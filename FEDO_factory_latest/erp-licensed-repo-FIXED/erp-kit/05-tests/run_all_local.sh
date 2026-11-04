#!/usr/bin/env bash
# =============================================================================
# run_all_local.sh — تشغيل كل اختبارات FEDO Factory على قاعدة محلية فارغة
#
#   LOCAL / DISPOSABLE DATABASE ONLY. Never point this at a customer project.
#
# الاستخدام:
#   ./run_all_local.sh                    # ينشئ قاعدة fedo_factory_test
#   DB=my_test ./run_all_local.sh         # قاعدة أخرى
#   ./run_all_local.sh --keep             # لا يحذف القاعدة بعد التشغيل
#
# المتطلبات: psql + PostgreSQL >= 14 (يُنصح 16/17) + صلاحية إنشاء قواعد.
# السكربت يستخدم متغيرات PG* القياسية (PGHOST/PGPORT/PGUSER).
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(cd "$HERE/.." && pwd)"
DB="${DB:-fedo_factory_test}"
KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   PASS\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31m   FAIL\033[0m  %s\n' "$*"; exit 1; }

command -v psql >/dev/null || die "psql غير موجود في PATH"
[[ "$DB" == "postgres" || "$DB" == "template1" ]] && die "اسم قاعدة غير مسموح: $DB"

log "إعادة إنشاء قاعدة الاختبار: $DB"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true
createdb "$DB" || die "تعذر إنشاء قاعدة $DB"

run_sql() { # $1=file $2=label
  local f="$1" label="${2:-$(basename "$1")}"
  if out=$(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1); then
    ok "$label"
  else
    printf '%s\n' "$out" | tail -25
    die "$label"
  fi
}
run_quiet() { # migrations: errors matter, notices do not
  local f="$1" label
  label="$(basename "$1")"
  if out=$(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1); then
    ok "migration $label"
  else
    printf '%s\n' "$out" | grep -v NOTICE | tail -25
    die "migration $label"
  fi
}

log "1) shim + قاعدة FEDO الأساسية"
run_quiet "$KIT/07-local-test/supabase_shim.sql"
run_quiet "$KIT/01-database/ERP_BASE_CURRENT.sql"

log "2) تخصيص المصنع v1 → v5 (كل ملف مرتين لإثبات idempotency)"
for f in ERP_FACTORY_CUSTOMIZE_v1 ERP_FACTORY_FIX_MANUAL_JOURNAL_v2 \
         ERP_FACTORY_SMOKE_RETURN_TAX_v3 ERP_FACTORY_ROLL_LEDGER_v4 ERP_FACTORY_ROLL_LEDGER_v5; do
  run_quiet "$KIT/01-database/$f.sql"
  run_quiet "$KIT/01-database/$f.sql"
done

log "3) lockdown"
run_quiet "$KIT/01-database/99_final_lockdown.sql"

log "4) اختبارات SQL (كلها تتراجع عن بياناتها)"
run_sql "$HERE/factory_manual_journal_fix_test.sql"
run_sql "$HERE/factory_tax_return_test.sql"
run_sql "$HERE/factory_foundation.sql"
run_sql "$HERE/factory_legacy_flows.sql"
run_sql "$HERE/factory_roll_ledger_test.sql"
run_sql "$HERE/factory_roll_ledger_v5_test.sql"
run_sql "$HERE/factory_legacy_smoke.sql"

log "5) فحص الأمان النهائي"
sec=$(psql -X -At -d "$DB" -c "SELECT (SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='public' AND grantee='anon')||'|'||(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND has_function_privilege('anon',p.oid,'EXECUTE') AND p.proname NOT IN ('app_version','app_lock_state'))||'|'||(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity)")
[[ "$sec" == "0|0|0" ]] && ok "lockdown 0/0/0" || die "lockdown counters: $sec"

log "6) اختبار التزامن (جلستان على نفس الرول) — قاعدة منفصلة تُحذف بعدها"
RACE_DB="fedo_roll_v5_race"
if command -v python3 >/dev/null; then
  dropdb --if-exists "$RACE_DB" >/dev/null 2>&1 || true
  if createdb "$RACE_DB" 2>/dev/null; then
    for f in 07-local-test/supabase_shim.sql 01-database/ERP_BASE_CURRENT.sql \
             01-database/ERP_FACTORY_CUSTOMIZE_v1.sql 01-database/ERP_FACTORY_FIX_MANUAL_JOURNAL_v2.sql \
             01-database/ERP_FACTORY_SMOKE_RETURN_TAX_v3.sql 01-database/ERP_FACTORY_ROLL_LEDGER_v4.sql \
             01-database/ERP_FACTORY_ROLL_LEDGER_v5.sql 01-database/99_final_lockdown.sql; do
      psql -X -q -v ON_ERROR_STOP=1 -d "$RACE_DB" -f "$KIT/$f" >/dev/null 2>&1 || die "race db load $f"
    done
    if out=$(python3 "$HERE/factory_roll_v5_race_test.py" 2>&1); then ok "$out"; else printf '%s\n' "$out"; die "race test"; fi
    dropdb --if-exists "$RACE_DB"
  else
    printf '   SKIP  لا يمكن إنشاء قاعدة %s\n' "$RACE_DB"
  fi
else
  printf '   SKIP  python3 غير موجود\n'
fi

log "7) صحة JS + اختبار الواجهة (jsdom)"
if [[ -d "$HERE/node_modules/jsdom" ]] || node -e "require.resolve('jsdom')" >/dev/null 2>&1; then
  if out=$(cd "$HERE" && node factory_ui_smoke_test.js 2>&1); then
    ok "$(printf '%s\n' "$out" | tail -1)"
  else
    printf '%s\n' "$out" | tail -20; die "ui smoke"
  fi
else
  printf '   SKIP  jsdom غير مثبت: cd 05-tests && npm install\n'
fi

for js in 03-frontend/app.js 03-frontend/sw.js; do
  node --check "$KIT/$js" && ok "node --check $js"
done

if [[ $KEEP -eq 0 ]]; then
  log "تنظيف"; dropdb --if-exists "$DB" && ok "تم حذف قاعدة الاختبار"
else
  log "القاعدة محفوظة: $DB"
fi
printf '\n\033[1;32mALL LOCAL CHECKS PASSED\033[0m\n'
