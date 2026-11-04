-- ============================================================================
-- factory_roll_ledger_v5_test.sql  — المرحلة 1: اختبار دفتر الرولات التشغيلي
-- LOCAL / DISPOSABLE DATABASE ONLY. Every fixture is rolled back at the end.
-- Run: psql -v ON_ERROR_STOP=1 -d <testdb> -f factory_roll_ledger_v5_test.sql
-- ============================================================================
BEGIN;

-- مفتاح تشغيل المسار لهذه المعاملة (لا يُثبَّت على القاعدة)
SELECT set_config('erp.factory_ledger','on',true);

-- ---------------------------------------------------------------- fixtures
INSERT INTO auth.users(id,email) VALUES
 ('b0000000-0000-4000-8000-000000000001','v5-admin@test.invalid'),
 ('b0000000-0000-4000-8000-000000000002','v5-store@test.invalid'),
 ('b0000000-0000-4000-8000-000000000003','v5-sales@test.invalid'),
 ('b0000000-0000-4000-8000-000000000004','v5-custom@test.invalid');
UPDATE profiles SET active=true,role=CASE id::text
    WHEN 'b0000000-0000-4000-8000-000000000001' THEN 'admin'
    WHEN 'b0000000-0000-4000-8000-000000000002' THEN 'store'
    WHEN 'b0000000-0000-4000-8000-000000000003' THEN 'sales'
    ELSE 'store' END,
  permissions_mode=CASE WHEN id='b0000000-0000-4000-8000-000000000004' THEN 'custom' ELSE 'role' END
  WHERE id::text LIKE 'b0000000-0000-4000-8000-00000000000%';
-- مستخدم custom بصلاحية stk فقط (لا mfg) لاختبار الفصل بين الصلاحيتين
INSERT INTO user_permissions(user_id,permission_key)
VALUES('b0000000-0000-4000-8000-000000000004','stk')
ON CONFLICT DO NOTHING;

INSERT INTO units(id,name) VALUES('b1000000-0000-4000-8000-000000000001','v5-unit');
INSERT INTO products(id,name,code,unit_id) VALUES
 ('b2000000-0000-4000-8000-000000000001','v5 fabric','V5-FAB','b1000000-0000-4000-8000-000000000001'),
 ('b2000000-0000-4000-8000-000000000002','v5 garment','V5-GRM','b1000000-0000-4000-8000-000000000001');
INSERT INTO suppliers(id,name) VALUES('b3000000-0000-4000-8000-000000000001','v5 supplier');
INSERT INTO boms(id,product_id,version) VALUES
 ('b4000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000002','v5-bom');
INSERT INTO bom_items(bom_id,component_product_id,qty) VALUES
 ('b4000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001',2);

CREATE TEMP TABLE v5_ctx(wh uuid, other_wh uuid, wo uuid, inv uuid, item uuid, roll_a uuid, roll_b uuid, prod uuid);
GRANT ALL ON v5_ctx TO authenticated;
INSERT INTO v5_ctx(prod) VALUES('b2000000-0000-4000-8000-000000000001');
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);

-- ===========================================================================
-- T1) شراء رولات ذري: فاتورة FEDO + قيد الشراء + دفتر الاستلام
-- ===========================================================================
UPDATE v5_ctx SET wh=(SELECT id FROM warehouses ORDER BY name LIMIT 1),
                  other_wh=(SELECT id FROM warehouses ORDER BY name DESC LIMIT 1);

DO $$ BEGIN
  IF (SELECT wh FROM v5_ctx) IS NULL THEN RAISE EXCEPTION 'warehouse fixture missing'; END IF;
END $$;

