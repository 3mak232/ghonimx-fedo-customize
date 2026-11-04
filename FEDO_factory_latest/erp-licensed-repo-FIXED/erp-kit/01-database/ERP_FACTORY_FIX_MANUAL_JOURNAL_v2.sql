-- EXPERIMENTAL: staging only. Fix ambiguous PL/pgSQL variable in the existing
-- FEDO manual journal function without changing the base SQL or its privileges.
-- Preserves the installed function definition including require_role/require_perm.
-- Fails closed if the expected original snippets do not match; idempotent.
BEGIN;
DO $migration$
DECLARE d text; nd text;
BEGIN
 SELECT pg_get_functiondef('public.create_manual_journal(date,text,jsonb)'::regprocedure) INTO d;
 IF position('c numeric; v_code text;' IN d)>0
    AND position('v_code:=it->>''account_code''' IN d)>0
    AND position('a.code=v_code' IN d)>0
    AND position('حساب غير موجود: %'',v_code' IN d)>0 THEN
   RAISE NOTICE 'manual journal patch already applied'; RETURN;
 END IF;
 IF position('c numeric; code text;' IN d)=0
    OR position('code:=it->>''account_code''' IN d)=0
    OR position('a.code=code' IN d)=0
    OR position('حساب غير موجود: %'',code' IN d)=0 THEN
   RAISE EXCEPTION 'Unexpected create_manual_journal definition; stop and review installed function';
 END IF;
 nd:=replace(d,'c numeric; code text;','c numeric; v_code text;');
 nd:=replace(nd,'code:=it->>''account_code''','v_code:=it->>''account_code''');
 nd:=replace(nd,'a.code=code','a.code=v_code');
 nd:=replace(nd,'حساب غير موجود: %'',code','حساب غير موجود: %'',v_code');
 EXECUTE nd;
END $migration$;
COMMIT;
