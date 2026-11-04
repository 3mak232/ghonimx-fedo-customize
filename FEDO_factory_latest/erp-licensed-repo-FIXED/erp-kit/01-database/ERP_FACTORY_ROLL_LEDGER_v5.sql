-- ============================================================================
-- ERP_FACTORY_ROLL_LEDGER_v5.sql   (المرحلة 1 — دفتر الرولات التشغيلي)
--
-- EXPERIMENTAL / LOCAL-ONLY. Do not apply to a customer or production project.
-- يبني فوق ERP_FACTORY_CUSTOMIZE_v1.sql و ERP_FACTORY_ROLL_LEDGER_v4.sql
-- ولا يعيد بناء أي وحدة قائمة: يضيف أنواع حركة وسياسات وRPC آمنة فقط.
--
-- ما يقدمه هذا الملف:
--   1) دفتر رولات append-only بأنواع: استلام/صرف/هالك/بواقي/مرتجع مورد/تسوية.
--   2) رصيد الرول = original_qty + مجموع الحركات (لا يُخزَّن، لا يُعدَّل مباشرة).
--   3) تقسيم رول إلى بقية (splitting) بحركة 'remainder' مرتبطة بالرول الأم.
--   4) حركة واحدة تشمل صرف + هالك في نفس المعاملة مع منع الخصم المزدوج.
--   5) شراء آجل ذري لصنف واحد متتبّع بأي عدد من الرولات (v4) + واجهة شراء مقيدة.
--   6) تسوية تفعيل التتبع بحيث تُطابق تكلفة الرولات تكلفة المخزون.
--   7) صلاحيات: mfg للصرف، stk للتفعيل والتسوية، purch للشراء.
--
-- غير مشمول عمدًا (مراحل لاحقة): إكمال أمر التصنيع، اعتماد المخزن، الإلغاء،
-- القيود المحاسبية للتصنيع، البواقي كصنف مستقل. تبقى أرقام المخزون القابلة
-- للبيع في FEDO فقط ولا تتغير إلا عبر مسارات FEDO القائمة.
-- ============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1) أنواع حركة أوسع: نُبقي 'receipt'/'consumption'/'waste' ونضيف الباقي
-- ---------------------------------------------------------------------------
ALTER TABLE public.factory_roll_moves DROP CONSTRAINT IF EXISTS factory_roll_moves_movement_type_check;
ALTER TABLE public.factory_roll_moves DROP CONSTRAINT IF EXISTS factory_roll_moves_check;
ALTER TABLE public.factory_roll_moves
  ADD CONSTRAINT factory_roll_moves_movement_type_check
  CHECK (movement_type IN ('receipt','consumption','waste','remainder','scrap','return','adjustment'));

-- عمود ارتباط البقية بالرول الأم + مرجع خارجي حر (مورد/فاتورة/جرد)
ALTER TABLE public.factory_roll_moves ADD COLUMN IF NOT EXISTS parent_roll_id uuid REFERENCES public.factory_rolls(id);
ALTER TABLE public.factory_roll_moves ADD COLUMN IF NOT EXISTS ref_doc text;
-- تفصيل استخدام الرول: المستهلك فعليًا في المنتج / الهالك / البواقي الصغيرة.
-- مجموع الثلاثة = -quantity_delta حتى يبقى دفتر الرولات مطابقًا لحركة المخزون.
ALTER TABLE public.factory_roll_moves ADD COLUMN IF NOT EXISTS consumed_qty numeric(14,3);
ALTER TABLE public.factory_roll_moves ADD COLUMN IF NOT EXISTS waste_qty    numeric(14,3);
ALTER TABLE public.factory_roll_moves ADD COLUMN IF NOT EXISTS scrap_qty    numeric(14,3);
ALTER TABLE public.factory_roll_moves DROP CONSTRAINT IF EXISTS factory_roll_moves_breakdown_check;
ALTER TABLE public.factory_roll_moves
  ADD CONSTRAINT factory_roll_moves_breakdown_check CHECK (
    coalesce(consumed_qty,0)+coalesce(waste_qty,0)+coalesce(scrap_qty,0)>=0
    AND (movement_type<>'receipt' OR coalesce(consumed_qty,0)+coalesce(waste_qty,0)+coalesce(scrap_qty,0)=0)
  );