-- نقطة البداية: تفعيل التتبع لصنف برصيد صفري.
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  -- لا يمكن بدء التتبع لصنف له رصيد قائم بلا رولات
  PERFORM create_purchase('b3000000-0000-4000-8000-000000000001',(SELECT wh FROM v5_ctx),
    '[{"product_id":"b2000000-0000-4000-8000-000000000001","qty":5,"price":10}]');
  BEGIN
    PERFORM factory_enable_roll_tracking((SELECT prod FROM v5_ctx),(SELECT wh FROM v5_ctx));
    RAISE EXCEPTION 'T0 zero-start accepted a product with stock';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%البدء برصيد صفري فقط%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T0 zero-start guard missing'; END IF;
  RAISE NOTICE 'PASS T0 zero-start tracking refuses non-zero stock';
END $$;

-- إرجاع رصيد البداية إلى الصفر عبر مرتجع شراء (مسار FEDO القائم)
DO $$ DECLARE v_inv uuid; v_ok boolean:=false; BEGIN
  SELECT id INTO v_inv FROM purchase_invoices WHERE status='Posted' ORDER BY created_at DESC LIMIT 1;
  PERFORM create_purchase_return(v_inv,'[{"product_id":"b2000000-0000-4000-8000-000000000001","qty":5}]');
  IF (SELECT qty FROM stock_balances WHERE product_id=(SELECT prod FROM v5_ctx) AND warehouse_id=(SELECT wh FROM v5_ctx))=0 THEN v_ok:=true; END IF;
  IF NOT v_ok THEN RAISE EXCEPTION 'T0 stock reset failed'; END IF;
  PERFORM factory_enable_roll_tracking((SELECT prod FROM v5_ctx),(SELECT wh FROM v5_ctx));
  RAISE NOTICE 'PASS T0 tracked product enabled at zero stock';
END $$;

UPDATE v5_ctx SET inv = factory_buy_rolls(
  'b5000000-0000-4000-8000-000000000001',
  'b3000000-0000-4000-8000-000000000001',
  wh, prod, 10,
  '[{"code":"V5-A","color":"أبيض","width":1.5,"qty":40},{"code":"V5-B","color":"أبيض","width":1.5,"qty":60}]');

UPDATE v5_ctx SET item = (SELECT id FROM purchase_invoice_items WHERE invoice_id=(SELECT inv FROM v5_ctx));

DO $$ DECLARE v_stock numeric; v_debit numeric; v_credit numeric; BEGIN
  IF (SELECT count(*) FROM factory_rolls WHERE roll_code IN ('V5-A','V5-B'))<>2 THEN
    RAISE EXCEPTION 'T1 rolls not created';
  END IF;
  SELECT qty INTO v_stock FROM stock_balances WHERE product_id='b2000000-0000-4000-8000-000000000001' AND warehouse_id=(SELECT wh FROM v5_ctx);
  IF v_stock<>100 THEN RAISE EXCEPTION 'T1 purchase stock wrong: %',v_stock; END IF;
  SELECT coalesce(sum(l.debit),0),coalesce(sum(l.credit),0) INTO v_debit,v_credit
    FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id
   WHERE e.doc_type='purchase_invoice' AND e.doc_id=(SELECT inv FROM v5_ctx);
  IF v_debit<>1000 OR v_debit<>v_credit THEN RAISE EXCEPTION 'T1 purchase journal unbalanced %/%',v_debit,v_credit; END IF;
  IF (SELECT count(*) FROM factory_roll_moves m JOIN factory_rolls r ON r.id=m.roll_id
        WHERE r.roll_code IN ('V5-A','V5-B') AND m.movement_type<>'receipt')<>0 THEN
    RAISE EXCEPTION 'T1 purchase must post roll receipts only';
  END IF;
  RAISE NOTICE 'PASS T1 atomic roll purchase: 100 units, balanced purchase journal, 2 rolls';
END $$;

