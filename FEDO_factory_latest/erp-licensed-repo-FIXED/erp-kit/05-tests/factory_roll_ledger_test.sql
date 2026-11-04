-- PostgreSQL local test ONLY. Owner invokes PRIVATE primitives to exercise the
-- backend; there is deliberately NO user-exposed stock-issue or GL posting yet.
BEGIN;
INSERT INTO auth.users(id,email) VALUES
 ('94000000-0000-4000-8000-000000000001','roll-admin@test.invalid'),
 ('94000000-0000-4000-8000-000000000002','roll-sales@test.invalid');
UPDATE profiles SET role=CASE WHEN id='94000000-0000-4000-8000-000000000001' THEN 'admin' ELSE 'sales' END,active=true WHERE id::text LIKE '94000000-0000-4000-8000-00000000000%';
INSERT INTO units(id,name) VALUES('94000000-0000-4000-8000-000000000003','roll-test-unit');
INSERT INTO products(id,name,code,unit_id) VALUES
 ('94000000-0000-4000-8000-000000000004','roll fabric','ROLL-V4-MAT','94000000-0000-4000-8000-000000000003'),
 ('94000000-0000-4000-8000-000000000005','roll finished','ROLL-V4-FIN','94000000-0000-4000-8000-000000000003');
INSERT INTO suppliers(id,name) VALUES('94000000-0000-4000-8000-000000000006','roll supplier');
INSERT INTO boms(id,product_id,version) VALUES('94000000-0000-4000-8000-000000000007','94000000-0000-4000-8000-000000000005','roll-v4');
INSERT INTO bom_items(bom_id,component_product_id,qty) VALUES('94000000-0000-4000-8000-000000000007','94000000-0000-4000-8000-000000000004',2);
CREATE TEMP TABLE roll_ctx(wh uuid, invoice uuid, item uuid, wo uuid, roll1 uuid, roll2 uuid);
GRANT ALL ON roll_ctx TO authenticated;
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
INSERT INTO roll_ctx(wh) SELECT id FROM warehouses LIMIT 1;
UPDATE roll_ctx SET invoice=create_purchase('94000000-0000-4000-8000-000000000006',wh,'[{"product_id":"94000000-0000-4000-8000-000000000004","qty":100,"price":10}]');
UPDATE roll_ctx SET item=(SELECT id FROM purchase_invoice_items WHERE invoice_id=roll_ctx.invoice);
SELECT factory_register_rolls('94000000-0000-4000-8000-000000000008','invoice',(SELECT item FROM roll_ctx),'[{"code":"ROLL-V4-1","color":"blue","width":1.5,"qty":40}]');
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM factory_activate_roll_control('94000000-0000-4000-8000-000000000004',(SELECT wh FROM roll_ctx)); EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%لا يمكن تفعيل%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'incomplete roll inventory allowed'; END IF; RAISE NOTICE 'PASS activation requires reconciliation';
END $$;
SELECT factory_register_rolls('94000000-0000-4000-8000-000000000009','invoice',(SELECT item FROM roll_ctx),'[{"code":"ROLL-V4-2","color":"blue","width":1.5,"qty":60}]');
UPDATE roll_ctx SET roll1=(SELECT id FROM factory_rolls WHERE roll_code='ROLL-V4-1'),roll2=(SELECT id FROM factory_rolls WHERE roll_code='ROLL-V4-2');
SELECT factory_activate_roll_control('94000000-0000-4000-8000-000000000004',(SELECT wh FROM roll_ctx));
UPDATE roll_ctx SET wo=create_work_order('94000000-0000-4000-8000-000000000007',wh,1);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$ BEGIN
 IF (SELECT count(*) FROM factory_roll_moves WHERE movement_type='receipt')<>2 OR (SELECT sum(remaining_qty) FROM factory_roll_balances)<>100 THEN RAISE EXCEPTION 'receipt or starting balance incorrect'; END IF;
 IF has_function_privilege('authenticated','factory_consume_roll_internal(uuid,uuid,uuid,numeric,text)','EXECUTE') OR has_function_privilege('anon','factory_consume_roll_internal(uuid,uuid,uuid,numeric,text)','EXECUTE') THEN RAISE EXCEPTION 'internal RPC exposed'; END IF;
 RAISE NOTICE 'PASS receipt ledger balances and private issue primitive';
