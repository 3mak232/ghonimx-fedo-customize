-- ============================================================================
-- ERP_FACTORY_PRODUCTION_v6.sql   (المرحلة 2 — الإنتاج الجزئي والاعتماد والإلغاء)
--
-- EXPERIMENTAL / LOCAL-ONLY. يبني فوق v1 + v4 + v5 ولا يعيد بناء أي وحدة FEDO.
-- يعالج: BUG-02 (كمية إنتاج فعلية) · BUG-03 (اعتماد المخزن) · BUG-06 (الإلغاء)
--         + القيود المحاسبية القابلة لإعادة البناء للتصنيع.
--
-- المبدأ: أمر التصنيع لا يمس المخزون. تُسجَّل "دفعة إنتاج" بالكميات الفعلية
-- (المستهلك/الهالك/البواقي/الصافي)، تُخصم موادها من دفتر الرولات عند التسجيل،
-- ثم تُضاف للكمية القابلة للبيع **فقط** عند اعتماد مسؤول المخزن.
--
-- الحسابات:
--   1200 المخزون · 1210 إنتاج تحت التشغيل · 2200 مستحق التصنيع
--   6100 هالك التصنيع (نسبة للخسارة)
-- ============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 0) الحساب المحاسبي الجديد
-- ---------------------------------------------------------------------------
INSERT INTO public.accounts(code,name,type) VALUES ('1210','Work In Process - Manufacturing','Asset')
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1) أعمدة أمر التصنيع: مسار الإنتاج الفعلي
-- ---------------------------------------------------------------------------
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS production_mode text NOT NULL DEFAULT 'legacy';
ALTER TABLE public.work_orders ALTER COLUMN production_mode SET DEFAULT 'legacy';
UPDATE public.work_orders SET production_mode='legacy' WHERE production_mode IS NULL;
ALTER TABLE public.work_orders DROP CONSTRAINT IF EXISTS work_orders_production_mode_check;
ALTER TABLE public.work_orders ADD CONSTRAINT work_orders_production_mode_check
  CHECK (production_mode IN ('legacy','batched'));

-- يُطلب الاعتماد؟ افتراضيًا نعم (BUG-03). يمكن للمدير تعطيله لكل أمر.
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS requires_approval boolean NOT NULL DEFAULT true;
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS completed_at timestamptz;
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS cancel_reason text;
ALTER TABLE public.work_orders ADD COLUMN IF NOT EXISTS closed_by uuid REFERENCES public.profiles(id);