-- دفعات الرولات: نسمح بمصدر 'remainder' (بقية من رول) و'adjustment' (تسوية)
-- حتى يبقى مفتاح الرول الجديد موثقًا بمصدره ولا يعتمد على الافتراض.
ALTER TABLE public.factory_roll_batches DROP CONSTRAINT IF EXISTS factory_roll_batches_source_kind_check;
ALTER TABLE public.factory_roll_batches ADD CONSTRAINT factory_roll_batches_source_kind_check
  CHECK (source_kind IN ('invoice','receipt','remainder','adjustment'));

-- v4 جعل request_id فريدًا (حركة واحدة لكل طلب). نستبدله بفريدية (request_id, roll_id)
-- حتى يمكن صرف أكثر من رول في نفس طلب التصنيع، مع بقاء منع تكرار نفس الرول.
ALTER TABLE public.factory_roll_moves DROP CONSTRAINT IF EXISTS factory_roll_moves_request_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS factory_roll_moves_request_roll_key
  ON public.factory_roll_moves(request_id, roll_id);

-- receipt: +qty بدون أمر تصنيع. consumption/waste/scrap/remainder: -qty (البقية سالبة على الرول الأم).
-- return/adjustment قد تكون زيادة أو نقصًا ومسجّلة من مسار مستندي.
ALTER TABLE public.factory_roll_moves DROP CONSTRAINT IF EXISTS factory_roll_moves_sign_check;
ALTER TABLE public.factory_roll_moves
  ADD CONSTRAINT factory_roll_moves_sign_check CHECK (
    (movement_type='receipt'   AND quantity_delta>0 AND work_order_id IS NULL)
 OR (movement_type='remainder' AND quantity_delta<0 AND parent_roll_id IS NOT NULL)
 OR (movement_type IN ('consumption','waste','scrap') AND quantity_delta<0 AND work_order_id IS NOT NULL)
 OR (movement_type='return'     AND quantity_delta>0)
 OR (movement_type='adjustment')
  );

-- بقية واحدة فقط لكل رول أم، وحماية من بقية فوق المتاح
CREATE UNIQUE INDEX IF NOT EXISTS factory_roll_one_remainder
  ON public.factory_roll_moves(parent_roll_id) WHERE movement_type='remainder';