END $$;
RESET ROLE;
DO $$ DECLARE a uuid; b uuid; q numeric; blocked boolean:=false; BEGIN
 a:=factory_consume_roll_internal('94000000-0000-4000-8000-000000000010',(SELECT roll1 FROM roll_ctx),(SELECT wo FROM roll_ctx),12,'consumption');
 b:=factory_consume_roll_internal('94000000-0000-4000-8000-000000000010',(SELECT roll1 FROM roll_ctx),(SELECT wo FROM roll_ctx),12,'consumption');
 IF a<>b THEN RAISE EXCEPTION 'retry is not idempotent'; END IF;
 PERFORM factory_consume_roll_internal('94000000-0000-4000-8000-000000000011',(SELECT roll1 FROM roll_ctx),(SELECT wo FROM roll_ctx),3,'waste');
 SET CONSTRAINTS ALL IMMEDIATE;
 SELECT remaining_qty INTO q FROM factory_roll_balances WHERE roll_id=(SELECT roll1 FROM roll_ctx);
 IF q<>25 OR (SELECT qty FROM stock_balances WHERE product_id='94000000-0000-4000-8000-000000000004' AND warehouse_id=(SELECT wh FROM roll_ctx))<>85 THEN RAISE EXCEPTION 'wrong roll or stock remaining'; END IF;
 IF (SELECT count(*) FROM factory_roll_moves WHERE work_order_id=(SELECT wo FROM roll_ctx) AND movement_type IN ('consumption','waste'))<>2 THEN RAISE EXCEPTION 'wrong work order movement history'; END IF;
 RAISE NOTICE 'PASS partial consumption waste remainder trace and idempotency';
 SET CONSTRAINTS ALL DEFERRED;
 BEGIN PERFORM factory_consume_roll_internal('94000000-0000-4000-8000-000000000012',(SELECT roll1 FROM roll_ctx),(SELECT wo FROM roll_ctx),26,'consumption'); EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%المتبقي بالرول%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'overconsumption accepted'; END IF; RAISE NOTICE 'PASS insufficient roll rejected';
 blocked:=false;
 BEGIN PERFORM factory_consume_roll_internal('94000000-0000-4000-8000-000000000010',(SELECT roll1 FROM roll_ctx),(SELECT wo FROM roll_ctx),11,'consumption'); EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%مفتاح العملية%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'changed retry accepted'; END IF; RAISE NOTICE 'PASS conflicting retry rejected';
 -- Existing paths must not silently bypass roll ledger.
 blocked:=false;
 BEGIN
   PERFORM apply_stock('94000000-0000-4000-8000-000000000004',(SELECT wh FROM roll_ctx),-1,'Sale','test_bypass',gen_random_uuid());
   SET CONSTRAINTS ALL IMMEDIATE;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%اختلاف مخزون الصنف%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'legacy stock bypass allowed'; END IF; RAISE NOTICE 'PASS untracked stock mutation rejected';
 SET CONSTRAINTS ALL DEFERRED;
 blocked:=false;
 BEGIN
   PERFORM complete_work_order((SELECT wo FROM roll_ctx));
   SET CONSTRAINTS ALL IMMEDIATE;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%اختلاف مخزون الصنف%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'legacy completion bypass allowed'; END IF;
 IF (SELECT status FROM work_orders WHERE id=(SELECT wo FROM roll_ctx))='Completed' THEN RAISE EXCEPTION 'legacy completion was not rolled back'; END IF;
 RAISE NOTICE 'PASS legacy manufacturing consumption is rejected and rolled back';
 SET CONSTRAINTS ALL DEFERRED;
 blocked:=false;
 BEGIN
   PERFORM create_purchase('94000000-0000-4000-8000-000000000006',(SELECT wh FROM roll_ctx),'[{"product_id":"94000000-0000-4000-8000-000000000004","qty":1,"price":10}]');
   SET CONSTRAINTS ALL IMMEDIATE;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%اختلاف مخزون الصنف%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'legacy purchase bypass allowed'; END IF;
 RAISE NOTICE 'PASS untracked receipt rejected until atomic tracked receipt exists';
 SET CONSTRAINTS ALL DEFERRED;
