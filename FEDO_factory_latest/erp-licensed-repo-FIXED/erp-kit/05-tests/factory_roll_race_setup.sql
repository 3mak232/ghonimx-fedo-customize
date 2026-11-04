-- This commits fixtures: only in a disposable database named fedo_roll_race.
DO $$ BEGIN IF current_database()<>'fedo_roll_race' THEN RAISE EXCEPTION 'wrong database'; END IF; END $$;
INSERT INTO auth.users(id,email) VALUES ('95000000-0000-4000-8000-000000000001','race-admin@test.invalid');
UPDATE profiles SET role='admin',active=true WHERE id='95000000-0000-4000-8000-000000000001';
INSERT INTO units(id,name) VALUES('95000000-0000-4000-8000-000000000003','roll-race-unit');
INSERT INTO warehouses(id,name) VALUES('95000000-0000-4000-8000-000000000010','roll-race-warehouse');
INSERT INTO products(id,name,code,unit_id) VALUES
 ('95000000-0000-4000-8000-000000000004','race fabric','RACE-FABRIC','95000000-0000-4000-8000-000000000003'),
 ('95000000-0000-4000-8000-000000000005','race output','RACE-OUTPUT','95000000-0000-4000-8000-000000000003');
INSERT INTO suppliers(id,name) VALUES('95000000-0000-4000-8000-000000000006','race supplier');
INSERT INTO boms(id,product_id,version) VALUES('95000000-0000-4000-8000-000000000007','95000000-0000-4000-8000-000000000005','race');
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',false);
SELECT set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE inv uuid; it uuid; BEGIN
 inv:=create_purchase('95000000-0000-4000-8000-000000000006','95000000-0000-4000-8000-000000000010','[{"product_id":"95000000-0000-4000-8000-000000000004","qty":40,"price":10}]');
 SELECT id INTO it FROM purchase_invoice_items WHERE invoice_id=inv;
 PERFORM factory_register_rolls('95000000-0000-4000-8000-000000000008','invoice',it,'[{"code":"RACE-ROLL","color":"blue","width":1,"qty":40}]');
 PERFORM factory_activate_roll_control('95000000-0000-4000-8000-000000000004','95000000-0000-4000-8000-000000000010');
 INSERT INTO work_orders(id,number,bom_id,warehouse_id,planned_qty) VALUES
 ('95000000-0000-4000-8000-000000000011','RACE-WO-1','95000000-0000-4000-8000-000000000007','95000000-0000-4000-8000-000000000010',1),
 ('95000000-0000-4000-8000-000000000012','RACE-WO-2','95000000-0000-4000-8000-000000000007','95000000-0000-4000-8000-000000000010',1);
END $$;
