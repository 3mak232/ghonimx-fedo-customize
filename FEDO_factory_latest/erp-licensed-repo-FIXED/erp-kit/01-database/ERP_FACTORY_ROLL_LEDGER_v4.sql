-- EXPERIMENTAL LOCAL ONLY. Not a deployable manufacturing release.
-- Internal roll-ledger primitives; no user-callable issue RPC and no accounting
-- postings. The future production-completion transaction must own accounting,
-- consumption, waste and finished-goods receipt. Do not use on production.
BEGIN;
CREATE TABLE IF NOT EXISTS public.factory_roll_controls(
  product_id uuid NOT NULL REFERENCES public.products(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  activated_at timestamptz NOT NULL DEFAULT now(),
  activated_by uuid NOT NULL REFERENCES public.profiles(id),
  PRIMARY KEY(product_id,warehouse_id)
);
CREATE TABLE IF NOT EXISTS public.factory_roll_moves(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE,
  roll_id uuid NOT NULL REFERENCES public.factory_rolls(id),
  movement_type text NOT NULL CHECK(movement_type IN ('receipt','consumption','waste')),
  quantity_delta numeric(14,3) NOT NULL CHECK(quantity_delta<>0),
  work_order_id uuid REFERENCES public.work_orders(id),
  stock_movement_id uuid REFERENCES public.stock_movements(id),
  unit_cost numeric(14,4) NOT NULL CHECK(unit_cost>=0),
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK((movement_type='receipt' AND quantity_delta>0 AND work_order_id IS NULL AND stock_movement_id IS NULL) OR
        (movement_type IN ('consumption','waste') AND quantity_delta<0 AND work_order_id IS NOT NULL AND stock_movement_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS factory_roll_one_receipt ON public.factory_roll_moves(roll_id) WHERE movement_type='receipt';
CREATE INDEX IF NOT EXISTS factory_roll_moves_roll ON public.factory_roll_moves(roll_id,created_at);
-- Transaction-scoped internal marker, inaccessible directly to API roles.
CREATE TABLE IF NOT EXISTS public.factory_roll_pending_receipts(
  tx bigint NOT NULL, product_id uuid NOT NULL, warehouse_id uuid NOT NULL,
  PRIMARY KEY(tx,product_id,warehouse_id)
);
CREATE TABLE IF NOT EXISTS public.factory_roll_purchase_requests(
  request_id uuid PRIMARY KEY, payload jsonb NOT NULL, invoice_id uuid NOT NULL REFERENCES public.purchase_invoices(id),
  created_by uuid NOT NULL REFERENCES public.profiles(id), created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.factory_roll_pending_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.factory_roll_purchase_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.factory_roll_pending_receipts,public.factory_roll_purchase_requests FROM PUBLIC,anon,authenticated;

ALTER TABLE public.factory_roll_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.factory_roll_moves ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.factory_roll_controls,public.factory_roll_moves FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.factory_roll_controls,public.factory_roll_moves TO authenticated;
DROP POLICY IF EXISTS factory_roll_controls_read ON public.factory_roll_controls;
CREATE POLICY factory_roll_controls_read ON public.factory_roll_controls FOR SELECT TO authenticated USING(public.has_perm('stk'));
DROP POLICY IF EXISTS factory_roll_moves_read ON public.factory_roll_moves;
CREATE POLICY factory_roll_moves_read ON public.factory_roll_moves FOR SELECT TO authenticated USING(public.has_perm('stk'));

-- RLS-respecting calculated roll remaining; only activated rolls have balances.
CREATE OR REPLACE VIEW public.factory_roll_balances WITH (security_invoker=true) AS
SELECT r.id AS roll_id,r.roll_code,r.product_id,r.warehouse_id,r.unit_id,r.color,r.width,r.original_qty,
       coalesce(sum(m.quantity_delta),0)::numeric(14,3) AS remaining_qty
FROM public.factory_rolls r JOIN public.factory_roll_controls c ON c.product_id=r.product_id AND c.warehouse_id=r.warehouse_id
LEFT JOIN public.factory_roll_moves m ON m.roll_id=r.id
GROUP BY r.id;
REVOKE ALL ON public.factory_roll_balances FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.factory_roll_balances TO authenticated;

-- Every registered roll is frozen while its product/warehouse is managed.
CREATE OR REPLACE FUNCTION public.factory_guard_roll_metadata() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') AND EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=OLD.product_id AND warehouse_id=OLD.warehouse_id) THEN
  RAISE EXCEPTION 'الرول ضمن صنف خاضع للتتبع؛ التعديل المباشر غير مدعوم';
 END IF;
 IF TG_OP IN ('INSERT','UPDATE') AND EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=NEW.product_id AND warehouse_id=NEW.warehouse_id)
    AND NOT (TG_OP='INSERT' AND EXISTS(SELECT 1 FROM factory_roll_pending_receipts WHERE tx=txid_current() AND product_id=NEW.product_id AND warehouse_id=NEW.warehouse_id)) THEN
  RAISE EXCEPTION 'تسجيل رول إضافي بعد التفعيل يتطلب مسار استلام ذري';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
DROP TRIGGER IF EXISTS factory_roll_metadata_guard ON public.factory_rolls;
CREATE TRIGGER factory_roll_metadata_guard BEFORE INSERT OR UPDATE OR DELETE ON public.factory_rolls FOR EACH ROW EXECUTE FUNCTION public.factory_guard_roll_metadata();

-- Deferred reconciliation denies legacy stock paths that would leave roll stock
-- inconsistent. Lock the stock row first, then read roll balances.
CREATE OR REPLACE FUNCTION public.factory_assert_roll_balance(p_product uuid,p_wh uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE qty_stock numeric; qty_roll numeric; bad bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=p_product AND warehouse_id=p_wh) THEN RETURN; END IF;
 SELECT qty INTO qty_stock FROM stock_balances WHERE product_id=p_product AND warehouse_id=p_wh FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'رصيد المخزن غير موجود للصنف المتتبع'; END IF;
 SELECT coalesce(sum(m.quantity_delta),0) INTO qty_roll FROM factory_roll_moves m JOIN factory_rolls r ON r.id=m.roll_id WHERE r.product_id=p_product AND r.warehouse_id=p_wh;
 SELECT count(*) INTO bad FROM (SELECT r.id,r.original_qty,coalesce(sum(m.quantity_delta),0) q FROM factory_rolls r LEFT JOIN factory_roll_moves m ON m.roll_id=r.id WHERE r.product_id=p_product AND r.warehouse_id=p_wh GROUP BY r.id) a WHERE a.q<0 OR a.q>a.original_qty;
 IF qty_stock<>qty_roll OR bad>0 THEN RAISE EXCEPTION 'اختلاف مخزون الصنف عن دفتر الرولات: مخزون %، رولات %',qty_stock,qty_roll; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.factory_stock_balance_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF TG_OP IN ('DELETE','UPDATE') THEN PERFORM factory_assert_roll_balance(OLD.product_id,OLD.warehouse_id); END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN PERFORM factory_assert_roll_balance(NEW.product_id,NEW.warehouse_id); END IF;
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS factory_stock_balance_guard ON public.stock_balances;
CREATE CONSTRAINT TRIGGER factory_stock_balance_guard AFTER INSERT OR UPDATE OR DELETE ON public.stock_balances DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.factory_stock_balance_guard();

CREATE OR REPLACE FUNCTION public.factory_roll_move_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p uuid; w uuid;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN RAISE EXCEPTION 'سجل حركة الرولات لا يقبل التعديل أو الحذف'; END IF;
 SELECT product_id,warehouse_id INTO p,w FROM factory_rolls WHERE id=NEW.roll_id;
 PERFORM factory_assert_roll_balance(p,w);
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS factory_roll_move_guard ON public.factory_roll_moves;
CREATE CONSTRAINT TRIGGER factory_roll_move_guard AFTER INSERT OR UPDATE OR DELETE ON public.factory_roll_moves DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.factory_roll_move_guard();

-- Activation cannot invent balances: all existing rolls together must match FEDO.
-- This is local-only pending an atomic tracked-purchase and return design.
CREATE OR REPLACE FUNCTION public.factory_activate_roll_control(p_product uuid,p_wh uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE stock numeric; q numeric; r record;
BEGIN
 PERFORM require_role('{admin,store}'); PERFORM require_perm('stk');
 SELECT qty INTO stock FROM stock_balances WHERE product_id=p_product AND warehouse_id=p_wh FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'لا يوجد رصيد لهذا الصنف'; END IF;
 IF EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=p_product AND warehouse_id=p_wh) THEN RETURN; END IF;
 SELECT coalesce(sum(original_qty),0) INTO q FROM factory_rolls WHERE product_id=p_product AND warehouse_id=p_wh;
 IF stock<=0 OR q<>stock THEN RAISE EXCEPTION 'لا يمكن تفعيل تتبع الرولات: مخزون %، رولات %',stock,q; END IF;
 INSERT INTO factory_roll_controls(product_id,warehouse_id,activated_by) VALUES(p_product,p_wh,auth.uid());
 FOR r IN SELECT * FROM factory_rolls WHERE product_id=p_product AND warehouse_id=p_wh ORDER BY id LOOP
   INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,unit_cost,created_by)
     VALUES(gen_random_uuid(),r.id,'receipt',r.original_qty,r.unit_cost,auth.uid());
 END LOOP;
 PERFORM log_event('create','factory_roll_controls',p_product::text,'تفعيل تجريبي لتتبع الرولات');
END $$;

-- Atomic credit purchase for ONE managed SKU and any number of rolls.
-- This uses FEDO create_purchase and records rolls in the same transaction;
-- normal untracked purchases for managed SKUs still fail reconciliation.
CREATE OR REPLACE FUNCTION public.factory_purchase_managed_rolls(p_request uuid,p_supplier uuid,p_wh uuid,p_product uuid,p_price numeric,p_rolls jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE payload jsonb; old factory_roll_purchase_requests; qty numeric:=0; x jsonb; invoice uuid; item uuid; r record;
BEGIN
 PERFORM require_role('{admin,accountant}'); PERFORM require_perm('purch'); PERFORM require_perm('stk');
 IF p_request IS NULL OR p_supplier IS NULL OR p_wh IS NULL OR p_product IS NULL OR p_price IS NULL OR p_price<0
    OR jsonb_typeof(p_rolls) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rolls)=0 THEN RAISE EXCEPTION 'بيانات شراء الرولات غير صحيحة'; END IF;
 payload:=jsonb_build_object('supplier',p_supplier,'warehouse',p_wh,'product',p_product,'price',p_price,'rolls',p_rolls);
 PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 SELECT * INTO old FROM factory_roll_purchase_requests WHERE request_id=p_request;
 IF FOUND THEN
   IF old.created_by<>auth.uid() OR old.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'مفتاح العملية مستخدم لبيانات مختلفة'; END IF;
   RETURN old.invoice_id;
 END IF;
 PERFORM 1 FROM factory_roll_controls WHERE product_id=p_product AND warehouse_id=p_wh FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'تتبع الرولات غير مفعّل لهذا الصنف والمخزن'; END IF;
 PERFORM 1 FROM stock_balances WHERE product_id=p_product AND warehouse_id=p_wh FOR UPDATE;
 FOR x IN SELECT value FROM jsonb_array_elements(p_rolls) LOOP
   IF coalesce((x->>'qty')::numeric,0)<=0 OR round((x->>'qty')::numeric,3)<>(x->>'qty')::numeric THEN RAISE EXCEPTION 'كمية رول غير صحيحة'; END IF;
   qty:=qty+(x->>'qty')::numeric;
 END LOOP;
 INSERT INTO factory_roll_pending_receipts(tx,product_id,warehouse_id) VALUES(txid_current(),p_product,p_wh);
 invoice:=create_purchase(p_supplier,p_wh,jsonb_build_array(jsonb_build_object('product_id',p_product,'qty',qty,'price',p_price)));
 SELECT id INTO item FROM purchase_invoice_items WHERE invoice_id=invoice AND product_id=p_product;
 PERFORM factory_register_rolls(p_request,'invoice',item,p_rolls);
 FOR r IN SELECT * FROM factory_rolls WHERE request_id=p_request ORDER BY id LOOP
   INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,unit_cost,created_by)
      VALUES(gen_random_uuid(),r.id,'receipt',r.original_qty,r.unit_cost,auth.uid());
 END LOOP;
 DELETE FROM factory_roll_pending_receipts WHERE tx=txid_current() AND product_id=p_product AND warehouse_id=p_wh;
 INSERT INTO factory_roll_purchase_requests(request_id,payload,invoice_id,created_by) VALUES(p_request,payload,invoice,auth.uid());
 PERFORM log_event('create','factory_roll_purchase_requests',p_request::text,'فاتورة شراء تجريبية برولات متتبعة');
 RETURN invoice;
END $$;
REVOKE ALL ON FUNCTION public.factory_purchase_managed_rolls(uuid,uuid,uuid,uuid,numeric,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_purchase_managed_rolls(uuid,uuid,uuid,uuid,numeric,jsonb) TO authenticated;

-- PRIVATE: called only by future atomic manufacturing-completion RPC (not built
-- yet). Revoked from all exposed roles. No GL posting yet: local tests only.
CREATE OR REPLACE FUNCTION public.factory_consume_roll_internal(p_request uuid,p_roll uuid,p_order uuid,p_qty numeric,p_kind text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r factory_rolls; existing factory_roll_moves; remain numeric; wo work_orders; mv uuid; result uuid; prior numeric;
BEGIN
 IF auth.uid() IS NULL OR p_request IS NULL OR p_roll IS NULL OR p_order IS NULL OR p_qty IS NULL OR p_qty<=0 OR round(p_qty,3)<>p_qty OR p_kind NOT IN ('consumption','waste') OR p_kind IS NULL THEN
   RAISE EXCEPTION 'بيانات الصرف غير صحيحة'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 SELECT * INTO existing FROM factory_roll_moves WHERE request_id=p_request;
 IF FOUND THEN
  IF existing.roll_id<>p_roll OR existing.work_order_id IS DISTINCT FROM p_order OR existing.quantity_delta<>-p_qty OR existing.movement_type<>p_kind OR existing.created_by<>auth.uid() THEN RAISE EXCEPTION 'مفتاح العملية مستخدم لبيانات مختلفة'; END IF;
  RETURN existing.id;
 END IF;
 SELECT * INTO wo FROM work_orders WHERE id=p_order FOR UPDATE;
 IF NOT FOUND OR wo.status IN ('Completed','Cancelled') THEN RAISE EXCEPTION 'أمر التصنيع غير متاح'; END IF;
 SELECT * INTO r FROM factory_rolls WHERE id=p_roll FOR UPDATE;
 IF NOT FOUND OR r.warehouse_id<>wo.warehouse_id OR NOT EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=r.product_id AND warehouse_id=r.warehouse_id) THEN RAISE EXCEPTION 'الرول غير متاح أو غير متتبع بالمخزن'; END IF;
 PERFORM 1 FROM stock_balances WHERE product_id=r.product_id AND warehouse_id=r.warehouse_id FOR UPDATE;
 SELECT coalesce(sum(quantity_delta),0) INTO remain FROM factory_roll_moves WHERE roll_id=p_roll;
 IF remain<p_qty THEN RAISE EXCEPTION 'المتبقي بالرول لا يكفي: %',remain; END IF;
 PERFORM assert_period_open(current_date);
 -- Existing FEDO helper creates a uniquely identified stock movement.
 PERFORM apply_stock(r.product_id,r.warehouse_id,-p_qty,'Sale','factory_roll_issue',p_request);
 SELECT id INTO mv FROM stock_movements WHERE doc_type='factory_roll_issue' AND doc_id=p_request ORDER BY created_at DESC LIMIT 1;
 IF mv IS NULL THEN RAISE EXCEPTION 'حركة مخزون مفقودة'; END IF;
 INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,work_order_id,stock_movement_id,unit_cost,created_by)
 VALUES(p_request,p_roll,p_kind,-p_qty,p_order,mv,r.unit_cost,auth.uid()) RETURNING id INTO result;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.factory_guard_roll_metadata(),public.factory_assert_roll_balance(uuid,uuid),public.factory_stock_balance_guard(),public.factory_roll_move_guard(),public.factory_consume_roll_internal(uuid,uuid,uuid,numeric,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.factory_activate_roll_control(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_activate_roll_control(uuid,uuid) TO authenticated;
COMMIT;
