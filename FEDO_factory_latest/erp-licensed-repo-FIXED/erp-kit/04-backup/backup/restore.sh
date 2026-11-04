#!/usr/bin/env bash
# استعادة نسخة كاملة على داتابيز جديدة (مشروع Supabase جديد أو Postgres تجريبي).
# usage: bash backup/restore.sh <erp-backup-XXXX.tar.gz.enc> "<TARGET_DB_URL>"
# Env: BACKUP_PASSPHRASE (نفس الباسورد اللي اتعمل بيه النسخة)، و SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (لو عايز ترفع ملفات الـ Storage)
set -euo pipefail

ARCHIVE="$1"
TARGET="$2"
WORK=$(mktemp -d)

echo "1) فك التشفير"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE -in "$ARCHIVE" -out "$WORK/bundle.tgz"
tar -C "$WORK" -xzf "$WORK/bundle.tgz"

echo "2) حسابات الدخول (لازم تتحمل قبل الـ public)"
psql "$TARGET" -v ON_ERROR_STOP=1 -q -f "$WORK/auth-users.sql"

echo "3) هيكل الداتابيز والبيانات والدوال"
pg_restore --no-owner --no-privileges --exit-on-error -n public -d "$TARGET" "$WORK/public.dump"

if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  echo "4) رفع ملفات الـ Storage"
  python3 backup/storage_tool.py upload "$WORK/storage"
fi

rm -rf "$WORK"
echo "تمت الاستعادة. اختبر الدخول وعدد الفواتير والأصناف."
