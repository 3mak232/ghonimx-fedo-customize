# Handoff كامل للـ AI الآخر — ERP المرخص — آخر تحديث 18-10-2026 20:00 UTC

> انسخ هذا الملف كاملاً وأرسله للـ AI الآخر. لا تحذف أي قسم.

---

## 0) المسارات والملفات

- الأصلي: `C:\Users\master laptop\Desktop\New folder\erp-licensed-repo.zip` (524KB)
- المُصلح الجاهز: `C:\Users\master laptop\Desktop\New folder\erp-licensed-repo-FIXED\` (مجلد)
- المضغوط النهائي بعد كل الإصلاحات: `C:\Users\master laptop\Desktop\New folder\erp-licensed-repo-FIXED.zip` ( ~1060KB)
- دليل تفاعلي تشيك ليست: `erp-licensed-repo-FIXED\دليل-انشاء-عميل-جديد.html` (افتحه دبل كليك)
- أدلة نصية: `SETUP.md` + `CHECKLIST.md` + `FIXED-README.md` + `HANDOFF-FOR-AI.md` (هذا الملف)
- أداة توليد مفاتيح بدون Node: `control-plane\03-tools\gen_keys.html` (دبل كليك) + `gen_keys.mjs` (Node)
- أنا Claude Fable 5.1 الذي طورته Anthropic.

---

## 1) وصف المشروع

- `erp-kit/`: ERP كامل (واجهة comptest4 `app.js` 432KB + قاعدة واحدة `ERP_BASE_CURRENT.sql` 492KB / 101 جدول + Edge Functions `login-with-identifier`, `admin-create-user`, `full-backup`, `full-restore` + نسخ احتياطي مشفر + `LICENSE_MODULE.sql`)
- `control-plane/`: لوحة تحكم مركزية لمشروع Supabase منفصل تتحكم بتراخيص كل العملاء بتوقيع Ed25519 (جدول `license` + triggers تمنع تجاوز الحدود + `push-license` يوقّع و `license-sync` يتحقق).

---

## 2) المشاريع الحالية عند المستخدم

### لوحة مركزية (panel)
- ref: `wqfbabtbqyioqumqjerc`
- URL: `https://wqfbabtbqyioqumqjerc.supabase.co`
- publishable key (anon): `sb_publishable_AkDpNpPkvq0nPEiYeGGRGA_PR2M8t-G` (لـ `04-dashboard/index.html`)
- Secret key (sb_secret_... = ADMIN_SECRET_KEY للوحة): موجود في `Project Settings > API Keys > Secret key > Reveal` (يبدأ `sb_secret_`، سابقاً `service_role`). لا يُوضع في html.
- حالة: `central_schema.sql` اشتغل بنجاح، يوزر `malik` (UUID `96195d2f-11ec-4990-8210-625fa10822da`) أنشئ وتم `Confirm email` وتم `INSERT INTO panel_staff` بنجاح بعد إصلاح خطأ uuid، دخول اللوحة يعمل + MFA.

### عميل جديد (client)
- ref: `rljzchqywvdfkfxuvjag`
- URL: `https://rljzchqywvdfkfxuvjag.supabase.co`
- publishable key (للعميل): `sb_publishable_NA_NCMyfDhXXBwmu3FAvlg_n4qrrayZ` **(كما أرسله المستخدم — قد يكون مقصوص، يجب مقارنته بالقيمة الكاملة من API Keys)**
- Secret key (ADMIN_SECRET_KEY للعميل): في نفس صفحة API Keys للعميل (مختلف عن اللوحة).
- حالة: `ERP_BASE_CURRENT.sql` ثم `LICENSE_MODULE.sql` تم تشغيلهما في SQL Editor بنجاح. Edge Functions للعميل قيد الإنشاء. رابط `license-sync` للعميل: `https://rljzchqywvdfkfxuvjag.supabase.co/functions/v1/license-sync`
- تم إنشاء سجل العميل في اللوحة: لوحة > العملاء > + عميل > license_endpoint = الرابط أعلاه. CLIENT_ID تولد تلقائياً بعد الحفظ (UUID).

---

## 3) كل الإصلاحات التي تمت في النسخة FIXED