-- retry with same payload returns same invoice and does not double anything
DO $$ DECLARE v_same uuid; v_repeat jsonb; BEGIN
  v_same := factory_buy_rolls('b5000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001',
    (SELECT wh FROM v5_ctx),'b2000000-0000-4000-8000-000000000001',10,
    '[{"code":"V5-A","color":"أبيض","width":1.5,"qty":40},{"code":"V5-B","color":"أبيض","width":1.5,"qty":60}]');
  IF v_same<>(SELECT inv FROM v5_ctx) THEN RAISE EXCEPTION 'T1 retry created a new invoice'; END IF;
  IF (SELECT count(*) FROM factory_rolls WHERE roll_code IN ('V5-A','V5-B'))<>2 THEN
    RAISE EXCEPTION 'T1 retry duplicated rolls';
  END IF;
  BEGIN
    PERFORM factory_buy_rolls('b5000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001',
      (SELECT wh FROM v5_ctx),'b2000000-0000-4000-8000-000000000001',9,
      '[{"code":"V5-A","color":"أبيض","width":1.5,"qty":40}]');
    RAISE EXCEPTION 'T1 conflicting retry accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%مفتاح العملية%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS T1 idempotent purchase retry and conflicting payload rejected';
END $$;

-- ===========================================================================
-- T2) التفعيل لصنف قائم يتطلب معايرة تكلفة الرولات مع متوسط تكلفة الصنف
--     (صنف ثانٍ: رولات مسجلة يدويًا بتكلفة 12 ومتوسط الصنف 10)
-- ===========================================================================
INSERT INTO products(id,name,code,unit_id) VALUES
 ('b2000000-0000-4000-8000-000000000003','v5 fabric legacy','V5-FAB2','b1000000-0000-4000-8000-000000000001');

DO $$ DECLARE v_inv uuid; v_item uuid; v_blocked boolean:=false; BEGIN
  v_inv := create_purchase('b3000000-0000-4000-8000-000000000001',(SELECT wh FROM v5_ctx),
    '[{"product_id":"b2000000-0000-4000-8000-000000000003","qty":100,"price":10}]');
  SELECT id INTO v_item FROM purchase_invoice_items WHERE invoice_id=v_inv;
  -- تسجيل رولات على بند فاتورة قائم (مسار v1) ثم معايرة التفعيل
  PERFORM factory_register_rolls('b5000000-0000-4000-8000-000000000002','invoice',v_item,
    '[{"code":"V5-L1","color":"بيج","width":1.4,"qty":60},{"code":"V5-L2","color":"بيج","width":1.4,"qty":40}]');
  IF (SELECT sum(original_qty) FROM factory_rolls WHERE product_id='b2000000-0000-4000-8000-000000000003')<>100 THEN
    RAISE EXCEPTION 'T2 legacy rolls fixture wrong';
  END IF;
  UPDATE factory_rolls SET unit_cost=12 WHERE roll_code='V5-L2';
  BEGIN
    PERFORM factory_activate_roll_control('b2000000-0000-4000-8000-000000000003',(SELECT wh FROM v5_ctx));
    RAISE EXCEPTION 'T2 activation accepted uncalibrated roll cost';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%قبل معايرة تكلفة%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T2 calibration gate missing'; END IF;
  IF factory_normalize_roll_costs('b2000000-0000-4000-8000-000000000003',(SELECT wh FROM v5_ctx))<>1 THEN
    RAISE EXCEPTION 'T2 normalize did not fix exactly one roll';
  END IF;
  PERFORM factory_activate_roll_control('b2000000-0000-4000-8000-000000000003',(SELECT wh FROM v5_ctx));
  RAISE NOTICE 'PASS T2 activation requires cost calibration, then succeeds';
END $$;

UPDATE v5_ctx SET roll_a=(SELECT id FROM factory_rolls WHERE roll_code='V5-A'),
                  roll_b=(SELECT id FROM factory_rolls WHERE roll_code='V5-B');
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

