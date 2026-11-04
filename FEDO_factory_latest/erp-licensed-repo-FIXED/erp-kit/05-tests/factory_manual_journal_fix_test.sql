-- Disposable test database only. Fixtures and journals roll back.
BEGIN;
INSERT INTO auth.users(id,email) VALUES
('92000000-0000-4000-8000-000000000001','manual-journal-admin@test.invalid'),
('92000000-0000-4000-8000-000000000002','manual-journal-sales@test.invalid'),
('92000000-0000-4000-8000-000000000003','manual-journal-custom@test.invalid'),
('92000000-0000-4000-8000-000000000004','manual-journal-accountant@test.invalid');
UPDATE profiles SET active=true, role=CASE id::text
 WHEN '92000000-0000-4000-8000-000000000001' THEN 'admin'
 WHEN '92000000-0000-4000-8000-000000000002' THEN 'sales'
 ELSE 'accountant' END,
 permissions_mode=CASE WHEN id='92000000-0000-4000-8000-000000000003' THEN 'custom' ELSE 'role' END
 WHERE id::text LIKE '92000000-0000-4000-8000-00000000000%';
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE j uuid; debit_total numeric; credit_total numeric; blocked boolean; BEGIN
 j:=create_manual_journal(current_date,'factory-journal-fix-test',
 '[{"account_code":"1000","debit":25},{"account_code":"3000","credit":25}]');
 SELECT sum(debit),sum(credit) INTO debit_total,credit_total FROM journal_lines WHERE entry_id=j;
 IF debit_total<>25 OR credit_total<>25 THEN RAISE EXCEPTION 'balanced journal failed'; END IF;
 RAISE NOTICE 'PASS: valid manual journal posts balanced lines';
 blocked:=false;
 BEGIN PERFORM create_manual_journal(current_date,'bad account',
 '[{"account_code":"NOT-EXIST","debit":25},{"account_code":"3000","credit":25}]');
 EXCEPTION WHEN OTHERS THEN IF position('حساب غير موجود' in SQLERRM)>0 THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'unknown account accepted'; END IF;
 RAISE NOTICE 'PASS: unknown account rejected';
 blocked:=false;
 BEGIN PERFORM create_manual_journal(current_date,'unbalanced',
 '[{"account_code":"1000","debit":25},{"account_code":"3000","credit":24}]');
 EXCEPTION WHEN OTHERS THEN IF position('غير متوازن' in SQLERRM)>0 THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'unbalanced journal accepted'; END IF;
 RAISE NOTICE 'PASS: unbalanced journal rejected';
END $$;
SELECT set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
DO $$ DECLARE j uuid; BEGIN
 j:=create_manual_journal(current_date,'accountant allowed',
 '[{"account_code":"1000","debit":1},{"account_code":"3000","credit":1}]');
 IF j IS NULL THEN RAISE EXCEPTION 'accountant journal failed'; END IF;
 RAISE NOTICE 'PASS: accountant can post';
END $$;
SELECT set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM create_manual_journal(current_date,'sales denied',
 '[{"account_code":"1000","debit":1},{"account_code":"3000","credit":1}]');
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%صلاحية%' THEN blocked:=true; ELSE RAISE; END IF; END;
 IF NOT blocked THEN RAISE EXCEPTION 'sales was allowed'; END IF;
 RAISE NOTICE 'PASS: sales role denied';
END $$;
SELECT set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
DO $$ DECLARE blocked boolean:=false; BEGIN
 BEGIN PERFORM create_manual_journal(current_date,'custom denied',
 '[{"account_code":"1000","debit":1},{"account_code":"3000","credit":1}]');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'custom accountant without jr was allowed'; END IF;
 RAISE NOTICE 'PASS: custom accountant without jr denied';
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.create_manual_journal(date,text,jsonb)','EXECUTE') THEN
 RAISE EXCEPTION 'anon can execute journal'; END IF;
 RAISE NOTICE 'PASS: anon denied';
END $$;
ROLLBACK;