1. `erp-kit/03-frontend/app.js` السطر 1: كان `https://qzvnuyapnkkhxdlocpms.supabase.co` التجريبي → استُبدل أولاً بـ `__SUPABASE_URL__/__SUPABASE_ANON_KEY__` ثم ثبت أخيراً على `https://rljzchqywvdfkfxuvjag.supabase.co` + `sb_publishable_NA_NCMyfDhXXBwmu3FAvlg_n4qrrayZ` (مع تعليق FIXED).
2. `erp-kit/03-frontend/index.html`: `preconnect` كان `qzvnuy` → الآن `https://rljzchqywvdfkfxuvjag.supabase.co`.
3. `sw.js`: `CACHE fedo-test-shell-v7` → `v8` لكسر كاش Cloudflare.
4. `app.js`: `APP_VERSION FEDO-TEST-4` → `FEDO-TEST-5` + سطر تشخيص `console.log('ERP FIXED - URL_ =', URL_)` و `console.log('KEY prefix'...)` (لحذفه بعد التحقق).
5. `control-plane/04-dashboard/index.html`: مضبوط على `wqfbabtbqyioqumqjerc` و `sb_publishable_AkDp...` (كان سليم).
6. إضافة `gen_keys.html` لتوليد Ed25519 من المتصفح بدون PowerShell.
7. إضافة `SETUP.md`, `CHECKLIST.md`, `FIXED-README.md`, `config.example.js`, `دليل-انشاء-عميل-جديد.html`, وهذا الملف.

لم يُمس منطق التوقيع/التحقق Ed25519 ولا SQL الترخيص — سليم.

---

## 4) سجل الأخطاء التي ظهرت وحلولها

- `Failed to run sql query: syntax error at or near "//" LINE 1: // بيولّد` → المستخدم شغّل `gen_keys.mjs` في SQL Editor. الحل: شغّله في المتصفح عبر `gen_keys.html` دبل كليك أو `node gen_keys.mjs` في PowerShell، وليس SQL.
- `22P02 invalid input syntax for type uuid: " 96195d2f-... > Users "` → نسخ UUID مع نص `> Users` ومسافة. الحل: `INSERT INTO panel_staff(user_id,name,role) VALUES('96195d2f-11ec-4990-8210-625fa10822da','malik','owner');` بدون مسافات.
- `بيانات الدخول غير صحيحة` رغم صحتها (لوحة) → سببه `email_confirmed_at = NULL` (Add user بدون Confirm). الحل: `Authentication > Users > Confirm email`.
- `بيانات الدخول غير صحيحة` رغم صحتها (عميل) → نفس السبب + `profiles.active=false` + `index.html/app.js` مربوط بمشروع خطأ.
- كلاود يطلب `qzvnuy...` رغم محلي `rljzch...` → رفع مجلد قديم قبل التعديل. الحل: إعادة رفع محتوى `FIXED/03-frontend` كما هو + `Ctrl+Shift+R` + `Clear site data`.

---

## 5) الحالة الحالية (18-10-2026 19:28 بعد آخر رفع)

- `F12 > Console` يطبع: `ERP FIXED - URL_ = https://rljzchqywvdfkfxuvjag.supabase.co` ✅ الرابط تغيّر بنجاح على كلاود.
- لكن يظهر: `GET https://rljzchqywvdfkfxuvjag.supabase.co/rest/v1/company_settings?select=* 401 (Unauthorized)` ❌
- التشخيص: الرابط صحيح لكن المفتاح مرفوض. الأكثر احتمالاً:
  1. `KEY` مقصوص/ناقص (المُرسل `sb_publishable_NA_NCMyfDhXXBwmu3FAvlg_n4qrrayZ` طوله 26 بعد البادئة، عادة أطول).
  2. وضع `sb_secret_` مكان `sb_publishable_` في `app.js`.
  3. `Publishable key` تم تدويره أو المشروع Paused.
  4. كاش سووركر قديم.
- المطلوب: مقارنة `KEY` في `app.js` حرفياً مع `Project Settings > API Keys > Publishable key` للعميل `rljzchq...`، ونسخ القيمة الكاملة بدون قص.

---

## 6) خطوات التشغيل الكاملة (بدون PowerShell قدر الإمكان — للمبتدئ)

### اللوحة (مرة واحدة — تمت)
1. SQL Editor في wqfbabtbqyioqumqjerc → شغّل `control-plane/01-central/central_schema.sql`
2. `gen_keys.html` دبل كليك → توليد → احفظ PRIVATE (لوحة فقط) و PUBLIC (لكل العملاء)
3. Authentication > Add user → Confirm email → SQL: `INSERT INTO panel_staff ... owner`
4. Edge Functions > Create function `push-license` (Verify JWT مفعل) → الصق `control-plane/01-central/push-license/index.ts` → Deploy → Secrets: `LICENSE_PRIVATE_KEY` (الطويل) + `ADMIN_SECRET_KEY` (sb_secret للوحة)
5. عدّل `04-dashboard/index.html` (URL + publishable للوحة) → ارفع على Cloudflare Pages