DO $$ DECLARE v_bal numeric; v_stock numeric; v_value numeric; BEGIN
  SELECT sum(b.remaining_qty),sum(b.value_remaining) INTO v_bal,v_value FROM factory_roll_balances b WHERE b.product_id=(SELECT prod FROM v5_ctx);
  SELECT qty INTO v_stock FROM stock_balances WHERE product_id=(SELECT prod FROM v5_ctx) AND warehouse_id=(SELECT wh FROM v5_ctx);
  IF v_bal<>100 OR v_stock<>100 THEN RAISE EXCEPTION 'T2 roll balance % <> stock %',v_bal,v_stock; END IF;
  IF v_value<>round(v_stock*(SELECT avg_cost FROM products WHERE id=(SELECT prod FROM v5_ctx)),2) THEN
    RAISE EXCEPTION 'T2 roll value % <> stock value',v_value;
  END IF;
  RAISE NOTICE 'PASS T2 roll balances 100 = FEDO stock 100 and value matches avg cost';
END $$;

-- ===========================================================================
-- T3) أمر تصنيع + صرف جزئي من رولين مع هالك وبواقي
-- ===========================================================================
UPDATE v5_ctx SET wo = create_work_order('b4000000-0000-4000-8000-000000000001', wh, 10);

DO $$ DECLARE v_wo uuid; BEGIN
  v_wo := (SELECT wo FROM v5_ctx);
  IF (SELECT planned_qty FROM work_orders WHERE id=v_wo)<>10 THEN RAISE EXCEPTION 'T3 work order missing'; END IF;
  -- إنشاء الأمر لا يخصم شيئًا
  IF (SELECT qty FROM stock_balances WHERE product_id=(SELECT prod FROM v5_ctx) AND warehouse_id=(SELECT wh FROM v5_ctx))<>100 THEN
    RAISE EXCEPTION 'T3 work order creation changed stock';
  END IF;
  RAISE NOTICE 'PASS T3 work order creation leaves stock untouched';
END $$;

-- صرف 12 من A (منها 2 هالك) و8 من B
SELECT factory_issue_roll('b6000000-0000-4000-8000-000000000001',(SELECT roll_a FROM v5_ctx),(SELECT wo FROM v5_ctx),10,'consumption','دفعة أولى');
DO $$ DECLARE v_blocked boolean:=false; v_rem numeric; v_stock numeric; v_mv record; BEGIN
  -- الهالك لا يمكن أن يُسجَّل كحركة منفصلة بدون صرف (p_qty=0 مع هالك 2 فقط)
  PERFORM factory_roll_issue_internal('b6000000-0000-4000-8000-000000000002',(SELECT roll_a FROM v5_ctx),(SELECT wo FROM v5_ctx),0,'waste',2,0,'هالك قص');
  SELECT remaining_qty INTO v_rem FROM factory_roll_balances WHERE roll_id=(SELECT roll_a FROM v5_ctx);
  IF v_rem<>28 THEN RAISE EXCEPTION 'T3 roll A remaining wrong: %',v_rem; END IF;
  SELECT qty INTO v_stock FROM stock_balances WHERE product_id=(SELECT prod FROM v5_ctx) AND warehouse_id=(SELECT wh FROM v5_ctx);
  IF v_stock<>88 THEN RAISE EXCEPTION 'T3 FEDO stock after issue+waste wrong: %',v_stock; END IF;
  IF (SELECT sum(consumed_qty) FROM factory_roll_moves WHERE work_order_id=(SELECT wo FROM v5_ctx))<>10
     OR (SELECT sum(waste_qty) FROM factory_roll_moves WHERE work_order_id=(SELECT wo FROM v5_ctx))<>2 THEN
    RAISE EXCEPTION 'T3 consumption/waste breakdown wrong';
  END IF;
  -- حركة المخزون مرتبطة بالدفتر
  SELECT sm.qty,sm.doc_type INTO v_mv FROM stock_movements sm
    JOIN factory_roll_moves m ON m.stock_movement_id=sm.id
   WHERE m.request_id='b6000000-0000-4000-8000-000000000001';
  IF v_mv.qty<>-10 OR v_mv.doc_type<>'factory_roll_issue' THEN RAISE EXCEPTION 'T3 stock movement linkage wrong'; END IF;
  RAISE NOTICE 'PASS T3 partial consumption 10 + waste 2 from one roll, stock and roll ledger agree (88)';
