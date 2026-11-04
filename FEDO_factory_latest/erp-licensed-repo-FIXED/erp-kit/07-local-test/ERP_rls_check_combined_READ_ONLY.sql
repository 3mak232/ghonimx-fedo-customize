-- فحص RLS وصلاحيات anon (أربعة فحوص في جدول واحد) — للقراءة فقط. المطلوب: صفوف النوع 1 و2 و3 تكون فاضية،
-- والنوع 4 فيه app_lock_state و app_version بس.
select '1 - جدول بدون RLS' as check_name, c.relname::text as item, ''::text as detail
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
union all
select '2 - سياسة مفتوحة للجميع', (tablename || '.' || policyname)::text, cmd::text
from pg_policies where schemaname = 'public' and (qual = 'true' or with_check = 'true')
union all
select '3 - صلاحية جدول لـ anon', table_name::text, privilege_type::text
from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon'
union all
select '4 - دالة متاحة لـ anon', p.proname::text, case when p.prosecdef then 'security definer' else 'invoker' end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
order by 1, 2;