-- ---------------------------------------------------------------------------
-- 2) resolve الحارس القديم: الرول الجديد الناتج عن بقية مسموح أثناء التتبع
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_guard_roll_metadata() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_parent uuid;
BEGIN
  IF NEW.request_id IS NOT NULL THEN
    SELECT parent_roll_id INTO v_parent FROM factory_roll_moves
     WHERE movement_type='remainder' AND request_id=NEW.request_id;
  END IF;
  IF TG_OP IN ('UPDATE','DELETE') AND EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=OLD.product_id AND warehouse_id=OLD.warehouse_id) THEN
    RAISE EXCEPTION 'الرول ضمن صنف خاضع للتتبع؛ التعديل المباشر غير مدعوم';
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=NEW.product_id AND warehouse_id=NEW.warehouse_id)
     AND NOT (TG_OP='INSERT' AND (
            EXISTS(SELECT 1 FROM factory_roll_pending_receipts WHERE tx=txid_current() AND product_id=NEW.product_id AND warehouse_id=NEW.warehouse_id)
         OR v_parent IS NOT NULL)) THEN
    RAISE EXCEPTION 'تسجيل رول إضافي بعد التفعيل يتطلب مسار استلام ذري أو تقسيم بقية';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3) دفتر حركة الرولات: منع التعديل/الحذف والتحقق من عدم تجاوز الرصيد
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_roll_move_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p uuid; w uuid; v_after numeric; v_orig numeric;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN RAISE EXCEPTION 'سجل حركة الرولات لا يقبل التعديل أو الحذف'; END IF;
  SELECT product_id,warehouse_id,original_qty INTO p,w,v_orig FROM factory_rolls WHERE id=NEW.roll_id;
  PERFORM factory_assert_roll_balance(p,w);
  -- لا يجوز أن يصبح رصيد الرول سالبًا أو أكبر من الكمية المسجلة على الرول
  SELECT coalesce(sum(quantity_delta),0) INTO v_after FROM factory_roll_moves WHERE roll_id=NEW.roll_id;
  IF v_after<0 THEN RAISE EXCEPTION 'رصيد الرول سالب بعد الحركة: %',v_after; END IF;
  IF v_after>v_orig THEN RAISE EXCEPTION 'رصيد الرول يتجاوز كميته المسجلة: % > %',v_after,v_orig; END IF;
  RETURN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 4) عرض الأرصدة: نُبقي الأعمدة القديمة ونضيف الحقول التشغيلية
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.factory_roll_balances WITH (security_invoker=true) AS
SELECT r.id AS roll_id, r.roll_code, r.product_id, r.warehouse_id, r.unit_id, r.color, r.width,
       r.original_qty,
       coalesce(sum(m.quantity_delta),0)::numeric(14,3) AS remaining_qty,
       r.unit_cost,
       (coalesce(sum(m.quantity_delta),0)::numeric(14,4) * r.unit_cost)::numeric(14,2) AS value_remaining,
       r.received_date,
       exists(SELECT 1 FROM public.factory_roll_moves rm WHERE rm.parent_roll_id=r.id) AS is_split_source
