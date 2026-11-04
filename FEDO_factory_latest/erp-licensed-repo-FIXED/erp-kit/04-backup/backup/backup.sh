#!/usr/bin/env bash
# نسخة كاملة للداتابيز + ملفات الـ Storage، مشفرة AES-256، وبترفع على Google Drive مع الاحتفاظ بآخر N نسخ.
set -euo pipefail

# فحص الـ secrets قبل أي حاجة: لو فاضية، نوقف برسالة واضحة بدل ما pg_dump يحاول يتصل بالـ socket المحلي
for v in SUPABASE_DB_URL SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY BACKUP_PASSPHRASE GDRIVE_FOLDER_ID GDRIVE_SERVICE_ACCOUNT_JSON; do
  if [ -z "${!v:-}" ]; then
    echo "خطأ: الـ secret ده فاضي أو مش موجود في الريبو ده: $v" >&2
    echo "اتأكد إنه متسجل في Settings > Secrets and variables > Actions في نفس الريبو اللي فيه الـ workflow." >&2
    exit 1
  fi
done

# نفس نسخة السيرفر (17)؛ Ubuntu بيحط نسخة 16 افتراضياً في /usr/bin
PG17_BIN=/usr/lib/postgresql/17/bin
if [ -x "$PG17_BIN/pg_dump" ]; then
  export PATH="$PG17_BIN:$PATH"
fi
echo "pg_dump: $(pg_dump --version)"

TS=$(date -u +%Y%m%d-%H%M)
WORK=$(mktemp -d)
OUT_DIR="$WORK/bundle"
mkdir -p "$OUT_DIR/storage"

echo "1) dump الـ public schema (هيكل + بيانات + دوال + triggers + policies)"
pg_dump "$SUPABASE_DB_URL" --format=custom --no-owner --no-privileges --schema=public -f "$OUT_DIR/public.dump"

echo "2) بيانات حسابات الدخول (auth.users + identities)"
pg_dump "$SUPABASE_DB_URL" --data-only --no-owner --table=auth.users --table=auth.identities -f "$OUT_DIR/auth-users.sql"

echo "3) تحميل ملفات الـ Storage"
python3 backup/storage_tool.py download "$OUT_DIR/storage"

echo "4) ضغط + تشفير"
tar -C "$OUT_DIR" -czf "$WORK/bundle.tgz" .
ARCHIVE="$WORK/erp-backup-$TS.tar.gz.enc"
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE -in "$WORK/bundle.tgz" -out "$ARCHIVE"
ls -lh "$ARCHIVE"

echo "5) رفع على Google Drive + الاحتفاظ بآخر $KEEP_BACKUPS نسخ"
python3 backup/drive_tool.py upload "$ARCHIVE" "erp-backup-$TS.tar.gz.enc"
python3 backup/drive_tool.py keep "${KEEP_BACKUPS:-3}"

rm -rf "$WORK"
echo "تمت النسخة بنجاح"
