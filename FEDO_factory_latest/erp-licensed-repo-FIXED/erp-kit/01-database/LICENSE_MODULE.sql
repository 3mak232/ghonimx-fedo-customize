-- ============================================================
-- وحدة الترخيص (تتشغّل عند كل عميل)
-- شغّلها مرة واحدة بعد ERP_BASE_CURRENT.sql على نفس المشروع.
-- بتعتمد على: profiles, branches, warehouses, app_control, log_event()
-- الفكرة: الحدود بتتنفذ بـ triggers في قاعدة البيانات نفسها، والتعديل بيجي من اللوحة بدالة موقّعة بس.
-- ============================================================
BEGIN;

-- 1) جدول الترخيص (صف واحد). NULL في أي حد = بدون حد.
CREATE TABLE IF NOT EXISTS license(
  id int PRIMARY KEY DEFAULT 1 CHECK(id=1),
  client_id text NOT NULL DEFAULT '',
  plan_code text NOT NULL DEFAULT 'unprovisioned',
  plan_name text,
  max_users int CHECK(max_users IS NULL OR max_users >= 0),
  max_branches int CHECK(max_branches IS NULL OR max_branches >= 0),
  max_warehouses int CHECK(max_warehouses IS NULL OR max_warehouses >= 0),
  modules text[],                       -- NULL = كل الوحدات
  storage_mb_warn int,                  -- تحذير فقط، مش منع
  status text NOT NULL DEFAULT 'active' CHECK(status IN('active','grace','readonly','suspended')),
  expires_at timestamptz,               -- للعرض والتنبيه بس. الإيقاف بيتم يدوي من اللوحة
  grace_until timestamptz,
  message text NOT NULL DEFAULT '',
  seq bigint NOT NULL DEFAULT 0,        -- حماية من إعادة إرسال أمر قديم
  schema_version text,                  -- بيتحدّث من أداة التحديثات
  license_locked boolean NOT NULL DEFAULT false, -- هل القفل الحالي جاي من الترخيص
  synced_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO license(id) VALUES(1) ON CONFLICT DO NOTHING;
ALTER TABLE license ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON license FROM PUBLIC, anon, authenticated;

-- 2) ربط الوحدات بالجداول بتاعتها (عدّلها حسب شاشاتك)
CREATE TABLE IF NOT EXISTS license_module_tables(
  module text NOT NULL, table_name text NOT NULL, PRIMARY KEY(module, table_name));
ALTER TABLE license_module_tables ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON license_module_tables FROM PUBLIC, anon, authenticated;
INSERT INTO license_module_tables(module, table_name) VALUES
 ('budgets','budgets'),
 ('manufacturing','boms'),('manufacturing','bom_items'),('manufacturing','work_orders'),
 ('shareholders','shareholders'),('shareholders','shareholder_movements'),
 ('shareholders','shareholder_profit_runs'),('shareholders','shareholder_change_requests'),
 ('hr','employees'),('hr','payroll'),('hr','attendance'),('hr','shifts'),
 ('hr','leave_types'),('hr','leave_requests'),('hr','holidays'),('hr','employee_adjustments'),
 ('pos','pos_sessions'),('pos','pos_session_sales'),
 ('assets','fixed_assets'),('assets','asset_categories'),('assets','asset_depreciations'),
 ('projects','projects'),('projects','service_tickets'),
 ('cheques','cheques'),
 ('tax','tax_documents'),('tax','integration_connections'),('tax','integration_events'),
 ('bank_recon','bank_statements'),('bank_recon','bank_statement_lines'),
 ('traceability','inventory_lots'),('traceability','inventory_serials')
ON CONFLICT DO NOTHING;

-- 3) دوال مساعدة
CREATE OR REPLACE FUNCTION license_is_dev() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND active AND role='developer') $$;