### كل عميل جديد (كررها)
1. أنشئ مشروع جديد للعميل → SQL Editor → شغّل `ERP_BASE_CURRENT.sql` ثم `LICENSE_MODULE.sql`
2. Edge Functions > Create function (انسخ index.ts):
   - `login-with-identifier` (Verify OFF) ← `erp-kit/02-edge-functions/login-with-identifier/index.ts`
   - `admin-create-user` (ON) ← `.../admin-create-user/index.ts`
   - `full-backup` (ON) ← `.../full-backup/index.ts` (قد يحتاج `_shared/fullbak-core.mjs` + `fullbak-env.ts`)
   - `full-restore` (ON) ← `.../full-restore/index.ts`
   - `license-sync` (OFF) ← `control-plane/02-client/license-sync/index.ts`
3. Secrets لـ `license-sync`: `LICENSE_PUBLIC_KEY` (القصير) + `CLIENT_ID` (من لوحة > العملاء > انسخ ID) + `ADMIN_SECRET_KEY` (sb_secret للعميل نفسه)
4. عدّل `erp-kit/03-frontend/app.js` السطر 1 و `index.html` preconnect برابط + publishable العميل → APP_VERSION v5 / sw v8 → ارفع محتوى مجلد `03-frontend` فقط على Cloudflare Pages → Authentication > URL Configuration > Site URL = رابط pages.dev
5. أول يوزر: سجّل من واجهة العميل (يصبح admin تلقائياً) → اقفل Disable sign-ups. باقي اليوزرز من داخل النظام > المستخدمين > + مستخدم (admin-create-user).
6. لوحة wqfbab... > العملاء > + عميل (الاسم + license_endpoint = https://REF-العميل.supabase.co/functions/v1/license-sync) → حفظ → افتحه → انسخ CLIENT_ID → ضعه في license-sync Secrets → الاشتراك → إرسال الترخيص → فحص (يجب مطابق).
7. اختبار: `07-local-test/ERP_rls_audit_READ_ONLY.sql` = 5 أصفار، جرب حدود مستخدمين/وحدات، جرب إيقاف suspended.

---

## 7) تشخيص 401 الحالي — اطلبه من المستخدم قبل أي تعديل

1. في مشروع العميل `rljzch...` افتح `Project Settings > API Keys > Publishable key > Copy` → قارنها حرفياً بـ `app.js` السطر 1. هل هي `sb_publishable_NA_NCMyfDhXXBwmu3FAvlg_n4qrrayZ` بالظبط؟ انسخها كاملة هنا.
2. على موقع كلاود `F12 > Network > company_settings > Headers > Response` انسخ الـ JSON.
3. `F12 > Console` اكتب `KEY.slice(0,30)` و `KEY.length` وانسخ النتيجة.
4. `F12 > Console` هل يطبع `ERP FIXED - URL_ = ... rljzch...` ؟

لو Response = `{"code":...,"message":"Invalid API key"}` → المفتاح خطأ/مقصوص.
لو `No API key found` → `KEY` فارغ.
لو `JWT expired` → نادر.

---

## 8) ما يجب أن يفعله الـ AI الآخر فور استلام هذا الملف

1. اطلب من المستخدم القيم الثلاث أعلاه (المفتاح الكامل + Response + Console).
2. صحح `app.js` إذا كان مقصوص، وأعد تغليف `erp-licensed-repo-FIXED.zip`.
3. ذكّره برفع محتوى `03-frontend` فقط + `Ctrl+Shift+R` + `Clear site data/Unregister SW`.
4. تأكد `Site URL` في العميل مضبوط.
5. بعد حل 401، أكمل اختبار `Confirm email` + `profiles.active=true` لأن إنشاء يوزر من `Dashboard > Add user` يتركه غير مفعّل.
6. لا تطلب `sb_secret_` في الشات ولا تضعه في html.

---

## 9) ملاحظات إضافية

- `ADMIN_SECRET_KEY` ليس اسم Supabase بل اسم متغير في الكود (`Deno.env.get("ADMIN_SECRET_KEY")`). قيمته هي `Secret key` (sb_secret) من `API Keys`.
- `gen_keys.html` يولد `PKCS8` للخاص و `SPKI raw 32` للعام — متوافق مع `importKey pkcs8/raw Ed25519` في الدالتين.
- الملفات في `03-frontend` الأصلي كانت تحمل `qzvnuyapnkkhxdlocpms` كتعليق تحذيري في `README-START-HERE.md`.
- لا تحذف `LICENSE_MODULE.sql` — منفصل عمداً عن `ERP_BASE_CURRENT.sql` لتشغيله بعد الأساس.

=== انتهى Handoff ===
