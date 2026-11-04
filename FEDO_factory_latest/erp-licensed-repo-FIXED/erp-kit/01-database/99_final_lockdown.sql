-- ============================================================================
-- 99_final_lockdown.sql  |  شغّله آخر ملف SQL في كل مشروع عميل (بعد ERP_BASE_CURRENT.sql ثم LICENSE_MODULE.sql)
-- وشغّله تاني بعد أي تحديث SQL لاحق. آمن تشغيله أكتر من مرة (idempotent).
-- الغرض: ما يفضلش لـ anon (الزوار من غير تسجيل دخول) أي صلاحية جدول أو دالة غير:
--   app_version() و app_lock_state()  (مقصودة، بتتنادى قبل تسجيل الدخول).
-- ============================================================================

-- 1) الجداول والتسلسلات: سحب أي صلاحية من anon، وتغيير الافتراضي للجداول الجديدة
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;

-- 2) الدوال: أي دالة في public متاحة لـ anon (ما عدا المقصودة) تتقفل عنه.
--    المسجّلون (authenticated) بيحتفظوا بصلاحيتهم لو كانت عندهم قبل كده، ما عدا دوال الـ triggers (مش بتتنادى من الـ API).
DO $$
DECLARE
  r record;
  keep text[] := ARRAY['app_version','app_lock_state'];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig,
           (p.prorettype = 'trigger'::regtype) AS is_trg,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_had
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind IN ('f','p')
      AND NOT (p.proname = ANY (keep))
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    IF r.is_trg THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.sig);
    ELSIF r.auth_had THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    END IF;
  END LOOP;
END $$;

-- 3) فحص نهائي: كل القيم لازم تكون 0، وبعدها شغّل 07-local-test/ERP_rls_check_combined_READ_ONLY.sql
SELECT
  (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='public' AND grantee='anon') AS anon_table_privileges,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND has_function_privilege('anon',p.oid,'EXECUTE')
       AND p.proname NOT IN ('app_version','app_lock_state')) AS anon_unexpected_functions,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity) AS tables_without_rls;