FROM public.factory_rolls r
JOIN public.factory_roll_controls c ON c.product_id=r.product_id AND c.warehouse_id=r.warehouse_id
LEFT JOIN public.factory_roll_moves m ON m.roll_id=r.id
GROUP BY r.id;
REVOKE ALL ON public.factory_roll_balances FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.factory_roll_balances TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) صلاحية mfg الافتراضية لدور المستودع (بدونها لا يمكن لأحد صرف رول)
-- ---------------------------------------------------------------------------
INSERT INTO public.role_default_perms(role,perm)
SELECT 'store','mfg' WHERE EXISTS (SELECT 1 FROM information_schema.columns
  WHERE table_schema='public' AND table_name='role_default_perms' AND column_name='perm')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6) PRIVATE: صرف/هالك/هدر على مستوى الرول (يُستدعى من RPC عام أدناه أو من
--    إكمال التصنيع لاحقًا). يقفل الرول ويحوّل خصم المخزون العام عبر apply_stock
--    في نفس المعاملة، فلا يمكن أن ينفصل دفتر الرولات عن مخزون FEDO.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_roll_issue_internal(
  p_request uuid, p_roll uuid, p_order uuid, p_qty numeric, p_kind text, p_waste numeric, p_scrap numeric, p_note text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  r public.factory_rolls%ROWTYPE;
  wo public.work_orders%ROWTYPE;
  v_exist public.factory_roll_moves%ROWTYPE;
  v_remain numeric; v_total numeric; v_mv uuid; v_id uuid;
BEGIN
  p_waste := coalesce(p_waste,0); p_scrap := coalesce(p_scrap,0);
  IF p_request IS NULL OR p_roll IS NULL OR p_order IS NULL OR p_qty IS NULL
     OR round(p_qty,3)<>p_qty OR round(p_waste,3)<>p_waste OR round(p_scrap,3)<>p_scrap
     OR p_qty<0 OR p_waste<0 OR p_scrap<0
     OR p_kind NOT IN ('consumption','waste','scrap') THEN
    RAISE EXCEPTION 'بيانات الصرف غير صحيحة';
  END IF;
  v_total := p_qty + p_waste + p_scrap;
  IF v_total<=0 THEN RAISE EXCEPTION 'الكمية المصروفة صفر'; END IF;
  -- هوية الطلب: (request_id, roll_id) فريدة، فلا يمكن الخصم مرتين لنفس الطلب
  -- على نفس الرول، ويُرفض تكرار الطلب ببيانات مختلفة.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
  SELECT * INTO v_exist FROM factory_roll_moves WHERE request_id=p_request AND roll_id=p_roll;
  IF FOUND THEN
    IF v_exist.work_order_id IS DISTINCT FROM p_order
       OR v_exist.movement_type<>p_kind
       OR v_exist.quantity_delta<>-v_total
       OR coalesce(v_exist.consumed_qty,0)<>p_qty
       OR coalesce(v_exist.waste_qty,0)<>p_waste
       OR coalesce(v_exist.scrap_qty,0)<>p_scrap
       OR v_exist.created_by<>auth.uid() THEN
      RAISE EXCEPTION 'مفتاح العملية مستخدم لبيانات مختلفة';
    END IF;
    RETURN v_exist.id;
  END IF;
  SELECT * INTO wo FROM work_orders WHERE id=p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'أمر التصنيع غير موجود'; END IF;
  IF wo.status='Cancelled' THEN RAISE EXCEPTION 'أمر التصنيع ملغي'; END IF;
  SELECT * INTO r FROM factory_rolls WHERE id=p_roll FOR UPDATE;
  IF NOT FOUND OR r.warehouse_id<>wo.warehouse_id
     OR NOT EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=r.product_id AND warehouse_id=r.warehouse_id) THEN
    RAISE EXCEPTION 'الرول غير متاح أو غير متتبع بالمخزن';
  END IF;
  PERFORM 1 FROM stock_balances WHERE product_id=r.product_id AND warehouse_id=r.warehouse_id FOR UPDATE;
  SELECT coalesce(sum(quantity_delta),0) INTO v_remain FROM factory_roll_moves WHERE roll_id=p_roll;
  IF v_remain<v_total THEN RAISE EXCEPTION 'المتبقي بالرول لا يكفي: %',v_remain; END IF;
  PERFORM assert_period_open(current_date);
  PERFORM apply_stock(r.product_id,r.warehouse_id,-v_total,'Sale','factory_roll_issue',p_request);
  SELECT id INTO v_mv FROM stock_movements WHERE doc_type='factory_roll_issue' AND doc_id=p_request
   ORDER BY created_at DESC LIMIT 1;
  IF v_mv IS NULL THEN RAISE EXCEPTION 'حركة مخزون مفقودة'; END IF;
  INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,work_order_id,stock_movement_id,
                                 unit_cost,created_by,ref_doc,consumed_qty,waste_qty,scrap_qty)
    VALUES(p_request,p_roll,p_kind,-v_total,p_order,v_mv,r.unit_cost,auth.uid(),p_note,p_qty,p_waste,p_scrap)
    RETURNING id INTO v_id;
  PERFORM log_event('issue','factory_roll_moves',v_id::text,
    'صرف من الرول '||r.roll_code||' بمقدار '||v_total||' (هالك '||p_waste||'، بواقي '||p_scrap||')');
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.factory_roll_issue_internal(uuid,uuid,uuid,numeric,text,numeric,numeric,text) FROM PUBLIC,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 7) RPC عام للصرف من رول داخل أمر تصنيع (صلاحية mfg + stk)
-- ---------------------------------------------------------------------------
-- p_qty = الكمية التي دخلت الإنتاج فعليًا، p_waste = هالك، p_scrap = بواقي صغيرة.
-- الثلاثة تُخصم من نفس الرول في حركة واحدة، ولا تُسجَّل مرتين لنفس المفتاح.
CREATE OR REPLACE FUNCTION public.factory_issue_roll(
  p_request uuid, p_roll uuid, p_order uuid, p_qty numeric,
  p_kind text DEFAULT 'consumption', p_note text DEFAULT NULL,
  p_waste numeric DEFAULT 0, p_scrap numeric DEFAULT 0)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM require_perm('mfg');
  PERFORM require_perm('stk');
  IF current_setting('erp.factory_ledger',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'مسار الصرف من الرول غير مفعّل لهذه القاعدة (erp.factory_ledger)';
  END IF;
  RETURN factory_roll_issue_internal(p_request,p_roll,p_order,coalesce(p_qty,0),
           CASE WHEN p_kind IS NULL THEN 'consumption' ELSE p_kind END,
           coalesce(p_waste,0),coalesce(p_scrap,0),p_note);
END $$;
REVOKE ALL ON FUNCTION public.factory_issue_roll(uuid,uuid,uuid,numeric,text,text,numeric,numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_issue_roll(uuid,uuid,uuid,numeric,text,text,numeric,numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8) تقسيم رول إلى بقية: يُنشئ رولًا جديدًا بنفس بيانات المصدر وينقل إليه
--    الكمية المتبقية. الأصل يُستنفد، والبقية تحمل parent_roll_id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_split_roll_remainder(p_request uuid, p_roll uuid, p_keep numeric, p_new_code text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.factory_rolls%ROWTYPE; v_remain numeric; v_new uuid; v_exist record;
BEGIN
  PERFORM require_perm('stk');
  IF p_request IS NULL OR p_roll IS NULL OR p_keep IS NULL OR p_keep<0 OR round(p_keep,3)<>p_keep
     OR nullif(trim(p_new_code),'') IS NULL THEN RAISE EXCEPTION 'بيانات تقسيم البقية غير صحيحة'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
  SELECT m.id,m.roll_id INTO v_exist FROM factory_roll_moves m WHERE m.request_id=p_request AND m.movement_type='remainder';
  IF FOUND THEN
    IF v_exist.roll_id<>p_roll THEN RAISE EXCEPTION 'مفتاح العملية مستخدم لبيانات مختلفة'; END IF;
    RETURN (SELECT id FROM factory_rolls WHERE id IN
      (SELECT roll_id FROM factory_roll_moves WHERE parent_roll_id=p_roll LIMIT 1));
  END IF;
  SELECT * INTO r FROM factory_rolls WHERE id=p_roll FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الرول غير موجود'; END IF;
  IF NOT EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=r.product_id AND warehouse_id=r.warehouse_id) THEN
    RAISE EXCEPTION 'تقسيم البقية يتطلب تفعيل تتبع الرولات لهذا الصنف'; END IF;
  PERFORM 1 FROM stock_balances WHERE product_id=r.product_id AND warehouse_id=r.warehouse_id FOR UPDATE;
  SELECT coalesce(sum(quantity_delta),0) INTO v_remain FROM factory_roll_moves WHERE roll_id=p_roll;
  IF p_keep>v_remain THEN RAISE EXCEPTION 'البقية المطلوبة أكبر من المتاح بالرول: %',v_remain; END IF;
  IF EXISTS(SELECT 1 FROM factory_roll_moves WHERE parent_roll_id=p_roll AND movement_type='remainder') THEN
    RAISE EXCEPTION 'تم تقسيم هذا الرول من قبل'; END IF;
  -- الرول الأم يفقد البقية المنقولة، والرول الجديد يستلمها في نفس المعاملة.
  -- الأصل: حركة 'remainder' سالبة بقيمة البقية؛ الجديد: حركة 'receipt' مجانية بقيمة البقية.
  -- تُسجَّل حركة الأصل أولًا لأن حارس إنشاء الرولات يتحقق منها.
  INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,unit_cost,created_by,parent_roll_id,ref_doc)
    VALUES(p_request,p_roll,'remainder',-p_keep,r.unit_cost,auth.uid(),p_roll,'تقسيم بقية إلى '||trim(p_new_code));
  INSERT INTO factory_roll_batches(request_id,source_kind,source_item_id,payload,created_by)
    VALUES(p_request,'remainder',p_roll,jsonb_build_object('parent_roll',p_roll,'qty',p_keep,'code',trim(p_new_code)),auth.uid());
  INSERT INTO factory_rolls(roll_code,request_id,product_id,warehouse_id,supplier_id,unit_id,color,width,original_qty,unit_cost,received_date)
    VALUES(trim(p_new_code),p_request,r.product_id,r.warehouse_id,r.supplier_id,r.unit_id,r.color,r.width,p_keep,r.unit_cost,r.received_date)
    RETURNING id INTO v_new;
  INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,unit_cost,created_by,parent_roll_id,ref_doc)
    VALUES(gen_random_uuid(),v_new,'receipt',p_keep,r.unit_cost,auth.uid(),p_roll,'بقية من '||r.roll_code);
  PERFORM log_event('split','factory_rolls',v_new::text,'تقسيم بقية من '||r.roll_code||' بمقدار '||p_keep);
  RETURN v_new;
