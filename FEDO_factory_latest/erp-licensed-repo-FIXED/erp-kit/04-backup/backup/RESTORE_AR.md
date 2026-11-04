# دليل النسخ الاحتياطي والاستعادة

## النسخة بتحتوي إيه؟
1. **هيكل الداتابيز كامل** (كل الجداول والأعمدة والـ views والـ triggers والـ policies والدوال)، ومعاه كل البيانات.
2. **حسابات الدخول** (auth.users + identities)، يعني الإيميلات وكلمات السر المشفرة. الاستعادة بتحافظ على كلمات السر، فالمستخدمين يدخلوا بنفس الباسورد.
3. **ملفات الـ Storage** (لوجو الشركة وأي ملفات مرفوعة)، مع قائمة (manifest) بيها.
4. **الملف كله مشفر** بـ AES-256، بباسورد اسمه `BACKUP_PASSPHRASE`. من غير الباسورد الملف مش هيتفتح أبداً.

## النسخة بتتعمل إمتى؟
- كل يوم الساعة 23:00 UTC (1 أو 2 الفجر بتوقيت القاهرة) من GitHub Actions.
- تقدر تشغلها يدوي من تبويب **Actions** ← **ERP full backup** ← **Run workflow**.
- بتحتفظ بآخر **3 نسخ** على Google Drive، وكل يوم بتتحذف الأقدم.

## الإعداد لأول مرة (مرة واحدة)

### أ) مفتاح Google Drive
1. ادخل **console.cloud.google.com**، واعمل مشروع جديد.
2. من **APIs & Services ← Library** فعّل **Google Drive API**.
3. من **IAM & Admin ← Service Accounts** اعمل Service Account جديد، وبعدين من تبويب **Keys** اعمل Key بصيغة **JSON** وحمّله.
4. في Google Drive اعمل فولدر اسمه `erp-backups`، واعمل Share له مع البريد اللي في خانة `client_email` في الملف (بصلاحية **Editor**).
5. افتح الفولدر وانسخ الـ ID من الرابط (الجزء بعد `/folders/`).

### ب) الداتابيز
من Supabase: **Project Settings ← Database ← Connection string**، واختار **Session pooler** (وقلل الـ port لـ 5432 لو لزم). انسخ الرابط وحط الباسورد مكان `[YOUR-PASSWORD]`.

### ج) الـ Secrets في GitHub
ادخل الريبو على GitHub ← **Settings ← Secrets and variables ← Actions** ← **New repository secret**، وضيف:

| الاسم | القيمة |
|---|---|
| `SUPABASE_DB_URL` | رابط الداتابيز من الخطوة ب |
| `SUPABASE_URL` | `https://<PROJECT_REF>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | مفتاح service_role (**مش** publishable) |
| `BACKUP_PASSPHRASE` | باسورد طويل وعشوائي. **احفظه في مكان آمن برا الجهاز**، لو ضاع النسخ مش هتفتح |
| `GDRIVE_FOLDER_ID` | الـ ID بتاع فولدر Drive |
| `GDRIVE_SERVICE_ACCOUNT_JSON` | محتوى ملف الـ JSON كامل |

### د) تشغيل أول مرة
من تبويب **Actions** شغّل **Run workflow**، واستنى لحد ما تخلص. لو نجحت هتلاقي ملف `erp-backup-YYYYMMDD-HHMM.tar.gz.enc` في فولدر Drive.

---

## اختبار الاستعادة (مهم جداً تعمله قبل ما تعتمد على النسخ)

الاختبار ده بيكون **على مشروع Supabase جديد وفاضي** (الـ Free plan يكفي)، عشان متأثرش على الشغل الحقيقي.

### الخطوة 1: مشروع تجريبي
1. من Supabase اعمل **New project** جديد باسم `erp-restore-test`.
2. استنى لحد ما يخلص الإنشاء، وخد **Connection string** بتاعه (زي ب).

### الخطوة 2: جهاز فيه Postgres 17 وopenssl
- Windows: ثبّت WSL (Ubuntu) واشتغل منه.
- أو استخدم GitHub Codespaces.
- ثبّت الأدوات: `sudo apt install -y postgresql-client-17 openssl python3 python3-pip`
- حمّل الريبو وادخل فولدره.

### الخطوة 3: نزّل ملف النسخة
من Google Drive نزّل آخر ملف `erp-backup-....tar.gz.enc` على الجهاز.

### الخطوة 4: شغّل الاستعادة
```
export BACKUP_PASSPHRASE="الباسورد اللي حطيته"
export SUPABASE_URL="https://<PROJECT_REF_التجريبي>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="service_role بتاع المشروع التجريبي"
bash backup/restore.sh ./erp-backup-XXXX.tar.gz.enc "<رابط الداتابيز التجريبية>"
```
الخطوات اللي هتظهر: فك التشفير، ثم حسابات الدخول، ثم الداتا والدوال، ثم رفع الـ Storage.

### الخطوة 5: اتأكد إن كل حاجة رجعت
1. ادخل الموقع وعدّله يشتغل على المشروع التجريبي (غيّر `URL_` و`KEY` في `index.html` مؤقتاً)، أو اعمل المقارنة من SQL.
2. قارن الأعداد: عدد الفواتير والأصناف والعملاء والقيود في الداتابيز الأصلية والتجريبية (SQL Editor: `select count(*) from sales_invoices`).
3. سجّل دخول بحساب موجود، وتأكد إن كلمة السر شغالة.
4. شوف لوجو الشركة (ملفات الـ Storage).

### لو حصل خطأ
- `permission denied` أو `already exists`: معناها إن الـ public schema فيه بيانات قبل الاستعادة. اعمل المشروع التجريبي جديد وفاضي.
- `foreign key violation` على profiles: حسابات الدخول لازم تتحمل قبل الداتا، والـ script بيعمل ده بالترتيب.

---

## ملاحظات أمان
- الملف المشفر فيه كل داتا الشركة. الفولدر في Drive لازم يكون خاص بيك بس.
- الباسورد `BACKUP_PASSPHRASE` ما يتحطش في أي شات أو ملف في الريبو.
- Service Account عنده صلاحية على الفولدر المحدد بس، مش على كل Drive.
- لو اتسرب مفتاح الـ service role، غيّره فوراً من Supabase.