-- ---------------------------------------------------------------------------
-- 2) دفعات الإنتاج: سجل append-only لكل دفعة فعلية
--    good_qty = الكمية الصالحة المنتجة (تدخل المراحل التالية)
--    waste_qty = هالك المنتج النهائي · scrap_qty = بواقي/قصاصات إنتاج
--    approved_* = ما اعتمده المخزن فعلًا (قد يكون أقل من الصالح)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.work_order_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_no int NOT NULL CHECK (batch_no>0),
  work_order_id uuid NOT NULL REFERENCES public.work_orders(id),
  request_id uuid NOT NULL UNIQUE,
  payload jsonb NOT NULL,
  good_qty numeric(14,3) NOT NULL DEFAULT 0 CHECK (good_qty>=0),
  waste_qty numeric(14,3) NOT NULL DEFAULT 0 CHECK (waste_qty>=0),
  scrap_qty numeric(14,3) NOT NULL DEFAULT 0 CHECK (scrap_qty>=0),
  approved_qty numeric(14,3) NOT NULL DEFAULT 0 CHECK (approved_qty>=0),
  approved_batch_id uuid UNIQUE,
  material_cost numeric(14,2) NOT NULL DEFAULT 0 CHECK (material_cost>=0),
  waste_cost numeric(14,2) NOT NULL DEFAULT 0 CHECK (waste_cost>=0),
  scrap_cost numeric(14,2) NOT NULL DEFAULT 0 CHECK (scrap_cost>=0),
  recovered_value numeric(14,2) NOT NULL DEFAULT 0 CHECK (recovered_value>=0),  -- قيمة البواقي المستردة
  labor_cost numeric(14,2) NOT NULL DEFAULT 0 CHECK (labor_cost>=0),
  overhead_cost numeric(14,2) NOT NULL DEFAULT 0 CHECK (overhead_cost>=0),
  unit_cost numeric(14,4) NOT NULL DEFAULT 0 CHECK (unit_cost>=0),
  approved_value numeric(14,2) NOT NULL DEFAULT 0 CHECK (approved_value>=0),
  status text NOT NULL DEFAULT 'recorded' CHECK (status IN ('recorded','approved','cancelled')),
  rejection_reason text,
  recorded_by uuid NOT NULL REFERENCES public.profiles(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  approved_by uuid REFERENCES public.profiles(id),
  approved_at timestamptz,
  cancelled_by uuid REFERENCES public.profiles(id),
  cancelled_at timestamptz,
  UNIQUE (work_order_id, batch_no),
  CHECK (approved_qty<=good_qty),
  CHECK ((status='approved') = (approved_at IS NOT NULL)),
  CHECK ((status='cancelled') = (cancelled_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS work_order_batches_wo_idx ON public.work_order_batches(work_order_id, batch_no);

-- مكوّنات الدفعة: كل صف يربط رولًا أو صنفًا مستقلًا بالاستهلاك الفعلي
CREATE TABLE IF NOT EXISTS public.work_order_batch_uses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.work_order_batches(id) ON DELETE CASCADE,
  component_product_id uuid NOT NULL REFERENCES public.products(id),
  roll_id uuid REFERENCES public.factory_rolls(id),
  roll_move_id uuid REFERENCES public.factory_roll_moves(id),
  consumed_qty numeric(14,3) NOT NULL CHECK (consumed_qty>0),
  waste_qty numeric(14,3) NOT NULL DEFAULT 0 CHECK (waste_qty>=0),
  scrap_qty numeric(14,3) NOT NULL DEFAULT 0 CHECK (scrap_qty>=0),
  unit_cost numeric(14,4) NOT NULL CHECK (unit_cost>=0),
  stock_movement_id uuid REFERENCES public.stock_movements(id),
  UNIQUE (batch_id, roll_id)
);
CREATE INDEX IF NOT EXISTS work_order_batch_uses_batch ON public.work_order_batch_uses(batch_id);

-- ربط حركة الرول بالدفعة (يُملأ بعد إنشاء الدفعة) — إضافة عمود فقط
ALTER TABLE public.factory_roll_moves ADD COLUMN IF NOT EXISTS production_batch_id uuid REFERENCES public.work_order_batches(id);
CREATE INDEX IF NOT EXISTS factory_roll_moves_batch ON public.factory_roll_moves(production_batch_id);

-- ---------------------------------------------------------------------------
-- 3) الصلاحيات: جدولان للقراءة فقط مع بقية الأدوار
-- ---------------------------------------------------------------------------
ALTER TABLE public.work_order_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_batch_uses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.work_order_batches, public.work_order_batch_uses FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.work_order_batches, public.work_order_batch_uses TO authenticated;
DROP POLICY IF EXISTS wob_read ON public.work_order_batches;
CREATE POLICY wob_read ON public.work_order_batches FOR SELECT TO authenticated
  USING (public.has_perm('mfg') OR public.has_perm('stk') OR public.has_perm('jr'));
DROP POLICY IF EXISTS wobu_read ON public.work_order_batch_uses;
CREATE POLICY wobu_read ON public.work_order_batch_uses FOR SELECT TO authenticated
  USING (public.has_perm('mfg') OR public.has_perm('stk') OR public.has_perm('jr'));

-- منع أي تعديل مباشر: الدفعات تُدار فقط عبر RPC
CREATE OR REPLACE FUNCTION public.factory_batch_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  -- الكميات والأمر والحالة: غير قابلة للتعديل من الـAPI مباشرة
  IF TG_OP='UPDATE' AND (
       NEW.good_qty IS DISTINCT FROM OLD.good_qty OR NEW.waste_qty IS DISTINCT FROM OLD.waste_qty
    OR NEW.scrap_qty IS DISTINCT FROM OLD.scrap_qty OR NEW.work_order_id IS DISTINCT FROM OLD.work_order_id)
  THEN RAISE EXCEPTION 'الكميات في دفعة الإنتاج غير قابلة للتعديل'; END IF;
  -- التكلفة تُكتب بواسطة RPC التسجيل مرة واحدة؛ مقفولة بعد الاعتماد
  IF TG_OP='UPDATE' AND OLD.status<>'recorded' AND (
       NEW.unit_cost IS DISTINCT FROM OLD.unit_cost OR NEW.material_cost IS DISTINCT FROM OLD.material_cost
    OR NEW.labor_cost IS DISTINCT FROM OLD.labor_cost OR NEW.overhead_cost IS DISTINCT FROM OLD.overhead_cost)
  THEN RAISE EXCEPTION 'تكلفة الدفعة مقفولة بعد الاعتماد'; END IF;
  IF TG_OP='UPDATE' AND OLD.status<>'recorded' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'حالة الدفعة المعتمدة/الملغاة نهائية'; END IF;
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'لا يمكن حذف دفعة إنتاج'; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS factory_batch_guard ON public.work_order_batches;
CREATE TRIGGER factory_batch_guard BEFORE UPDATE OR DELETE ON public.work_order_batches
  FOR EACH ROW EXECUTE FUNCTION public.factory_batch_guard();
REVOKE ALL ON FUNCTION public.factory_batch_guard() FROM PUBLIC,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 4) عرض أرصدة الإنتاج لكل أمر (قابل للبيع / تحت الاعتماد / الهالك)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.work_order_production WITH (security_invoker=true) AS
SELECT w.id AS work_order_id, w.number, w.status, w.production_mode, w.planned_qty,
       w.warehouse_id, w.bom_id,
       coalesce(sum(b.good_qty),0)::numeric(14,3)     AS good_qty,
       coalesce(sum(b.approved_qty),0)::numeric(14,3) AS approved_qty,
       (coalesce(sum(b.good_qty),0)-coalesce(sum(b.approved_qty),0))::numeric(14,3) AS pending_approval_qty,
       coalesce(sum(b.waste_qty),0)::numeric(14,3)    AS waste_qty,
       coalesce(sum(b.scrap_qty),0)::numeric(14,3)    AS scrap_qty,
       coalesce(sum(b.material_cost),0)::numeric(14,2) AS material_cost,
       coalesce(sum(b.waste_cost),0)::numeric(14,2)    AS waste_cost,
       coalesce(sum(b.scrap_cost),0)::numeric(14,2)    AS scrap_cost,
       coalesce(sum(b.labor_cost+b.overhead_cost),0)::numeric(14,2) AS conversion_cost,
       coalesce(sum(b.approved_value),0)::numeric(14,2) AS approved_value,
       count(b.id) AS batches
