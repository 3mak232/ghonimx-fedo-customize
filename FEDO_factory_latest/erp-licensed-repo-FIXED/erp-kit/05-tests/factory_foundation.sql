-- Disposable PostgreSQL/Supabase staging only. Run with ON_ERROR_STOP=1. Rolls back fixtures.
BEGIN;
INSERT INTO auth.users(id,email) VALUES
('10000000-0000-4000-8000-000000000001','factory-admin@test.invalid'),
('10000000-0000-4000-8000-000000000002','factory-store@test.invalid'),
('10000000-0000-4000-8000-000000000003','factory-sales@test.invalid'),
('10000000-0000-4000-8000-000000000004','factory-custom@test.invalid'),
('10000000-0000-4000-8000-000000000005','factory-accountant@test.invalid');
UPDATE profiles SET active=true,role=CASE id::text
  WHEN '10000000-0000-4000-8000-000000000001' THEN 'admin'
  WHEN '10000000-0000-4000-8000-000000000002' THEN 'store'
  WHEN '10000000-0000-4000-8000-000000000003' THEN 'sales'
  WHEN '10000000-0000-4000-8000-000000000004' THEN 'store'
  ELSE 'accountant' END,
  permissions_mode=CASE WHEN id='10000000-0000-4000-8000-000000000004' THEN 'custom' ELSE 'role' END
  WHERE id::text LIKE '10000000-0000-4000-8000-00000000000%';
INSERT INTO units(id,name) VALUES('20000000-0000-4000-8000-000000000001','factory-test-unit');
INSERT INTO products(id,name,code,unit_id) VALUES
('30000000-0000-4000-8000-000000000001','factory-test-fabric','FCT-FAB','20000000-0000-4000-8000-000000000001'),
('30000000-0000-4000-8000-000000000002','factory-test-parent','FCT-PARENT','20000000-0000-4000-8000-000000000001'),
('30000000-0000-4000-8000-000000000003','factory-test-variant','FCT-VARIANT','20000000-0000-4000-8000-000000000001');
INSERT INTO suppliers(id,name) VALUES('40000000-0000-4000-8000-000000000001','factory-test-supplier');
CREATE TEMP TABLE factory_test_context(invoice uuid, item uuid, wh uuid, stock_before numeric);
GRANT SELECT,INSERT,UPDATE ON factory_test_context TO authenticated;
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
INSERT INTO factory_test_context(wh) SELECT id FROM warehouses LIMIT 1;
UPDATE factory_test_context SET invoice=public.create_purchase('40000000-0000-4000-8000-000000000001',wh,'[{"product_id":"30000000-0000-4000-8000-000000000001","qty":100,"price":7}]'::jsonb);
UPDATE factory_test_context SET item=(SELECT id FROM purchase_invoice_items WHERE invoice_id=factory_test_context.invoice),stock_before=(SELECT qty FROM stock_balances WHERE product_id='30000000-0000-4000-8000-000000000001' AND warehouse_id=factory_test_context.wh);
DO $$ BEGIN IF (SELECT stock_before FROM factory_test_context)<>100 THEN RAISE EXCEPTION 'purchase baseline stock failed'; END IF; RAISE NOTICE 'PASS: base purchase posts 100'; END $$;
SELECT public.factory_link_variant('30000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000003','أزرق','كبير');
DO $$ BEGIN IF (SELECT count(*) FROM factory_variants)<>1 THEN RAISE EXCEPTION 'variant link failed'; END IF; RAISE NOTICE 'PASS: distinct product variant linked'; END $$;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
SELECT factory_register_rolls('50000000-0000-4000-8000-000000000001','invoice',(SELECT item FROM factory_test_context),'[{"code":"FCT-R1","color":"أزرق","width":1.5,"qty":40},{"code":"FCT-R2","color":"أزرق","width":1.5,"qty":60}]');
SELECT factory_register_rolls('50000000-0000-4000-8000-000000000001','invoice',(SELECT item FROM factory_test_context),'[{"code":"FCT-R1","color":"أزرق","width":1.5,"qty":40},{"code":"FCT-R2","color":"أزرق","width":1.5,"qty":60}]');
DO $$ DECLARE blocked boolean:=false; BEGIN
 IF (SELECT count(*) FROM factory_rolls)<>2 OR (SELECT sum(original_qty) FROM factory_rolls)<>100 THEN RAISE EXCEPTION 'roll registration/retry failed'; END IF;
 IF (SELECT qty FROM stock_balances WHERE product_id='30000000-0000-4000-8000-000000000001' AND warehouse_id=(SELECT wh FROM factory_test_context))<>100 THEN RAISE EXCEPTION 'double stock posting'; END IF;
 RAISE NOTICE 'PASS: two rolls and retry do not double stock';
 BEGIN PERFORM factory_register_rolls('50000000-0000-4000-8000-000000000002','invoice',(SELECT item FROM factory_test_context),'[{"code":"FCT-R3","color":"blue","width":1,"qty":1}]'); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'over-allocation allowed'; END IF; RAISE NOTICE 'PASS: over-allocation rejected';
 blocked:=false;
 BEGIN PERFORM factory_register_rolls('50000000-0000-4000-8000-000000000001','invoice',(SELECT item FROM factory_test_context),'[{"code":"DIFFERENT","color":"blue","width":1,"qty":1}]'); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'idempotency mismatch allowed'; END IF; RAISE NOTICE 'PASS: conflicting retry rejected';
 blocked:=false;
 BEGIN INSERT INTO factory_rolls(roll_code) VALUES('BAD'); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'direct insert allowed'; END IF; RAISE NOTICE 'PASS: direct table writes denied';