CREATE OR REPLACE FUNCTION license_has_module(p_module text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT l.modules IS NULL OR p_module = ANY(l.modules) FROM license l WHERE l.id=1 $$;

-- 4) حالة الترخيص للواجهة (للمستخدم المسجّل): الخطة، الحدود، الاستخدام الحالي
CREATE OR REPLACE FUNCTION license_state() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE l license%ROWTYPE; used_users int; used_br int; used_wh int; db_mb numeric; st_mb numeric := NULL;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'يجب تسجيل الدخول'; END IF;
  SELECT * INTO l FROM license WHERE id=1;
  SELECT count(*) INTO used_users FROM profiles WHERE active AND role<>'developer';
  SELECT count(*) INTO used_br FROM branches WHERE active;
  SELECT count(*) INTO used_wh FROM warehouses WHERE COALESCE(active,true);
  db_mb := round(pg_database_size(current_database())/1048576.0, 1);
  BEGIN
    EXECUTE 'SELECT round(COALESCE(sum((metadata->>''size'')::bigint),0)/1048576.0,1) FROM storage.objects' INTO st_mb;
  EXCEPTION WHEN OTHERS THEN st_mb := NULL; END;
  RETURN jsonb_build_object(
    'plan_code', l.plan_code, 'plan_name', l.plan_name, 'status', l.status,
    'expires_at', l.expires_at, 'grace_until', l.grace_until, 'message', l.message,
    'limits', jsonb_build_object('users', l.max_users, 'branches', l.max_branches, 'warehouses', l.max_warehouses),
    'used', jsonb_build_object('users', used_users, 'branches', used_br, 'warehouses', used_wh),
    'over_limit', (l.max_users IS NOT NULL AND used_users > l.max_users)
               OR (l.max_branches IS NOT NULL AND used_br > l.max_branches)
               OR (l.max_warehouses IS NOT NULL AND used_wh > l.max_warehouses),
    'modules', to_jsonb(l.modules),
    'db_mb', db_mb, 'storage_mb', st_mb,
    'storage_warn', (l.storage_mb_warn IS NOT NULL AND (db_mb + COALESCE(st_mb,0)) > l.storage_mb_warn),
    'schema_version', l.schema_version, 'synced_at', l.synced_at);
END $$;
REVOKE ALL ON FUNCTION license_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION license_state() TO authenticated;

-- 5) تطبيق أمر من اللوحة. للـservice_role بس (بتناديها دالة license-sync بعد التحقق من التوقيع)
CREATE OR REPLACE FUNCTION license_apply(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE l license%ROWTYPE; v_seq bigint; v_status text; v_mods text[];
BEGIN
  SELECT * INTO l FROM license WHERE id=1 FOR UPDATE;
  v_seq := (p->>'seq')::bigint;
  IF v_seq IS NULL OR v_seq <= l.seq THEN
    RAISE EXCEPTION 'أمر قديم أو مكرر (seq=%، الحالي=%)', v_seq, l.seq;
  END IF;
  v_status := COALESCE(p->>'status','active');
  IF v_status NOT IN('active','grace','readonly','suspended') THEN RAISE EXCEPTION 'حالة غير معروفة'; END IF;
  IF p ? 'modules' AND jsonb_typeof(p->'modules')='array' THEN
    SELECT array_agg(x) INTO v_mods FROM jsonb_array_elements_text(p->'modules') x;
    v_mods := COALESCE(v_mods,'{}');
  ELSE v_mods := NULL; END IF;

  UPDATE license SET
    client_id=COALESCE(p->>'client_id',client_id),
    plan_code=COALESCE(p->>'plan_code',plan_code),
    plan_name=p->>'plan_name',
    max_users=(p->>'max_users')::int,
    max_branches=(p->>'max_branches')::int,
    max_warehouses=(p->>'max_warehouses')::int,
    modules=v_mods,
    storage_mb_warn=(p->>'storage_mb_warn')::int,
    status=v_status,
    expires_at=(p->>'expires_at')::timestamptz,
    grace_until=(p->>'grace_until')::timestamptz,
    message=COALESCE(p->>'message',''),
    seq=v_seq, synced_at=now(), updated_at=now()
  WHERE id=1;

  -- الإيقاف الكامل بيستخدم قفل الموقع الموجود أصلًا (شاشة القفل + قفل الـRLS + خروج الجلسات)
  IF v_status='suspended' THEN
    UPDATE app_control SET locked=true,
      lock_msg=COALESCE(NULLIF(p->>'message',''),'الاشتراك متوقف. تواصل مع الدعم.'),
      lock_roles='{}', lock_until=NULL, sessions_after=now(), updated_at=now() WHERE id=1;
    UPDATE license SET license_locked=true WHERE id=1;
  ELSIF l.license_locked THEN
    UPDATE app_control SET locked=false, lock_msg='', lock_roles='{}', lock_until=NULL, updated_at=now() WHERE id=1;
    UPDATE license SET license_locked=false WHERE id=1;
  END IF;

  PERFORM log_event('update','license',v_seq::text,
    'تحديث الترخيص من لوحة التحكم: '||COALESCE(p->>'plan_code','')||' / '||v_status);
  RETURN jsonb_build_object('ok',true,'seq',v_seq,'status',v_status);
END $$;
REVOKE ALL ON FUNCTION license_apply(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION license_apply(jsonb) TO service_role;

-- 6) تسجيل نسخة قاعدة البيانات (من أداة التحديثات، بالـservice_role)
CREATE OR REPLACE FUNCTION license_set_schema_version(v text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$ UPDATE license SET schema_version=v WHERE id=1 $$;
REVOKE ALL ON FUNCTION license_set_schema_version(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION license_set_schema_version(text) TO service_role;

-- 7) حد المستخدمين (حساب المطوّر مش بيتحسب)
CREATE OR REPLACE FUNCTION trg_lic_users() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE mx int; n int;
BEGIN
  IF NEW.role='developer' OR NOT NEW.active THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.active AND OLD.role<>'developer' THEN RETURN NEW; END IF; -- محسوب أصلًا
  SELECT max_users INTO mx FROM license WHERE id=1;
  IF mx IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('lic_users'));
  SELECT count(*) INTO n FROM profiles WHERE active AND role<>'developer' AND id<>NEW.id;
  IF n >= mx THEN
    RAISE EXCEPTION 'وصلت للحد الأقصى للمستخدمين في خطتك (%). للزيادة تواصل مع الدعم.', mx;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS lic_users ON profiles;
CREATE TRIGGER lic_users BEFORE INSERT OR UPDATE OF active, role ON profiles
  FOR EACH ROW EXECUTE FUNCTION trg_lic_users();

-- 8) حد الفروع والمخازن
CREATE OR REPLACE FUNCTION trg_lic_branches() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE mx int; n int;
BEGIN
  IF NOT COALESCE(NEW.active,true) THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND COALESCE(OLD.active,true) THEN RETURN NEW; END IF;
  SELECT max_branches INTO mx FROM license WHERE id=1;
  IF mx IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('lic_branches'));
  SELECT count(*) INTO n FROM branches WHERE active AND id<>NEW.id;
  IF n >= mx THEN RAISE EXCEPTION 'وصلت للحد الأقصى للفروع في خطتك (%). للزيادة تواصل مع الدعم.', mx; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS lic_branches ON branches;
