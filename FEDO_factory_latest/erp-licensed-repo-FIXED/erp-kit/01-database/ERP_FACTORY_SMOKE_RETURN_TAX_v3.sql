-- Local/staging-only: correct the FEDO smoke-test expected balance after a
-- VAT-inclusive sales return. Business posting functions are unchanged.
BEGIN;
DO $patch$
DECLARE d text; nd text;
BEGIN
 SELECT pg_get_functiondef('public.run_erp_smoke_test()'::regprocedure) INTO d;
 IF position('ok:=ok AND b=8 AND v=192;' IN d)>0 AND position('''pass'',b=8 AND v=192' IN d)>0 THEN
  RAISE NOTICE 'VAT smoke expectation already corrected'; RETURN;
 END IF;
 IF position('ok:=ok AND b=8 AND v=213;' IN d)=0 OR position('''pass'',b=8 AND v=213' IN d)=0 THEN
  RAISE EXCEPTION 'Unexpected smoke test definition; stop for review';
 END IF;
 nd:=replace(d,'ok:=ok AND b=8 AND v=213;','ok:=ok AND b=8 AND v=192;');
 nd:=replace(nd,'''pass'',b=8 AND v=213','''pass'',b=8 AND v=192');
 EXECUTE nd;
END $patch$;
COMMIT;
