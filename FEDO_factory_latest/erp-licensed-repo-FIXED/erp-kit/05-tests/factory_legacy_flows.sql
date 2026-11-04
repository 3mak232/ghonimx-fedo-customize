-- Disposable DB only: baseline flows after experimental migration, always rollback.
BEGIN;
INSERT INTO auth.users(id,email) VALUES('91000000-0000-4000-8000-000000000001','legacy-admin@test.invalid');
UPDATE profiles SET role='admin',active=true WHERE id='91000000-0000-4000-8000-000000000001';
INSERT INTO products(id,name,code,purchase_price,sale_price,avg_cost) VALUES('91000000-0000-4000-8000-000000000002','test product','LEGACY-FCT',10,20,10);
INSERT INTO customers(id,name) VALUES('91000000-0000-4000-8000-000000000003','test customer');
INSERT INTO suppliers(id,name) VALUES('91000000-0000-4000-8000-000000000004','test supplier');
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE wh uuid; pi uuid; si uuid; q numeric; dr numeric; cr numeric; BEGIN
 SELECT id INTO wh FROM warehouses LIMIT 1;
 pi:=create_purchase('91000000-0000-4000-8000-000000000004',wh,'[{"product_id":"91000000-0000-4000-8000-000000000002","qty":20,"price":10}]');
 si:=create_sale('91000000-0000-4000-8000-000000000003',wh,'[{"product_id":"91000000-0000-4000-8000-000000000002","qty":5,"price":20}]');
 PERFORM create_sales_return(si,'[{"product_id":"91000000-0000-4000-8000-000000000002","qty":1}]');
 PERFORM create_purchase_return(pi,'[{"product_id":"91000000-0000-4000-8000-000000000002","qty":2}]');
 SELECT qty INTO q FROM stock_balances WHERE warehouse_id=wh AND product_id='91000000-0000-4000-8000-000000000002';
 IF q<>14 THEN RAISE EXCEPTION 'unexpected stock: %',q; END IF;
 SELECT coalesce(sum(debit),0),coalesce(sum(credit),0) INTO dr,cr FROM journal_lines;
 IF dr=0 OR dr<>cr THEN RAISE EXCEPTION 'journal is not balanced: % %',dr,cr; END IF;
 RAISE NOTICE 'PASS: purchase, sale, sales return, purchase return: stock %; journal %/%',q,dr,cr;
END $$;
ROLLBACK;
