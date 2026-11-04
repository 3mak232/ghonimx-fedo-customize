-- Disposable database ONLY, name must be fedo_roll_v5_race. Commits fixtures.
DO $$ BEGIN IF current_database()<>'fedo_roll_v5_race' THEN RAISE EXCEPTION 'wrong database: run only on fedo_roll_v5_race'; END IF; END $$;
INSERT INTO auth.users(id,email) VALUES
 ('c5000000-0000-4000-8000-000000000001','v5race-admin@test.invalid'),
 ('c5000000-0000-4000-8000-000000000002','v5race-store@test.invalid');
UPDATE profiles SET active=true,role=CASE WHEN id='c5000000-0000-4000-8000-000000000001' THEN 'admin' ELSE 'store' END
 WHERE id::text LIKE 'c5000000-0000-4000-8000-00000000000%';
INSERT INTO units(id,name) VALUES('c5100000-0000-4000-8000-000000000001','v5race-unit');
INSERT INTO products(id,name,code,unit_id) VALUES
 ('c5200000-0000-4000-8000-000000000001','v5race fabric','V5RACE-FAB','c5100000-0000-4000-8000-000000000001'),
 ('c5200000-0000-4000-8000-000000000002','v5race output','V5RACE-OUT','c5100000-0000-4000-8000-000000000001');
INSERT INTO suppliers(id,name) VALUES('c5300000-0000-4000-8000-000000000001','v5race supplier');
INSERT INTO boms(id,product_id,version) VALUES('c5400000-0000-4000-8000-000000000001','c5200000-0000-4000-8000-000000000002','v5race');
INSERT INTO bom_items(bom_id,component_product_id,qty) VALUES('c5400000-0000-4000-8000-000000000001','c5200000-0000-4000-8000-000000000001',2);
INSERT INTO warehouses(id,name) VALUES('c5500000-0000-4000-8000-000000000001','v5race-warehouse');
SELECT set_config('erp.factory_ledger','on',false);
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',false);
SELECT set_config('request.jwt.claim.sub','c5000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
  PERFORM factory_enable_roll_tracking('c5200000-0000-4000-8000-000000000001','c5500000-0000-4000-8000-000000000001');
  PERFORM factory_buy_rolls('c5600000-0000-4000-8000-000000000001','c5300000-0000-4000-8000-000000000001',
    'c5500000-0000-4000-8000-000000000001','c5200000-0000-4000-8000-000000000001',10,
    '[{"code":"V5RACE-ROLL","color":"أزرق","width":1.5,"qty":40}]');
  -- أمران مستقلان يتنافسان على نفس الرول
  INSERT INTO work_orders(id,number,bom_id,warehouse_id,planned_qty) VALUES
   ('c5700000-0000-4000-8000-000000000001','V5RACE-WO-1','c5400000-0000-4000-8000-000000000001','c5500000-0000-4000-8000-000000000001',1),
   ('c5700000-0000-4000-8000-000000000002','V5RACE-WO-2','c5400000-0000-4000-8000-000000000001','c5500000-0000-4000-8000-000000000001',1);
END $$;