END $$;
REVOKE ALL ON FUNCTION public.factory_split_roll_remainder(uuid,uuid,numeric,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_split_roll_remainder(uuid,uuid,numeric,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8b) بدء التتبع لصنف جديد برصيد صفري (قبل أول شراء).
--     v4 يمنع الشراء المتتبع لصنف غير مفعّل، والتفعيل يمنع وجود فرق بين
--     المخزون والرولات. لذلك نحتاج نقطة بداية آمنة: تفعيل عند رصيد صفر
--     بدون رولات، وهذا الوحيد الذي يجعل 0 = 0. أي صنف له رصيد قائم يجب أن
--     يُفعّل بالمسار القديم بعد تسجيل رولاته.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_enable_roll_tracking(p_product uuid, p_warehouse uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_stock numeric; v_rolls numeric;
BEGIN
  PERFORM require_perm('stk');
  IF EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=p_product AND warehouse_id=p_warehouse) THEN
    RAISE EXCEPTION 'تتبع الرولات مفعّل من قبل'; END IF;
  IF NOT EXISTS(SELECT 1 FROM products WHERE id=p_product AND active) THEN
    RAISE EXCEPTION 'الصنف غير موجود أو غير نشط'; END IF;
  SELECT coalesce(qty,0) INTO v_stock FROM stock_balances WHERE product_id=p_product AND warehouse_id=p_warehouse;
  v_stock := coalesce(v_stock,0);
  SELECT coalesce(sum(original_qty),0) INTO v_rolls FROM factory_rolls
   WHERE product_id=p_product AND warehouse_id=p_warehouse;
  IF v_stock<>0 OR v_rolls<>0 THEN
    RAISE EXCEPTION 'البدء برصيد صفري فقط: الرصيد الحالي % والرولات %. للصنف القائم سجّل رولاته ثم استخدم factory_activate_roll_control',v_stock,v_rolls;
  END IF;
  INSERT INTO factory_roll_controls(product_id,warehouse_id,activated_by) VALUES(p_product,p_warehouse,auth.uid());
  PERFORM log_event('create','factory_roll_controls',p_product::text,'بدء تتبع الرولات من رصيد صفري');
END $$;
REVOKE ALL ON FUNCTION public.factory_enable_roll_tracking(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_enable_roll_tracking(uuid,uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9) شراء الرولات: يضمن وجود صفوف الأرصدة قبل الاستدعاء ثم يستخدم v4
--    factory_purchase_managed_rolls — التي تنشئ فاتورة FEDO والقيود والرولات
--    والحركات في معاملة واحدة.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_buy_rolls(
  p_request uuid, p_supplier uuid, p_warehouse uuid, p_product uuid, p_price numeric, p_rolls jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_inv uuid;
BEGIN
  PERFORM require_perm('purch');
  PERFORM require_perm('stk');
  IF current_setting('erp.factory_ledger',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'مسار شراء الرولات غير مفعّل لهذه القاعدة (erp.factory_ledger)';
  END IF;
  IF jsonb_typeof(p_rolls) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rolls)=0 THEN
    RAISE EXCEPTION 'بيانات شراء الرولات غير صحيحة'; END IF;
  IF NOT EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=p_product AND warehouse_id=p_warehouse) THEN
    RAISE EXCEPTION 'تتبع الرولات غير مفعّل لهذا الصنف والمخزن؛ استخدم factory_enable_roll_tracking أولًا أو فعّل التتبع بعد تسجيل رولات المخزون القائم';
  END IF;
  v_inv := factory_purchase_managed_rolls(p_request,p_supplier,p_warehouse,p_product,p_price,p_rolls);
  PERFORM log_event('purchase','factory_rolls',v_inv::text,'شراء رولات متتبعة بالطلب '||coalesce(p_request::text,''));
  RETURN v_inv;
END $$;
REVOKE ALL ON FUNCTION public.factory_buy_rolls(uuid,uuid,uuid,uuid,numeric,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_buy_rolls(uuid,uuid,uuid,uuid,numeric,jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10) تسوية تكلفة الرولات مع متوسط تكلفة الصنف قبل التفعيل — إلزامية
--     v4 يسجل حركة استلام بقيمة unit_cost لكل رول عند التفعيل. إذا اختلفت
--     عن avg_cost في FEDO تختلف قيمة المخزون عن قيمة دفتر الرولات.
--     لذلك نمنع التفعيل قبل المعايرة بدل إبقاء رقم مضلل.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_normalize_roll_costs(p_product uuid, p_warehouse uuid)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_avg numeric; n int:=0;
BEGIN
  PERFORM require_perm('stk');
  IF EXISTS(SELECT 1 FROM factory_roll_controls WHERE product_id=p_product AND warehouse_id=p_warehouse) THEN
    RAISE EXCEPTION 'لا يمكن تعديل تكلفة الرولات بعد تفعيل التتبع';
  END IF;
  SELECT coalesce(avg_cost,0) INTO v_avg FROM products WHERE id=p_product;
  IF v_avg IS NULL THEN RAISE EXCEPTION 'الصنف غير موجود'; END IF;
  UPDATE factory_rolls SET unit_cost=v_avg
   WHERE product_id=p_product AND warehouse_id=p_warehouse AND unit_cost IS DISTINCT FROM v_avg;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n>0 THEN
    PERFORM log_event('adjust','factory_rolls',p_product::text,'توحيد تكلفة الرولات مع متوسط تكلفة الصنف');
  END IF;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.factory_normalize_roll_costs(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_normalize_roll_costs(uuid,uuid) TO authenticated;

-- معايرة إلزامية: إن وُجدت رولات غير مسعّرة بمتوسط الصنف يُرفض التفعيل
CREATE OR REPLACE FUNCTION public.factory_require_roll_costs() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_avg numeric; v_bad int;
BEGIN
  SELECT coalesce(avg_cost,0) INTO v_avg FROM products WHERE id=NEW.product_id;
  SELECT count(*) INTO v_bad FROM factory_rolls
   WHERE product_id=NEW.product_id AND warehouse_id=NEW.warehouse_id AND unit_cost<>v_avg;
  IF v_bad>0 THEN
    RAISE EXCEPTION 'لا يمكن تفعيل التتبع قبل معايرة تكلفة % رول مع متوسط تكلفة الصنف (factory_normalize_roll_costs)',v_bad;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS factory_require_roll_costs ON public.factory_roll_controls;
CREATE TRIGGER factory_require_roll_costs BEFORE INSERT ON public.factory_roll_controls
  FOR EACH ROW EXECUTE FUNCTION public.factory_require_roll_costs();
REVOKE ALL ON FUNCTION public.factory_require_roll_costs() FROM PUBLIC,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 11) مفتاح تشغيل المسار: erp.factory_ledger
--     RPC الشراء/الصرف ترفض العمل إلا إذا ضُبط على 'on' لهذه القاعدة، حتى لا
--     ينشط تتبع الرولات بالخطأ على قاعدة قائمة. لا يُضبط هنا تلقائيًا؛
--     اضبطه يدويًا على قاعدة الاختبار:
--       ALTER DATABASE fedo_factory_test SET erp.factory_ledger = 'on';
--     ويمكن ضبطه لجلسة واحدة أثناء الاختبار:
--       SELECT set_config('erp.factory_ledger','on',false);
-- ---------------------------------------------------------------------------

COMMIT;