END $$;

-- إعادة نفس الطلب = لا خصم إضافي
DO $$ BEGIN
  IF factory_issue_roll('b6000000-0000-4000-8000-000000000001',(SELECT roll_a FROM v5_ctx),(SELECT wo FROM v5_ctx),10,'consumption','دفعة أولى')
     IS NULL THEN RAISE EXCEPTION 'T3 retry returned null'; END IF;
  IF (SELECT remaining_qty FROM factory_roll_balances WHERE roll_id=(SELECT roll_a FROM v5_ctx))<>28 THEN
    RAISE EXCEPTION 'T3 retry double-deducted';
  END IF;
  RAISE NOTICE 'PASS T3 repeated request id is idempotent';
END $$;

-- صرف من الرول الثاني بواقي صغيرة (scrap)
SELECT factory_roll_issue_internal('b6000000-0000-4000-8000-000000000003',(SELECT roll_b FROM v5_ctx),(SELECT wo FROM v5_ctx),9,'consumption',0,1,'بواقي طرف');

DO $$ DECLARE v_blocked boolean:=false; BEGIN
  -- صرف يزيد عن المتبقي
  BEGIN
    PERFORM factory_issue_roll('b6000000-0000-4000-8000-000000000004',(SELECT roll_a FROM v5_ctx),(SELECT wo FROM v5_ctx),29,'consumption',null);
    RAISE EXCEPTION 'T3 over-issue accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%المتبقي بالرول لا يكفي%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T3 over-issue not rejected'; END IF;
  RAISE NOTICE 'PASS T3 over-issue beyond roll remaining rejected';
END $$;

DO $$ DECLARE v_blocked boolean:=false; BEGIN
  -- تكرار الطلب بكمية مختلفة
  BEGIN
    PERFORM factory_issue_roll('b6000000-0000-4000-8000-000000000001',(SELECT roll_a FROM v5_ctx),(SELECT wo FROM v5_ctx),11,'consumption','دفعة أولى');
    RAISE EXCEPTION 'T3 conflicting retry accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%مفتاح العملية%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T3 conflicting retry not rejected'; END IF;
  RAISE NOTICE 'PASS T3 same request id with different quantity rejected';
END $$;

-- ===========================================================================
-- T4) تقسيم بقية: الرول الأم يُستنفد والبقية رصيد مستقل قابل للصرف
-- ===========================================================================
DO $$ DECLARE v_new uuid; v_rem numeric; v_other numeric; v_blocked boolean:=false; BEGIN
  v_new := factory_split_roll_remainder('b7000000-0000-4000-8000-000000000001',(SELECT roll_a FROM v5_ctx),16,'V5-A-REST');
  SELECT remaining_qty INTO v_rem FROM factory_roll_balances WHERE roll_id=(SELECT roll_a FROM v5_ctx);
  SELECT remaining_qty INTO v_other FROM factory_roll_balances WHERE roll_id=v_new;
  IF v_rem<>12 OR v_other<>16 THEN RAISE EXCEPTION 'T4 split balances wrong % / %',v_rem,v_other; END IF;
  IF (SELECT count(*) FROM factory_roll_moves WHERE movement_type='remainder')<>1
     OR (SELECT count(*) FROM factory_roll_moves WHERE parent_roll_id=(SELECT roll_a FROM v5_ctx) AND movement_type='receipt')<>1 THEN
    RAISE EXCEPTION 'T4 split ledger rows wrong';
  END IF;
  -- لا يمكن تقسيم نفس الرول مرتين
  BEGIN
    PERFORM factory_split_roll_remainder('b7000000-0000-4000-8000-000000000002',(SELECT roll_a FROM v5_ctx),5,'V5-A-REST2');
    RAISE EXCEPTION 'T4 double split accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%تم تقسيم%' AND SQLERRM NOT LIKE '%مفتاح العملية%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS T4 remainder split creates an independent roll and blocks double splitting';
