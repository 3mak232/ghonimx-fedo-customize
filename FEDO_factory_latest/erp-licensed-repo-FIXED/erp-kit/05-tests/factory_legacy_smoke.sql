-- Disposable DB only. Exercise FEDO's existing smoke test with rollback.
BEGIN;
INSERT INTO auth.users(id,email) VALUES('90000000-0000-4000-8000-000000000001','factory-developer@test.invalid');
UPDATE profiles SET role='developer',active=true WHERE id='90000000-0000-4000-8000-000000000001';
SELECT set_config('request.jwt.claims','{"iat":4102444800,"aal":"aal2"}',true);
SELECT set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=run_erp_smoke_test();
 RAISE NOTICE 'smoke_result: %',r;
 IF coalesce((r->>'ok')::boolean,false) IS NOT TRUE THEN
   RAISE EXCEPTION 'FEDO smoke test returned ok=false; inspect smoke_result';
 END IF;
END $$;
ROLLBACK;