END $$;
-- GRN and invoice from GRN: allocating both paths is forbidden.
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
DO $$ DECLARE po uuid; gr uuid; gri uuid; inv uuid; ii uuid; wh uuid; blocked boolean:=false; BEGIN
 SELECT warehouse_id INTO wh FROM factory_rolls LIMIT 1;
 po:=create_purchase_order('40000000-0000-4000-8000-000000000001',wh,'[{"product_id":"30000000-0000-4000-8000-000000000001","qty":30,"price":7}]');
 gr:=create_goods_receipt(po,'[{"product_id":"30000000-0000-4000-8000-000000000001","qty":30,"cost":7}]');
 SELECT id INTO gri FROM goods_receipt_items WHERE receipt_id=gr;
 PERFORM factory_register_rolls('50000000-0000-4000-8000-000000000005','receipt',gri,'[{"code":"FCT-G1","color":"أبيض","width":1.5,"qty":10},{"code":"FCT-G2","color":"أبيض","width":1.5,"qty":20}]');
 inv:=create_purchase_invoice_from_receipt(gr);
 SELECT id INTO ii FROM purchase_invoice_items WHERE invoice_id=inv;
 BEGIN PERFORM factory_register_rolls('50000000-0000-4000-8000-000000000006','invoice',ii,'[{"code":"BAD-G1","color":"أبيض","width":1.5,"qty":10}]'); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked OR (SELECT count(*) FROM factory_rolls)<>4 THEN RAISE EXCEPTION 'receipt and invoice duplicate protection failed'; END IF;
 RAISE NOTICE 'PASS: GRN rolls and duplicate receipt-invoice rejected';
END $$;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM factory_register_rolls('50000000-0000-4000-8000-000000000003','invoice',(SELECT item FROM factory_test_context),'[{"code":"bad","color":"a","width":1,"qty":1}]'); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked OR (SELECT count(*) FROM factory_rolls)<>0 THEN RAISE EXCEPTION 'sales authorization failed'; END IF; RAISE NOTICE 'PASS: sales denied roll RPC and RLS';
END $$;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM factory_register_rolls('50000000-0000-4000-8000-000000000004','invoice',(SELECT item FROM factory_test_context),'[{"code":"bad","color":"a","width":1,"qty":1}]'); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked OR (SELECT count(*) FROM factory_rolls)<>0 THEN RAISE EXCEPTION 'custom permissions bypass'; END IF; RAISE NOTICE 'PASS: custom mode without stk denied';
 blocked:=false;
 BEGIN PERFORM create_work_order('30000000-0000-4000-8000-000000000001',(SELECT wh FROM factory_test_context),1,0,0); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'old create_work_order permission bypass'; END IF;
 blocked:=false;
 BEGIN PERFORM complete_work_order('30000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'old complete_work_order permission bypass'; END IF;
 RAISE NOTICE 'PASS: legacy manufacturing RPCs deny custom user without mfg';
END $$;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
DO $$ BEGIN IF (SELECT count(*) FROM factory_rolls)<>4 THEN RAISE EXCEPTION 'accountant should see metadata'; END IF; RAISE NOTICE 'PASS: accountant can read'; END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_table_privilege('anon','factory_rolls','SELECT') OR has_function_privilege('anon','factory_register_rolls(uuid,text,uuid,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'anon privilege leak'; END IF;
 RAISE NOTICE 'PASS: anonymous denied';
END $$;
ROLLBACK;
