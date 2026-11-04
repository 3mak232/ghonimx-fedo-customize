# اختبار محلي (اختياري)
1. `createdb erp_test` على Postgres 16.
2. `psql -d erp_test -f supabase_shim.sql` (بيعمل أدوار و schema auth و storage تقليد لـ Supabase).
3. `psql -d erp_test -f ../01-database/ERP_BASE_CURRENT.sql`
4. `psql -d erp_test -f ERP_rls_audit_READ_ONLY.sql`
ده اختبار للتركيب فقط، مش بديل عن Supabase الحقيقي.