CREATE TRIGGER lic_branches BEFORE INSERT OR UPDATE OF active ON branches
  FOR EACH ROW EXECUTE FUNCTION trg_lic_branches();

CREATE OR REPLACE FUNCTION trg_lic_warehouses() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE mx int; n int;
BEGIN
  IF NOT COALESCE(NEW.active,true) THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND COALESCE(OLD.active,true) THEN RETURN NEW; END IF;
  SELECT max_warehouses INTO mx FROM license WHERE id=1;
  IF mx IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('lic_warehouses'));
  SELECT count(*) INTO n FROM warehouses WHERE COALESCE(active,true) AND id<>NEW.id;
  IF n >= mx THEN RAISE EXCEPTION 'وصلت للحد الأقصى للمخازن في خطتك (%). للزيادة تواصل مع الدعم.', mx; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS lic_warehouses ON warehouses;
CREATE TRIGGER lic_warehouses BEFORE INSERT OR UPDATE OF active ON warehouses
  FOR EACH ROW EXECUTE FUNCTION trg_lic_warehouses();

-- 9) منع الإضافة في الوحدات اللي مش في الخطة (القراءة تفضل شغالة)
CREATE OR REPLACE FUNCTION trg_lic_module() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL OR license_is_dev() THEN RETURN NEW; END IF;
  IF NOT license_has_module(TG_ARGV[0]) THEN
    RAISE EXCEPTION 'وحدة "%" غير مفعّلة في خطتك. للترقية تواصل مع الدعم.', TG_ARGV[0];
  END IF;
  RETURN NEW;
END $$;

-- 10) وضع القراءة فقط: يمنع أي كتابة من المستخدمين (RPC أو مباشر) لو الحالة readonly أو suspended
CREATE OR REPLACE FUNCTION trg_lic_readonly() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN COALESCE(NEW,OLD); END IF;   -- عمليات النظام والـservice_role
  SELECT status INTO s FROM license WHERE id=1;
  IF s IN('readonly','suspended') AND NOT license_is_dev() THEN
    RAISE EXCEPTION 'الاشتراك منتهي: النظام في وضع القراءة فقط. تواصل مع الدعم للتجديد.';
  END IF;
  RETURN COALESCE(NEW,OLD);
END $$;

DO $$ DECLARE r record; skip text[] := ARRAY['audit_logs','notifications','trusted_devices','user_quick_actions',
    'app_control','license','license_module_tables','profiles','user_permissions'];
BEGIN
  FOR r IN SELECT tablename t FROM pg_tables WHERE schemaname='public' AND NOT (tablename = ANY(skip)) LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS lic_readonly ON %I', r.t);
    EXECUTE format('CREATE TRIGGER lic_readonly BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION trg_lic_readonly()', r.t);
  END LOOP;
  FOR r IN SELECT module m, table_name t FROM license_module_tables WHERE to_regclass('public.'||table_name) IS NOT NULL LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS lic_module ON %I', r.t);
    EXECUTE format('CREATE TRIGGER lic_module BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION trg_lic_module(%L)', r.t, r.m);
  END LOOP;
END $$;

COMMIT;
