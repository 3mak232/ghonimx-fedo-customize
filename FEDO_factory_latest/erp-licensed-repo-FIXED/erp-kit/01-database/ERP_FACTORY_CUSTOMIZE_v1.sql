-- FEDO FACTORY: EXPERIMENTAL FOUNDATION ONLY. DO NOT APPLY TO PRODUCTION.
-- Registers metadata against existing postings; does NOT implement usable roll stock,
-- manufacturing, returns, order fulfillment, or factory accounting. See design/report.
BEGIN;

CREATE TABLE IF NOT EXISTS public.factory_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_product_id uuid NOT NULL REFERENCES public.products(id),
  variant_product_id uuid NOT NULL UNIQUE REFERENCES public.products(id),
  color text NOT NULL CHECK(length(trim(color))>0),
  size_label text NOT NULL CHECK(length(trim(size_label))>0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  CHECK(parent_product_id <> variant_product_id),
  UNIQUE(parent_product_id,color,size_label)
);
CREATE TABLE IF NOT EXISTS public.factory_roll_batches (
  request_id uuid PRIMARY KEY,
  source_kind text NOT NULL CHECK(source_kind IN ('invoice','receipt')),
  source_item_id uuid NOT NULL,
  payload jsonb NOT NULL,
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.factory_rolls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  roll_code text NOT NULL UNIQUE CHECK(length(trim(roll_code))>0),
  request_id uuid NOT NULL REFERENCES public.factory_roll_batches(request_id),
  product_id uuid NOT NULL REFERENCES public.products(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  supplier_id uuid NOT NULL REFERENCES public.suppliers(id),
  unit_id uuid NOT NULL REFERENCES public.units(id),
  color text NOT NULL CHECK(length(trim(color))>0),
  width numeric(14,3) NOT NULL CHECK(width>0),
  original_qty numeric(14,3) NOT NULL CHECK(original_qty>0),
  unit_cost numeric(14,4) NOT NULL CHECK(unit_cost>=0),
  received_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS factory_roll_batches_source_idx ON public.factory_roll_batches(source_kind,source_item_id);
CREATE INDEX IF NOT EXISTS factory_rolls_product_wh_idx ON public.factory_rolls(product_id,warehouse_id);
ALTER TABLE public.factory_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.factory_roll_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.factory_rolls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.factory_variants,public.factory_roll_batches,public.factory_rolls FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.factory_variants,public.factory_roll_batches,public.factory_rolls TO authenticated;
DROP POLICY IF EXISTS factory_variants_read ON public.factory_variants;
CREATE POLICY factory_variants_read ON public.factory_variants FOR SELECT TO authenticated USING(public.has_perm('prod'));
DROP POLICY IF EXISTS factory_batches_read ON public.factory_roll_batches;
CREATE POLICY factory_batches_read ON public.factory_roll_batches FOR SELECT TO authenticated USING(public.has_perm('stk'));
DROP POLICY IF EXISTS factory_rolls_read ON public.factory_rolls;
CREATE POLICY factory_rolls_read ON public.factory_rolls FOR SELECT TO authenticated USING(public.has_perm('stk'));

-- Variant uses a *distinct existing product SKU*. All FEDO sales/stock/price-list paths
-- therefore continue using their existing product_id. It is not automatic UI support.
CREATE OR REPLACE FUNCTION public.factory_link_variant(p_parent uuid,p_variant uuid,p_color text,p_size text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v uuid;
BEGIN
  PERFORM public.require_role('{admin,accountant,store}');
  PERFORM public.require_perm('prod');
  IF p_parent=p_variant OR NOT EXISTS(SELECT 1 FROM products WHERE id=p_parent AND active)
    OR NOT EXISTS(SELECT 1 FROM products WHERE id=p_variant AND active AND code IS NOT NULL AND length(trim(code))>0)
  THEN RAISE EXCEPTION 'المنتج الأساسي والتركيبة يجب أن يكونا صنفين نشطين مختلفين، وللتركيبة كود'; END IF;
  INSERT INTO factory_variants(parent_product_id,variant_product_id,color,size_label,created_by)
  VALUES(p_parent,p_variant,trim(p_color),trim(p_size),auth.uid()) RETURNING id INTO v;
  PERFORM public.log_event('create','factory_variants',v::text,'ربط تركيبة بصنف');
  RETURN v;
END $$;

-- Only annotates existing purchase stock. Never posts stock or changes accounting.
-- A receipt-derived invoice is rejected to avoid registering the same receipt twice.
-- Serializes competing allocations by locking the original item.
CREATE OR REPLACE FUNCTION public.factory_register_rolls(p_request uuid,p_kind text,p_item uuid,p_rolls jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE x jsonb; v_product uuid; v_wh uuid; v_supplier uuid; v_unit uuid; v_cost numeric; v_date date;
        v_qty numeric; v_alloc numeric; v_total numeric:=0; v_payload jsonb; old_batch factory_roll_batches;
BEGIN
  PERFORM public.require_role('{admin,accountant,store}');
  PERFORM public.require_perm('stk');
  IF p_request IS NULL OR p_kind NOT IN ('invoice','receipt') OR p_item IS NULL
     OR jsonb_typeof(p_rolls) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rolls)=0 THEN
    RAISE EXCEPTION 'بيانات التسجيل غير صحيحة'; END IF;
  v_payload:=jsonb_build_object('kind',p_kind,'item',p_item,'rolls',p_rolls);
  -- xact-scoped lock serializes repeated request ids, including across different source items.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
  SELECT * INTO old_batch FROM factory_roll_batches WHERE request_id=p_request;
  IF FOUND THEN
    IF old_batch.payload IS DISTINCT FROM v_payload OR old_batch.created_by<>auth.uid() THEN
      RAISE EXCEPTION 'مفتاح العملية مستخدم لبيانات أو مستخدم مختلف'; END IF;
    RETURN p_request;
  END IF;
  IF p_kind='invoice' THEN
    SELECT i.product_id,h.warehouse_id,h.supplier_id,i.qty,i.unit_price,h.date,p.unit_id
      INTO v_product,v_wh,v_supplier,v_qty,v_cost,v_date,v_unit
      FROM purchase_invoice_items i JOIN purchase_invoices h ON h.id=i.invoice_id
      JOIN products p ON p.id=i.product_id WHERE i.id=p_item AND h.status<>'Cancelled'
      AND coalesce(h.notes,'') NOT LIKE 'GRN:%' FOR UPDATE OF i;
  ELSE
    SELECT i.product_id,h.warehouse_id,h.supplier_id,i.qty,i.unit_cost,h.date,p.unit_id
      INTO v_product,v_wh,v_supplier,v_qty,v_cost,v_date,v_unit
      FROM goods_receipt_items i JOIN goods_receipts h ON h.id=i.receipt_id
      JOIN products p ON p.id=i.product_id WHERE i.id=p_item AND h.status='Received' FOR UPDATE OF i;
  END IF;
  IF NOT FOUND OR v_unit IS NULL THEN RAISE EXCEPTION 'بند المصدر غير متاح أو بلا وحدة؛ لفات فاتورة الاستلام تسجل من إذن الاستلام'; END IF;
  SELECT coalesce(sum(r.original_qty),0) INTO v_alloc FROM factory_rolls r
    JOIN factory_roll_batches b ON b.request_id=r.request_id
    WHERE b.source_kind=p_kind AND b.source_item_id=p_item;
  FOR x IN SELECT value FROM jsonb_array_elements(p_rolls) LOOP
    IF nullif(trim(x->>'code'),'') IS NULL OR nullif(trim(x->>'color'),'') IS NULL
       OR coalesce((x->>'width')::numeric,0)<=0 OR coalesce((x->>'qty')::numeric,0)<=0
       OR round((x->>'qty')::numeric,3)<>(x->>'qty')::numeric
       OR round((x->>'width')::numeric,3)<>(x->>'width')::numeric THEN
       RAISE EXCEPTION 'بيانات الرول غير صحيحة'; END IF;
    v_total:=v_total+(x->>'qty')::numeric;
  END LOOP;
  IF v_alloc+v_total>v_qty THEN RAISE EXCEPTION 'مجموع الرولات يتجاوز كمية البند'; END IF;
  INSERT INTO factory_roll_batches(request_id,source_kind,source_item_id,payload,created_by)
    VALUES(p_request,p_kind,p_item,v_payload,auth.uid());
  FOR x IN SELECT value FROM jsonb_array_elements(p_rolls) LOOP
    INSERT INTO factory_rolls(roll_code,request_id,product_id,warehouse_id,supplier_id,unit_id,color,width,original_qty,unit_cost,received_date)
      VALUES(trim(x->>'code'),p_request,v_product,v_wh,v_supplier,v_unit,trim(x->>'color'),(x->>'width')::numeric,(x->>'qty')::numeric,v_cost,v_date);
  END LOOP;
  PERFORM public.log_event('create','factory_roll_batches',p_request::text,'تسجيل بيانات رولات على بند شراء قائم');
  RETURN p_request;
END $$;
REVOKE ALL ON FUNCTION public.factory_link_variant(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.factory_register_rolls(uuid,text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_link_variant(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.factory_register_rolls(uuid,text,uuid,jsonb) TO authenticated;

-- Legacy RPC hardening only; original stock behavior remains unsuitable for factory.
CREATE OR REPLACE FUNCTION create_work_order(p_bom uuid,p_warehouse uuid,p_qty numeric,p_labor numeric DEFAULT 0,p_overhead numeric DEFAULT 0) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b boms; v uuid:=gen_random_uuid(); num text;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); PERFORM require_perm('mfg'); SELECT * INTO b FROM boms WHERE id=p_bom AND active; IF NOT FOUND THEN RAISE EXCEPTION 'BOM غير متاح'; END IF;
  IF p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;
  num:='WO-'||(1000+nextval('seq_wo')); INSERT INTO work_orders(id,number,bom_id,warehouse_id,planned_qty,labor_cost,overhead_cost) VALUES(v,num,b.id,p_warehouse,p_qty,p_labor,p_overhead); RETURN v;
END $$;
CREATE OR REPLACE FUNCTION complete_work_order(p_order uuid) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE w work_orders; b boms; bi record; v_material_cost numeric:=0; v_total_cost numeric:=0; je uuid;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); PERFORM require_perm('mfg');
  SELECT * INTO w FROM work_orders WHERE id=p_order FOR UPDATE; IF NOT FOUND OR w.status IN('Completed','Cancelled') THEN RAISE EXCEPTION 'أمر التصنيع غير متاح'; END IF;
  SELECT * INTO b FROM boms WHERE id=w.bom_id;
  FOR bi IN SELECT * FROM bom_items WHERE bom_id=b.id LOOP
    PERFORM apply_stock(bi.component_product_id,w.warehouse_id,-(bi.qty*w.planned_qty),'Sale','work_order',w.id);
    v_material_cost:=v_material_cost+bi.qty*w.planned_qty*(SELECT avg_cost FROM products WHERE id=bi.component_product_id);
  END LOOP;
  v_total_cost:=round(v_material_cost+w.labor_cost+w.overhead_cost,2);
  PERFORM apply_stock(b.product_id,w.warehouse_id,w.planned_qty,'Purchase','work_order',w.id);
  UPDATE products SET avg_cost=CASE WHEN w.planned_qty>0 THEN v_total_cost/w.planned_qty ELSE avg_cost END WHERE id=b.product_id;
  IF v_total_cost>0 THEN
    je:=gen_random_uuid();
    BEGIN
      INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,w.date,'إتمام تصنيع '||w.number,'work_order',w.id,(SELECT default_branch FROM company_settings WHERE id=1));
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1200',v_total_cost,0);
      IF v_material_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1200',0,round(v_material_cost,2)); END IF;
      IF w.labor_cost+w.overhead_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'2200',0,round(w.labor_cost+w.overhead_cost,2)); END IF;
    END;
  END IF;
  UPDATE work_orders SET status='Completed',produced_qty=planned_qty,material_cost=round(v_material_cost,2),total_cost=v_total_cost WHERE id=w.id;
  PERFORM log_event('complete','work_orders',w.id::text,'أكمل أمر تصنيع بتكلفة '||v_total_cost); RETURN v_total_cost;
END $$;

COMMIT;
