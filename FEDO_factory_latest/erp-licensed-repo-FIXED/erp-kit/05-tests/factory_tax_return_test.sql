-- Independent VAT-inclusive sales return test. Disposable local database only.
BEGIN;
INSERT INTO auth.users(id,email) VALUES('93000000-0000-4000-8000-000000000001','tax-dev@test.invalid');
UPDATE profiles SET role='developer',active=true WHERE id='93000000-0000-4000-8000-000000000001';
UPDATE company_settings SET tax_enabled=true,tax_pct=14 WHERE id=1;
INSERT INTO products(id,name,code,avg_cost) VALUES('93000000-0000-4000-8000-000000000002','VAT test product','VAT-TEST-FACTORY',100);
INSERT INTO customers(id,name) VALUES('93000000-0000-4000-8000-000000000003','VAT test customer');
INSERT INTO suppliers(id,name) VALUES('93000000-0000-4000-8000-000000000004','VAT test supplier');
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE wh uuid; acc uuid; s uuid; r uuid; bal_before numeric; bal_after numeric; ret_total numeric; base numeric; tax numeric; cost numeric; d numeric; c numeric; matched integer; snapshot jsonb; rebuilt jsonb;
BEGIN
 SELECT id INTO wh FROM warehouses LIMIT 1; SELECT id INTO acc FROM cash_accounts WHERE type='cash' LIMIT 1;
 PERFORM create_purchase('93000000-0000-4000-8000-000000000004',wh,'[{"product_id":"93000000-0000-4000-8000-000000000002","qty":10,"price":100}]');
 s:=create_sale('93000000-0000-4000-8000-000000000003',wh,'[{"product_id":"93000000-0000-4000-8000-000000000002","qty":3,"price":150}]',100,acc,'cash');
 PERFORM record_payment('receipt','93000000-0000-4000-8000-000000000003',50,acc,jsonb_build_array(jsonb_build_object('invoice_id',s,'amount',50)));
 SELECT balance INTO bal_before FROM customer_balances WHERE id='93000000-0000-4000-8000-000000000003';
 r:=create_sales_return(s,'[{"product_id":"93000000-0000-4000-8000-000000000002","qty":1}]');
 SELECT balance INTO bal_after FROM customer_balances WHERE id='93000000-0000-4000-8000-000000000003';
 SELECT total INTO ret_total FROM sales_returns WHERE id=r;
 SELECT sum(i.line_total),sum(i.tax),sum(i.cost_total) INTO base,tax,cost FROM sales_return_items i WHERE i.return_id=r;
 IF bal_before<>363 OR bal_after<>192 OR bal_before-bal_after<>171 OR base<>150 OR tax<>21 OR ret_total<>171 OR cost<>100 THEN
 RAISE EXCEPTION 'wrong return before=% after=% base=% tax=% total=% cost=%',bal_before,bal_after,base,tax,ret_total,cost; END IF;
 SELECT coalesce(sum(l.debit),0),coalesce(sum(l.credit),0),
 count(*) FILTER (WHERE (l.account_code='4000' AND l.debit=150 AND l.credit=0) OR (l.account_code='2100' AND l.debit=21 AND l.credit=0) OR (l.account_code='1300' AND l.debit=0 AND l.credit=171) OR (l.account_code='1200' AND l.debit=100 AND l.credit=0) OR (l.account_code='5000' AND l.debit=0 AND l.credit=100)),
 jsonb_object_agg(l.account_code,jsonb_build_array(l.debit,l.credit))
 INTO d,c,matched,snapshot FROM journal_entries e JOIN journal_lines l ON l.entry_id=e.id WHERE e.doc_type='sales_return' AND e.doc_id=r;
 IF d<>271 OR c<>271 OR matched<>5 THEN RAISE EXCEPTION 'return journal wrong debit=% credit=% matched=%',d,c,matched; END IF;
 PERFORM rebuild_journal();
 SELECT jsonb_object_agg(l.account_code,jsonb_build_array(l.debit,l.credit)) INTO rebuilt FROM journal_entries e JOIN journal_lines l ON l.entry_id=e.id WHERE e.doc_type='sales_return' AND e.doc_id=r;
 IF rebuilt IS DISTINCT FROM snapshot THEN RAISE EXCEPTION 'journal rebuild changes return entry'; END IF;
 RAISE NOTICE 'PASS VAT return 150+21=171; customer 363->192; journal Dr revenue 150 VAT 21 inventory 100 / Cr AR 171 COGS 100; rebuild identical';
END $$;
ROLLBACK;