END $$;
-- Atomic purchase of multiple new managed rolls, repeat and journal check.
SET LOCAL ROLE authenticated;
DO $$ DECLARE a uuid; b uuid; blocked boolean:=false; d numeric; c numeric; BEGIN
 a:=factory_purchase_managed_rolls('94000000-0000-4000-8000-000000000013','94000000-0000-4000-8000-000000000006',(SELECT wh FROM roll_ctx),'94000000-0000-4000-8000-000000000004',10,'[{"code":"ROLL-V4-3","color":"blue","width":1.5,"qty":10},{"code":"ROLL-V4-4","color":"blue","width":1.5,"qty":20}]');
 b:=factory_purchase_managed_rolls('94000000-0000-4000-8000-000000000013','94000000-0000-4000-8000-000000000006',(SELECT wh FROM roll_ctx),'94000000-0000-4000-8000-000000000004',10,'[{"code":"ROLL-V4-3","color":"blue","width":1.5,"qty":10},{"code":"ROLL-V4-4","color":"blue","width":1.5,"qty":20}]');
 SET CONSTRAINTS ALL IMMEDIATE;
 IF a<>b OR (SELECT sum(remaining_qty) FROM factory_roll_balances)<>115 OR (SELECT qty FROM stock_balances WHERE product_id='94000000-0000-4000-8000-000000000004' AND warehouse_id=(SELECT wh FROM roll_ctx))<>115 THEN RAISE EXCEPTION 'atomic purchase or retry failed'; END IF;
 IF (SELECT count(*) FROM factory_rolls WHERE request_id='94000000-0000-4000-8000-000000000013')<>2 THEN RAISE EXCEPTION 'atomic purchase rolls missing'; END IF;
 SELECT sum(l.debit),sum(l.credit) INTO d,c FROM journal_entries j JOIN journal_lines l ON l.entry_id=j.id WHERE j.doc_type='purchase_invoice' AND j.doc_id=a;
 IF d<>300 OR c<>300 THEN RAISE EXCEPTION 'purchase GL failed % / %',d,c; END IF;
 BEGIN PERFORM factory_purchase_managed_rolls('94000000-0000-4000-8000-000000000013','94000000-0000-4000-8000-000000000006',(SELECT wh FROM roll_ctx),'94000000-0000-4000-8000-000000000004',11,'[{"code":"ROLL-V4-3","color":"blue","width":1.5,"qty":10},{"code":"ROLL-V4-4","color":"blue","width":1.5,"qty":20}]'); EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%مفتاح العملية%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'changed purchase retry accepted'; END IF;
 RAISE NOTICE 'PASS atomic multi-roll credit purchase retry, conflict and FEDO purchase journal';
 SET CONSTRAINTS ALL DEFERRED;
END $$;
SELECT set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
DO $$ DECLARE blocked boolean:=false; BEGIN
 IF (SELECT count(*) FROM factory_roll_balances)<>0 THEN RAISE EXCEPTION 'sales can read roll balances'; END IF;
 BEGIN PERFORM factory_activate_roll_control('94000000-0000-4000-8000-000000000004',(SELECT wh FROM roll_ctx));
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%صلاحية%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'sales can activate roll control'; END IF;
 RAISE NOTICE 'PASS sales denied activation and roll ledger visibility';
END $$;
ROLLBACK;