END $$;

UPDATE v5_ctx SET roll_a=(SELECT id FROM factory_rolls WHERE roll_code='V5-A-REST');
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

-- ===========================================================================
-- T5) إجمالي مخزون FEDO = مجموع أرصدة الرولات في كل خطوة
-- ===========================================================================
DO $$ DECLARE v_rolls numeric; v_stock numeric; v_value numeric; BEGIN
  SELECT sum(remaining_qty),sum(value_remaining) INTO v_rolls,v_value FROM factory_roll_balances
   WHERE product_id=(SELECT prod FROM v5_ctx);
  SELECT qty INTO v_stock FROM stock_balances WHERE product_id=(SELECT prod FROM v5_ctx) AND warehouse_id=(SELECT wh FROM v5_ctx);
  IF v_rolls<>v_stock THEN RAISE EXCEPTION 'T5 roll ledger % <> FEDO stock %',v_rolls,v_stock; END IF;
  IF v_value<>round(v_stock*10,2) THEN RAISE EXCEPTION 'T5 roll value % <> stock value at avg cost %',v_value,v_stock*10; END IF;
  RAISE NOTICE 'PASS T5 roll ledger equals FEDO stock (%) and value (%)',v_rolls,v_value;
END $$;

-- ===========================================================================
-- T6) منع الالتفاف على الدفتر: حركة مخزون مباشرة تُرفض
-- ===========================================================================
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    PERFORM apply_stock((SELECT prod FROM v5_ctx),(SELECT wh FROM v5_ctx),-1,'Sale','test_bypass',gen_random_uuid());
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%اختلاف مخزون الصنف%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T6 direct stock bypass allowed'; END IF;
  RAISE NOTICE 'PASS T6 untracked stock mutation rejected';
END $$;

-- لا يمكن تعديل أو حذف حركة رول
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    UPDATE factory_roll_moves SET quantity_delta=quantity_delta-1 WHERE id=(SELECT id FROM factory_roll_moves WHERE movement_type='consumption' ORDER BY created_at LIMIT 1);
    -- الحارس على الدفتر مؤجل إلى نهاية المعاملة، لذا نجعله فوريًا داخل الاختبار
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'T6 ledger update accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%لا يقبل التعديل%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T6 ledger update not blocked'; END IF;
  RAISE NOTICE 'PASS T6 roll ledger is append-only';
END $$;

-- ===========================================================================
-- T7) الصلاحيات: مبيعات مرفوض، custom بلا mfg مرفوض، anon مرفوض، وكتابة
--     مباشرة على الجداول مرفوضة.
-- ===========================================================================
SELECT set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true); -- sales
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    PERFORM factory_issue_roll('b6000000-0000-4000-8000-000000000005',(SELECT roll_b FROM v5_ctx),(SELECT wo FROM v5_ctx),1,'consumption',null);
    RAISE EXCEPTION 'T7 sales role issued a roll';
  EXCEPTION WHEN insufficient_privilege THEN v_blocked:=true;
           WHEN OTHERS THEN IF SQLERRM NOT LIKE '%صلاحية%' THEN RAISE; ELSE v_blocked:=true; END IF; END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T7 sales role not denied'; END IF;
  BEGIN
    PERFORM factory_buy_rolls('b5000000-0000-4000-8000-000000000009',(SELECT 'b3000000-0000-4000-8000-000000000001'::uuid),(SELECT wh FROM v5_ctx),(SELECT prod FROM v5_ctx),10,'[{"code":"X","color":"c","width":1,"qty":1}]');
    RAISE EXCEPTION 'T7 sales role purchased rolls';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
           WHEN OTHERS THEN IF SQLERRM NOT LIKE '%صلاحية%' THEN RAISE; END IF; END;
  RAISE NOTICE 'PASS T7 sales role denied roll issue and roll purchase';
END $$;