FROM public.work_orders w
LEFT JOIN public.work_order_batches b ON b.work_order_id=w.id AND b.status<>'cancelled'
GROUP BY w.id;
REVOKE ALL ON public.work_order_production FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.work_order_production TO authenticated;

-- ---------------------------------------------------------------------------
-- 5) إعادة تعريف _rebuild_journal: نفس منطق FEDO + دفعات التصنيع
--    لا تغيير صامت: إن كان التعريف المثبت لا يحتوي كتلة أوامر التصنيع
--    القديمة يتوقف الملف برسالة صريحة بدل الكتابة فوق منطق غير معروف.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_src text;
BEGIN
  v_src := pg_get_functiondef('public._rebuild_journal(text,uuid)'::regprocedure);
  IF v_src NOT LIKE '%work_orders WHERE status=''Completed'' AND p_type IS NULL%' THEN
    RAISE EXCEPTION 'تعريف _rebuild_journal غير متوقع؛ افحص staging قبل تطبيق v6';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public._rebuild_journal(p_type text DEFAULT NULL::text, p_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  e uuid;
  n int:=0;
  c numeric;
  net numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(777);
  PERFORM set_config('erp.rebuild','on',true);

  -- Rebuild system-generated entries, preserve manual journals and opening balances.
  -- v6: production-batch and approval postings are rebuilt with everything else.
  IF p_type IS NULL THEN
    DELETE FROM journal_entries WHERE doc_type NOT IN('manual','opening_balance') OR doc_type IS NULL;
  ELSE
    DELETE FROM journal_entries WHERE doc_type=p_type AND doc_id=p_id;
    -- دفعات التصنيع تُرحّل قيدين لنفس الأمر (استهلاك + اعتماد)؛ يُحذفان معًا
    IF p_type='work_order_batch' THEN
      DELETE FROM journal_entries
       WHERE doc_type='work_order_approval'
         AND doc_id IN (SELECT b.id FROM work_order_batches b WHERE b.work_order_id=p_id);
    END IF;
  END IF;

  -- Sales invoices: AR Dr / Revenue Cr / Output VAT Cr / COGS Dr / Inventory Cr
  FOR r IN SELECT * FROM sales_invoices WHERE status='Posted' AND (p_type IS NULL OR (p_type='sales_invoice' AND id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'فاتورة مبيعات '||r.number,'sales_invoice',r.id);

    net:=round(r.total-coalesce(r.tax,0),2);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES
      (e,'1300',r.total,0),
      (e,'4000',0,greatest(net,0));

    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2100',0,r.tax);
    END IF;

    SELECT coalesce(sum(sii.qty*sii.unit_cost),0)
      INTO c
      FROM sales_invoice_items AS sii
      WHERE sii.invoice_id=r.id;

    IF c>0 AND coalesce(r.notes,'') NOT LIKE 'DN:%' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'5000',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  -- Purchase invoices: Inventory Dr / Input VAT Dr / AP Cr
  FOR r IN SELECT * FROM purchase_invoices WHERE status='Posted' AND (p_type IS NULL OR (p_type='purchase_invoice' AND id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'فاتورة مشتريات '||r.number,'purchase_invoice',r.id);

    net:=round(r.total-coalesce(r.tax,0),2);

    IF coalesce(r.notes,'') LIKE 'GRN:%' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2110',greatest(net,0),0),(e,'2000',0,r.total);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',greatest(net,0),0),(e,'2000',0,r.total);
    END IF;

    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1410',r.tax,0);
    END IF;
  END LOOP;

  -- Goods receipts: Inventory Dr / GRNI Cr
  FOR r IN SELECT gr.*,coalesce(sum(i.line_total),0) AS total_cost
    FROM goods_receipts gr JOIN goods_receipt_items i ON i.receipt_id=gr.id
    WHERE gr.status='Received' AND p_type IS NULL GROUP BY gr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'استلام بضاعة '||r.number,'goods_receipt',r.id);
    IF r.total_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.total_cost,0),(e,'2110',0,r.total_cost); END IF;
  END LOOP;

  -- Delivery notes: COGS Dr / Inventory Cr. Sales invoice created from DN only posts AR/Revenue/VAT.
  FOR r IN SELECT dn.*,coalesce(sum(i.qty*i.unit_cost),0) AS cost
    FROM delivery_notes dn JOIN delivery_note_items i ON i.delivery_id=dn.id
    WHERE dn.status='Delivered' AND p_type IS NULL GROUP BY dn.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'إذن تسليم '||r.number,'delivery_note',r.id);
    IF r.cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'5000',r.cost,0),(e,'1200',0,r.cost); END IF;
  END LOOP;

  -- Payments: Cash/Bank Dr for receipts, AP Dr for supplier payments.
  FOR r IN SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
    FROM payments AS p
    JOIN cash_accounts AS a ON a.id=p.account_id WHERE (p_type IS NULL OR (p_type='payment' AND p.id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,
        CASE r.kind WHEN 'receipt' THEN 'مقبوضات ' ELSE 'مدفوعات ' END||coalesce(r.doc_ref,''),
        'payment',r.id);

    IF r.kind='receipt' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,r.cc,r.amount,0),(e,'1300',0,r.amount);
    ELSIF r.kind='payment' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2000',r.amount,0),(e,r.cc,0,r.amount);
    ELSE
      RAISE EXCEPTION 'نوع دفع غير صحيح أثناء ترحيل اليومية: %',r.kind;
    END IF;
  END LOOP;

  -- Expenses: Expense Dr / Cash-Bank Cr
  FOR r IN SELECT x.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
           FROM expenses AS x
           JOIN cash_accounts AS a ON a.id=x.account_id WHERE (p_type IS NULL OR (p_type='expense' AND x.id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مصروف '||r.category,'expense',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'6000',r.amount,0),(e,r.cc,0,r.amount);
  END LOOP;

  -- Sales returns: contra revenue Dr + VAT Dr + Inventory Dr / AR Cr + COGS Cr
  FOR r IN SELECT sr.*,
           coalesce(sum(i.cost_total),0) AS cost,
           coalesce(sum(i.tax),0) AS tax,
           coalesce(sum(i.line_total),0) AS base
    FROM sales_returns AS sr
    JOIN sales_return_items AS i ON i.return_id=sr.id WHERE (p_type IS NULL OR (p_type='sales_return' AND sr.id=p_id)) GROUP BY sr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مرتجع مبيعات '||r.number,'sales_return',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'4000',r.base,0),(e,'1300',0,r.total);

    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2100',r.tax,0);
    END IF;

    IF r.cost>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1200',r.cost,0),(e,'5000',0,r.cost);
    END IF;
  END LOOP;

  -- Purchase returns: AP Dr / Inventory Cr / Input VAT Cr
  FOR r IN SELECT pr.*,
           coalesce(sum(i.tax),0) AS tax,
           coalesce(sum(i.line_total),0) AS base
    FROM purchase_returns AS pr
    JOIN purchase_return_items AS i ON i.return_id=pr.id WHERE (p_type IS NULL OR (p_type='purchase_return' AND pr.id=p_id)) GROUP BY pr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مرتجع مشتريات '||r.number,'purchase_return',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'2000',r.total,0),(e,'1200',0,r.base);

    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1410',0,r.tax);
    END IF;
  END LOOP;

  -- Cash transfers: destination Dr / source Cr
  FOR r IN SELECT * FROM cash_transfers WHERE p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'تحويل بين الحسابات','cash_transfer',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(
        e,
        CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.to_account)='bank' THEN '1100' ELSE '1000' END,
        r.amount,0),
      (
        e,
        CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.from_account)='bank' THEN '1100' ELSE '1000' END,
        0,r.amount);
  END LOOP;

  -- Paid payroll: Expense Dr / Cash-Bank Cr
  FOR r IN SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
    FROM payroll AS p
    JOIN cash_accounts AS a ON a.id=p.account_id
    WHERE p.paid AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.month,'مرتب','payroll',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'6000',r.net,0),(e,r.cc,0,r.net);
  END LOOP;

  -- Stocktake adjustments: inventory gain/shrinkage.
  FOR r IN SELECT sm.id,sm.created_at::date AS date,sm.product_id,sm.qty,sm.doc_id,p.avg_cost
    FROM stock_movements AS sm
    JOIN products AS p ON p.id=sm.product_id
    WHERE sm.type='Stock Adjustment'
      AND sm.doc_type='stocktake'
      AND sm.doc_id IS NOT NULL AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    c:=round(abs(r.qty*r.avg_cost),2);
    IF c=0 THEN CONTINUE; END IF;

    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'تسوية جرد','stock_adjustment',r.doc_id);

    IF r.qty>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1200',c,0),(e,'4300',0,c);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'6100',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  -- Fixed asset acquisition / depreciation / disposal entries
  FOR r IN SELECT * FROM fixed_assets WHERE capitalized AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.purchase_date,'رسملة أصل '||r.code,'fixed_asset_acquisition',r.id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1400',r.cost,0);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,coalesce(r.acquisition_account,'1000'),0,r.cost);
  END LOOP;

  FOR r IN SELECT ad.*,fa.code,fa.branch_id FROM asset_depreciations ad JOIN fixed_assets fa ON fa.id=ad.asset_id WHERE p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.period_date,'إهلاك أصل '||r.code,'depreciation',r.asset_id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6200',r.amount,0),(e,'1500',0,r.amount);
  END LOOP;

  FOR r IN SELECT * FROM fixed_assets WHERE status='Disposed' AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1; c:=round(r.cost-r.accumulated_depreciation,2);
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.disposal_date,'استبعاد أصل '||r.code,'asset_disposal',r.id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1500',r.accumulated_depreciation,0),(e,'1400',0,r.cost);
    IF r.disposal_proceeds>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.disposal_account_id)='bank' THEN '1100' ELSE '1000' END,r.disposal_proceeds,0); END IF;
    IF r.disposal_proceeds-(r.cost-r.accumulated_depreciation)>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'7100',0,r.disposal_proceeds-(r.cost-r.accumulated_depreciation));
    ELSIF r.disposal_proceeds-(r.cost-r.accumulated_depreciation)<0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6300',-(r.disposal_proceeds-(r.cost-r.accumulated_depreciation)),0); END IF;
  END LOOP;

  -- =====================================================================
  -- FEDO FACTORY v6: manufacturing postings
  --   * legacy orders (no factory ledger rows) keep the original block and
  --     are still applied exactly once when a full rebuild runs;
  --   * batch-based orders post per production batch from work_order_batches,
  --     so a partial rebuild after each batch equals a full rebuild.
  -- =====================================================================
  FOR r IN SELECT * FROM work_orders WHERE status='Completed' AND p_type IS NULL LOOP
    IF NOT EXISTS (SELECT 1 FROM work_order_batches b WHERE b.work_order_id=r.id) THEN
      e:=gen_random_uuid(); n:=n+1;
      INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'إتمام تصنيع '||r.number,'work_order',r.id);
      IF r.total_cost>0 THEN
        INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.total_cost,0);
        IF r.material_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',0,r.material_cost); END IF;
        IF r.labor_cost+r.overhead_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2200',0,r.labor_cost+r.overhead_cost); END IF;
      END IF;
    END IF;
  END LOOP;

  -- Production batches: WIP Dr / material, waste and scrap Cr (negative value
  -- posts as a debit), labour + overhead credit to the manufacturing accrual.
  FOR r IN SELECT b.*, w.number, w.warehouse_id
    FROM work_order_batches b JOIN work_orders w ON w.id=b.work_order_id
    WHERE (p_type IS NULL OR (p_type='work_order_batch' AND b.work_order_id=p_id))
    ORDER BY b.recorded_at, b.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.recorded_at::date,'دفعة تصنيع '||r.number||' #'||r.batch_no,'work_order_batch',r.work_order_id);
    -- Dr WIP = قيمة الخامة الصالحة + العمالة والتحميلات (تكلفة التحويل تُحمَّل على الإنتاج)
    -- Dr هالك = قيمة الهالك ناقص قيمة البواقي المستردة
    -- Cr المخزون = إجمالي قيمة ما صُرف · Cr مستحق التصنيع = العمالة والتحميلات
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'1210',round(r.material_cost - r.waste_cost - r.scrap_cost
                            + r.labor_cost + r.overhead_cost,2),0);
    IF round(r.material_cost,2)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',0,round(r.material_cost,2));
    END IF;
    IF round(r.waste_cost - r.scrap_cost,2)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'6100',round(r.waste_cost - r.scrap_cost,2),0);
    END IF;
    IF round(r.labor_cost + r.overhead_cost,2)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2200',0,round(r.labor_cost+r.overhead_cost,2));
    END IF;
  END LOOP;

  -- Stockkeeper approval: finished goods move from WIP into sellable inventory.
  FOR r IN SELECT b.*, w.number
    FROM work_order_batches b JOIN work_orders w ON w.id=b.work_order_id
    WHERE b.status='approved' AND (p_type IS NULL OR (p_type='work_order_batch' AND b.work_order_id=p_id))
    ORDER BY b.approved_at, b.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.approved_at::date,'اعتماد إنتاج '||r.number||' #'||r.batch_no,'work_order_approval',r.id);
    IF r.approved_value>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',round(r.approved_value,2),0);
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1210',0,round(r.approved_value,2));
    END IF;
  END LOOP;

  PERFORM set_config('erp.rebuild','off',true);
  RETURN n;
