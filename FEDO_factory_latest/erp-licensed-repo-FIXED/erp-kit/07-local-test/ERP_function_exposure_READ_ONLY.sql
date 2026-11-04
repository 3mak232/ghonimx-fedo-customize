-- دوال SECURITY DEFINER متاحة للمسجّلين (authenticated) وما فيهاش أي فحص دور/مستخدم واضح — للمراجعة اليدوية، للقراءة فقط.
-- القايمة دي مش معناها ثغرة بالضرورة (ممكن الفحص يتم بطريقة تانية)، لكن كل اسم لازم تعرف ليه مفتوح.
select p.proname as function_name, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef and p.prorettype <> 'trigger'::regtype
  and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  and p.proname not in ('app_version','app_lock_state')
  and pg_get_functiondef(p.oid) !~* '(require_role|auth_role|require_perm|has_perm|require_dev|is_developer|license_is_dev|auth\.uid)'
order by 1;