SELECT set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000004',true); -- custom store with stk only
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    PERFORM factory_issue_roll('b6000000-0000-4000-8000-000000000006',(SELECT roll_b FROM v5_ctx),(SELECT wo FROM v5_ctx),1,'consumption',null);
    RAISE EXCEPTION 'T7 custom user without mfg issued a roll';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%صلاحية الشاشة%' AND SQLERRM NOT LIKE '%صلاحية%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T7 custom mfg denial missing'; END IF;
  RAISE NOTICE 'PASS T7 custom user with stk but no mfg denied roll issue';
END $$;

SET LOCAL ROLE authenticated;
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,unit_cost,created_by)
    VALUES(gen_random_uuid(),(SELECT roll_b FROM v5_ctx),'waste',-1,1,'b0000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'T7 direct ledger insert allowed';
  EXCEPTION WHEN insufficient_privilege THEN v_blocked:=true;
           WHEN OTHERS THEN IF SQLERRM NOT LIKE '%صلاحية%' AND SQLERRM NOT LIKE '%permission denied%' THEN RAISE; ELSE v_blocked:=true; END IF; END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T7 direct ledger insert not blocked'; END IF;
  RAISE NOTICE 'PASS T7 authenticated role cannot write roll ledger tables directly';
END $$;
RESET ROLE;

-- anon ممنوع من كل شيء
SET LOCAL ROLE anon;
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    PERFORM factory_issue_roll(gen_random_uuid(),(SELECT roll_b FROM v5_ctx),(SELECT wo FROM v5_ctx),1,'consumption',null);
    RAISE EXCEPTION 'T7 anon issued a roll';
  EXCEPTION WHEN insufficient_privilege THEN v_blocked:=true;
           WHEN OTHERS THEN v_blocked:=true; END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T7 anon not denied'; END IF;
  RAISE NOTICE 'PASS T7 anon denied';
END $$;
RESET ROLE;

-- ===========================================================================
-- T8) الدفتر لا يسمح بتعديل رصيد سالب أو تجاوز الكمية الأصلية
-- ===========================================================================
SELECT set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    INSERT INTO factory_rolls(roll_code,request_id,product_id,warehouse_id,supplier_id,unit_id,color,width,original_qty,unit_cost,received_date)
    VALUES('V5-NEG',(SELECT request_id FROM factory_rolls WHERE roll_code='V5-B'),(SELECT prod FROM v5_ctx),(SELECT wh FROM v5_ctx),
           'b3000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','x',1,5,10,current_date);
    RAISE EXCEPTION 'T8 extra roll after activation allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%تسجيل رول إضافي%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS T8 direct roll registration after activation blocked';
END $$;

DO $$ DECLARE v_blocked boolean:=false; BEGIN
  BEGIN
    -- رصيد سالب: تجاوز المتبقي ثم تحقق الحارس
    INSERT INTO factory_roll_moves(request_id,roll_id,movement_type,quantity_delta,work_order_id,stock_movement_id,unit_cost,created_by)
    VALUES(gen_random_uuid(),(SELECT roll_a FROM v5_ctx),'consumption',-999,(SELECT wo FROM v5_ctx),
      (SELECT id FROM stock_movements LIMIT 1),10,'b0000000-0000-4000-8000-000000000001');
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'T8 negative roll balance allowed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%رصيد الرول سالب%' AND SQLERRM NOT LIKE '%اختلاف مخزون الصنف%' THEN RAISE; END IF;
    v_blocked:=true;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  IF NOT v_blocked THEN RAISE EXCEPTION 'T8 negative balance guard missing'; END IF;
  RAISE NOTICE 'PASS T8 negative roll balance blocked by ledger guard';
END $$;

-- ===========================================================================
-- T9) الفلتر العام لصلاحية mfg لدور المستودع
-- ===========================================================================
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM role_default_perms WHERE role='store' AND perm='mfg') THEN
    RAISE EXCEPTION 'T9 store role lost mfg permission';
  END IF;
  RAISE NOTICE 'PASS T9 store role keeps mfg permission';
END $$;

SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
ROLLBACK;