END $function$;

-- ---------------------------------------------------------------------------
-- 6) متطلبات الخامة مقابل المتاح
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_manual_requirement(p_bom uuid, p_qty numeric)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v jsonb;
BEGIN
  PERFORM require_perm('mfg');
  IF p_qty IS NULL OR p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'component_product_id',x.component_product_id,'qty',round(x.qty,4),
           'required',round(x.qty*p_qty,3),'available',coalesce(a.qty,0),
           'shortage',greatest(round(x.qty*p_qty,3)-coalesce(a.qty,0),0))),'[]'::jsonb)
    INTO v
    FROM (SELECT bi.component_product_id,sum(bi.qty) AS qty
            FROM bom_items bi WHERE bi.bom_id=p_bom GROUP BY bi.component_product_id) x
    LEFT JOIN (SELECT b.product_id,sum(b.qty) AS qty FROM stock_balances b GROUP BY b.product_id) a
      ON a.product_id=x.component_product_id;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.factory_manual_requirement(uuid,numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_manual_requirement(uuid,numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7) بدء أمر تصنيع بالمسار الجديد — لا يمس المخزون
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_start_work_order(
  p_bom uuid, p_warehouse uuid, p_qty numeric, p_labor numeric DEFAULT 0, p_overhead numeric DEFAULT 0,
  p_requires_approval boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id uuid; v_num text;
BEGIN
  PERFORM require_perm('mfg');
  IF NOT EXISTS(SELECT 1 FROM boms WHERE id=p_bom AND active) THEN RAISE EXCEPTION 'BOM غير متاح'; END IF;
  IF p_qty IS NULL OR p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;
  IF coalesce(p_labor,0)<0 OR coalesce(p_overhead,0)<0 THEN RAISE EXCEPTION 'التكلفة غير صحيحة'; END IF;
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse) THEN RAISE EXCEPTION 'المخزن غير متاح'; END IF;
  v_id := gen_random_uuid();
  v_num := 'WO-'||(1000+nextval('seq_wo'));
  INSERT INTO work_orders(id,number,bom_id,warehouse_id,planned_qty,labor_cost,overhead_cost,status,date,production_mode,requires_approval)
    VALUES(v_id,v_num,p_bom,p_warehouse,p_qty,coalesce(p_labor,0),coalesce(p_overhead,0),'In Progress',current_date,
           'batched',coalesce(p_requires_approval,true));
  PERFORM log_event('create','work_orders',v_id::text,'أمر تصنيع بالمسار الجديد '||v_num);
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.factory_start_work_order(uuid,uuid,numeric,numeric,numeric,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_start_work_order(uuid,uuid,numeric,numeric,numeric,boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8) تسجيل دفعة إنتاج فعلية (BUG-02) + استهلاك رولات/أصناف + اعتماد المؤجّل
--    p_uses = [{"roll_id":"..","consumed":8,"waste":1,"scrap":0}, ...]
--          أو [{"product_id":"..","consumed":8}, ...] لصنف غير متتبع
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_record_batch(
  p_request uuid, p_order uuid, p_good_qty numeric, p_uses jsonb,
  p_waste_qty numeric DEFAULT 0, p_scrap_qty numeric DEFAULT 0, p_note text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  wo public.work_orders%ROWTYPE;
  v_exist public.work_order_batches%ROWTYPE;
  v_payload jsonb; x jsonb; v_product uuid; v_avg numeric; v_unitc numeric; v_mv uuid;
  v_batch uuid; v_no int; v_bom_product uuid;
  v_mat numeric:=0; v_waste_cost numeric:=0; v_scrap_cost numeric:=0;
  v_labor numeric; v_overhead numeric; v_unit numeric; v_total numeric; v_done numeric;
BEGIN
  PERFORM require_perm('mfg');
  PERFORM require_perm('stk');
  IF current_setting('erp.factory_ledger',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'مسار إنتاج المصنع غير مفعّل لهذه القاعدة (erp.factory_ledger)';
  END IF;
  IF p_request IS NULL OR p_order IS NULL OR p_good_qty IS NULL OR p_good_qty<0
     OR round(p_good_qty,3)<>p_good_qty OR coalesce(p_waste_qty,0)<0 OR coalesce(p_scrap_qty,0)<0
     OR round(coalesce(p_waste_qty,0),3)<>coalesce(p_waste_qty,0)
     OR round(coalesce(p_scrap_qty,0),3)<>coalesce(p_scrap_qty,0)
     OR jsonb_typeof(p_uses) IS DISTINCT FROM 'array' OR jsonb_array_length(p_uses)=0 THEN
    RAISE EXCEPTION 'بيانات دفعة الإنتاج غير صحيحة';
  END IF;
  IF p_good_qty + coalesce(p_waste_qty,0) <= 0 THEN RAISE EXCEPTION 'الدفعة بلا كمية'; END IF;
  v_payload := jsonb_build_object('order',p_order,'good',p_good_qty,'waste',coalesce(p_waste_qty,0),
                                  'scrap',coalesce(p_scrap_qty,0),'uses',p_uses,'note',p_note);
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
  SELECT * INTO v_exist FROM work_order_batches WHERE request_id=p_request;
  IF FOUND THEN
    IF v_exist.payload IS DISTINCT FROM v_payload OR v_exist.recorded_by<>auth.uid() THEN
      RAISE EXCEPTION 'مفتاح العملية مستخدم لبيانات مختلفة';
    END IF;
    RETURN v_exist.id;
  END IF;

  SELECT * INTO wo FROM work_orders WHERE id=p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'أمر التصنيع غير موجود'; END IF;
  IF wo.status IN ('Completed','Cancelled') THEN RAISE EXCEPTION 'أمر التصنيع مغلق'; END IF;
  SELECT b.product_id INTO v_bom_product FROM boms b WHERE b.id=wo.bom_id;
  IF v_bom_product IS NULL THEN RAISE EXCEPTION 'BOM غير متاح'; END IF;

  SELECT coalesce(sum(b.good_qty+b.waste_qty),0) INTO v_done FROM work_order_batches b
   WHERE b.work_order_id=p_order AND b.status<>'cancelled';
  IF v_done + p_good_qty + coalesce(p_waste_qty,0) > wo.planned_qty THEN
    RAISE EXCEPTION 'إجمالي الإنتاج (%) يتجاوز الكمية المخططة (%)',
      v_done+p_good_qty+coalesce(p_waste_qty,0),wo.planned_qty;
  END IF;

  -- العمالة والتحميلات تُوزَّع بالتناسب مع الكمية الصالحة لهذه الدفعة
  v_labor := CASE WHEN wo.planned_qty>0 THEN round(wo.labor_cost/wo.planned_qty*p_good_qty,2) ELSE 0 END;
  v_overhead := CASE WHEN wo.planned_qty>0 THEN round(wo.overhead_cost/wo.planned_qty*p_good_qty,2) ELSE 0 END;

  SELECT coalesce(max(batch_no),0)+1 INTO v_no FROM work_order_batches WHERE work_order_id=p_order;
  v_batch := gen_random_uuid();
  INSERT INTO work_order_batches(id,batch_no,work_order_id,request_id,payload,good_qty,waste_qty,scrap_qty,
                                 labor_cost,overhead_cost,recorded_by)
    VALUES(v_batch,v_no,p_order,p_request,v_payload,p_good_qty,coalesce(p_waste_qty,0),coalesce(p_scrap_qty,0),
           v_labor,v_overhead,auth.uid());

  FOR x IN SELECT value FROM jsonb_array_elements(p_uses) LOOP
    IF nullif(x->>'roll_id','') IS NOT NULL THEN
      -- استهلاك من رول محدد عبر الدفتر الموحد (نفس المعاملة)
      v_mv := factory_roll_issue_internal(
        md5(p_request::text||':'||(x->>'roll_id'))::uuid, (x->>'roll_id')::uuid, p_order,
        coalesce((x->>'consumed')::numeric,0), 'consumption',
        coalesce((x->>'waste')::numeric,0), coalesce((x->>'scrap')::numeric,0), p_note);
      INSERT INTO work_order_batch_uses(batch_id,component_product_id,roll_id,roll_move_id,consumed_qty,waste_qty,scrap_qty,unit_cost,stock_movement_id)
      SELECT v_batch,r.product_id,m.roll_id,m.id,coalesce(m.consumed_qty,0),coalesce(m.waste_qty,0),coalesce(m.scrap_qty,0),m.unit_cost,m.stock_movement_id
        FROM factory_roll_moves m JOIN factory_rolls r ON r.id=m.roll_id WHERE m.id=v_mv;
      UPDATE factory_roll_moves SET production_batch_id=v_batch WHERE id=v_mv;
    ELSIF nullif(x->>'product_id','') IS NOT NULL THEN
      -- صنف غير متتبع: خصم مباشر من رصيد المخزن (FEDO) بنفس المعاملة
      IF coalesce((x->>'consumed')::numeric,0)<=0 OR round((x->>'consumed')::numeric,3)<>(x->>'consumed')::numeric THEN
        RAISE EXCEPTION 'كمية استهلاك الصنف غير صحيحة'; END IF;
      SELECT coalesce(avg_cost,0) INTO v_avg FROM products WHERE id=(x->>'product_id')::uuid;
      IF NOT FOUND THEN RAISE EXCEPTION 'الصنف غير موجود'; END IF;
      PERFORM assert_period_open(current_date);
      PERFORM apply_stock((x->>'product_id')::uuid, wo.warehouse_id, -((x->>'consumed')::numeric),
                          'Sale','work_order_batch', v_batch);
      SELECT id INTO v_mv FROM stock_movements WHERE doc_type='work_order_batch' AND doc_id=v_batch
        ORDER BY created_at DESC LIMIT 1;
      INSERT INTO work_order_batch_uses(batch_id,component_product_id,consumed_qty,unit_cost,stock_movement_id)
        VALUES(v_batch,(x->>'product_id')::uuid,(x->>'consumed')::numeric,v_avg,v_mv);
    ELSE
      RAISE EXCEPTION 'كل بند استهلاك يحتاج roll_id أو product_id';
    END IF;
  END LOOP;

  SELECT coalesce(sum(round((u.consumed_qty+u.waste_qty+u.scrap_qty)*u.unit_cost,2)),0),
         coalesce(sum(round(u.waste_qty*u.unit_cost,2)),0),
         coalesce(sum(round(u.scrap_qty*u.unit_cost,2)),0)
    INTO v_mat,v_waste_cost,v_scrap_cost
    FROM work_order_batch_uses u WHERE u.batch_id=v_batch;

  v_total := round(v_mat + v_labor + v_overhead,2);
  v_unit := CASE WHEN p_good_qty>0 THEN v_total/p_good_qty ELSE 0 END;
  UPDATE work_order_batches SET material_cost=round(v_mat,2), waste_cost=round(v_waste_cost,2),
         scrap_cost=round(v_scrap_cost,2), unit_cost=round(v_unit,4) WHERE id=v_batch;
  UPDATE work_orders SET status='In Progress', started_at=coalesce(started_at,now()),
         material_cost=round(material_cost+v_mat,2), total_cost=round(total_cost+v_total,2)
   WHERE id=p_order AND status NOT IN ('Completed','Cancelled');
  PERFORM log_event('create','work_order_batches',v_batch::text,
    'دفعة إنتاج #'||v_no||' صالح '||p_good_qty||' تكلفة '||v_total);
  RETURN v_batch;
END $$;
REVOKE ALL ON FUNCTION public.factory_record_batch(uuid,uuid,numeric,jsonb,numeric,numeric,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_record_batch(uuid,uuid,numeric,jsonb,numeric,numeric,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9) اعتماد المخزن (BUG-03): هنا فقط يدخل المنتج النهائي للمخزون القابل للبيع
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_approve_batch(
  p_request uuid, p_batch uuid, p_qty numeric DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  b public.work_order_batches%ROWTYPE;
  wo public.work_orders%ROWTYPE;
  v_qty numeric; v_product uuid; v_value numeric;
  v_done numeric; v_pending int; v_planned numeric;
BEGIN
  PERFORM require_perm('stk');
  IF current_setting('erp.factory_ledger',true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'مسار اعتماد الإنتاج غير مفعّل لهذه القاعدة (erp.factory_ledger)';
  END IF;
  IF p_request IS NULL OR p_batch IS NULL THEN RAISE EXCEPTION 'بيانات الاعتماد غير صحيحة'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
  SELECT * INTO b FROM work_order_batches WHERE approved_batch_id=p_request;
  IF FOUND THEN RETURN b.id; END IF;                     -- إعادة نفس المفتاح = نفس النتيجة
  SELECT * INTO b FROM work_order_batches WHERE id=p_batch FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الدفعة غير موجودة'; END IF;
  IF b.status='cancelled' THEN RAISE EXCEPTION 'الدفعة ملغاة'; END IF;
  IF b.status='approved' THEN RAISE EXCEPTION 'الدفعة معتمدة بالفعل بمفتاح مختلف'; END IF;
  IF EXISTS(SELECT 1 FROM work_order_batches o WHERE o.work_order_id=b.work_order_id
            AND o.status='recorded' AND o.batch_no<b.batch_no) THEN
    RAISE EXCEPTION 'اعتمد الدفعات بالترتيب: توجد دفعة أقدم لم تُعتمد';
  END IF;
  SELECT * INTO wo FROM work_orders WHERE id=b.work_order_id FOR UPDATE;
  IF wo.status='Cancelled' THEN RAISE EXCEPTION 'أمر التصنيع ملغى'; END IF;
  v_qty := coalesce(p_qty,b.good_qty);
  IF v_qty<=0 OR v_qty>b.good_qty OR round(v_qty,3)<>v_qty THEN
    RAISE EXCEPTION 'كمية الاعتماد غير صحيحة (الحد الأقصى %)',b.good_qty; END IF;
  SELECT product_id INTO v_product FROM boms WHERE id=wo.bom_id;

  -- قيمة الاعتماد = الكمية المعتمدة × تكلفة الوحدة، وتُعاد قيمة الباقي للمعالجة
  v_value := round(v_qty*b.unit_cost,2);
  PERFORM assert_period_open(current_date);
  PERFORM apply_stock(v_product, wo.warehouse_id, v_qty, 'Purchase','work_order_approval', b.id);
  UPDATE work_order_batches SET status='approved', approved_qty=v_qty, approved_value=v_value,
         approved_by=auth.uid(), approved_at=now(), approved_batch_id=p_request,
         rejection_reason=coalesce(p_note,rejection_reason)
   WHERE id=b.id;

  SELECT coalesce(sum(x.good_qty+x.waste_qty),0), count(*) FILTER (WHERE x.status='recorded')
    INTO v_done, v_pending FROM work_order_batches x
   WHERE x.work_order_id=wo.id AND x.status<>'cancelled';
  SELECT planned_qty INTO v_planned FROM work_orders WHERE id=wo.id;
  IF v_pending=0 AND v_done>=v_planned THEN
    UPDATE work_orders SET status='Completed', produced_qty=v_done, completed_at=now(), closed_by=auth.uid()
     WHERE id=wo.id;
    PERFORM log_event('complete','work_orders',wo.id::text,'اكتمل أمر التصنيع '||wo.number||' بإنتاج '||v_done);
  ELSE
    UPDATE work_orders SET produced_qty=v_done WHERE id=wo.id;
  END IF;
  PERFORM log_event('approve','work_order_batches',b.id::text,
    'اعتماد دفعة #'||b.batch_no||' كمية '||v_qty||' قيمة '||v_value);
  RETURN b.id;
END $$;
REVOKE ALL ON FUNCTION public.factory_approve_batch(uuid,uuid,numeric,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_approve_batch(uuid,uuid,numeric,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10) رفض دفعة (لا حركة مخزون؛ تُلغى الدفعة بلا اعتماد)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_reject_batch(p_batch uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE b public.work_order_batches%ROWTYPE;
BEGIN
  PERFORM require_perm('stk');
  IF coalesce(trim(p_reason),'')='' THEN RAISE EXCEPTION 'سبب الرفض مطلوب'; END IF;
  SELECT * INTO b FROM work_order_batches WHERE id=p_batch FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الدفعة غير موجودة'; END IF;
  IF b.status<>'recorded' THEN RAISE EXCEPTION 'لا يمكن رفض دفعة معتمدة أو ملغاة'; END IF;
  UPDATE work_order_batches SET status='cancelled', cancelled_by=auth.uid(), cancelled_at=now(),
         rejection_reason=p_reason WHERE id=b.id;
  PERFORM log_event('reject','work_order_batches',b.id::text,'رفض دفعة #'||b.batch_no||': '||p_reason);
END $$;
REVOKE ALL ON FUNCTION public.factory_reject_batch(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.factory_reject_batch(uuid,text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 11) ترحيل قيود الأمر فورًا بعد كل دفعة/اعتماد داخل نفس المعاملة
--     (لا نعتمد على rebuild يدوي؛ ويمكن دومًا _rebuild_journal لإعادة البناء)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.factory_batch_post_journal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM public._rebuild_journal('work_order_batch', COALESCE(NEW.work_order_id, OLD.work_order_id));
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.factory_batch_post_journal() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS factory_batch_journal ON public.work_order_batches;
CREATE TRIGGER factory_batch_journal AFTER INSERT OR UPDATE ON public.work_order_batches
  FOR EACH ROW EXECUTE FUNCTION public.factory_batch_post_journal();

-- ---------------------------------------------------------------------------
-- 12) توحيد المسار: الدالة العامة rebuild_journal() تنادي _rebuild_journal()
--     النسخة المثبتة في FEDO تحتفظ بنسخة قديمة من منطق الترحيل (بلا قيود
--     التصنيع)، فأي إعادة بناء عامة كانت ستحذف قيود المصنع. هنا نوجّهها إلى
--     المصدر الوحيد بنفس فحص الصلاحية، فتصبح إعادة البناء الكاملة = اللحظية.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rebuild_journal() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM require_role('{admin,accountant}');
  RETURN public._rebuild_journal(NULL,NULL);
END $$;
REVOKE ALL ON FUNCTION public.rebuild_journal() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rebuild_journal() TO authenticated;

-- ---------------------------------------------------------------------------
-- 13) إغلاق المعاملة
-- ---------------------------------------------------------------------------
COMMIT;
