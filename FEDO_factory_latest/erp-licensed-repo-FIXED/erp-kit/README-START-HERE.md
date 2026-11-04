# ERP Starter Kit v3 (comptest4 front end + ERP v1.99 backend)

استخدم الكيت ده تبني نظام جديد بقاعدة بيانات جديدة (شركة جديدة أو مشروع جديد) بنفس النظام وكل التحديثات الأخيرة.

## إضافة الترخيص (للبيع لعملاء كتير)
- `01-database/LICENSE_MODULE.sql`: يتشغّل **بعد** `ERP_BASE_CURRENT.sql` على نفس المشروع (ملف تاني مقصود، مش جزء من الأساس).
- `01-database/99_final_lockdown.sql`: **آخر ملف** يتشغّل بعد القاعدة والترخيص (وبعد أي تحديث SQL): بيقفل صلاحيات anon على الجداول والدوال. الفحص: `07-local-test/ERP_rls_check_combined_READ_ONLY.sql`، ومراجعة الدوال: `ERP_function_exposure_READ_ONLY.sql`.
- `02-edge-functions/license-sync`: انشره بـ`--no-verify-jwt` وحط Secrets: `LICENSE_PUBLIC_KEY` و`CLIENT_ID` و`ADMIN_SECRET_KEY`.
- لوحة التحكم نفسها في فولدر `control-plane` (بره الكيت). التفاصيل في `control-plane/README-AR.md`.
- لحد أول إرسال ترخيص من اللوحة العميل بيشتغل من غير حدود.

## الإصدار
- الواجهة: **comptest4** (`APP_VERSION = FEDO-TEST-4`، SW cache `fedo-test-shell-v7`)
  - وضع فاتح وداكن، ألوان نافي/تيل/كريمي، شريط جانبي، زر تبديل الوضع في الشريط العلوي وشاشة الدخول.
  - لوجو FEDO من `brand/` (رمز للشريط الجانبي، لوجو كامل بالكلمة في شاشة الدخول)، مع سطر "Powered by GHONIMX Technologies".
  - تخصيص الطباعة: الهيدر والمحاذاة، حجم الورقة والهوامش والخط، الملاحظات وخانات التوقيع، رصيد النظام أسفل الطباعة.
  - الأرقام: عربي في العامية، إنجليزي في الفصحى والإنجليزي.
  - الخمول: خروج تلقائي بعد ساعة.
- الباك إند: ERP v1.99 base (ملف SQL واحد).
- النسخ الاحتياطي: erp-backup (احتفاظ 30 نسخة، منع التشغيل المتزامن).

## محتويات الكيت
- `01-database/` ملف SQL واحد: `ERP_BASE_CURRENT.sql` (كل حاجة لحد آخر تحديث).
- `02-edge-functions/` الدوال الأربعة: `login-with-identifier`، `admin-create-user`، `full-backup`، `full-restore`، و`_shared`، و`onefile/` للنسخ المدموجة.
- `03-frontend/` الموقع الكامل (comptest4 من آخر commit).
- `04-backup/` النسخ الاحتياطي اليومي المشفّر على Google Drive (GitHub Actions) + `RESTORE_AR.md`.
- `05-tests/` سكريبت فحص Python وسيناريوهات الأعمال (شغّلها على مشروع تجريبي بس).
- `06-docs/` الملخص الكامل للتغييرات (`SUMMARY-COMPTEST4.md`) والـCHANGELOG وخطط الإصدارات.
- `07-local-test/` اختبار محلي على Postgres 16 مع محاكاة Supabase، وفحص RLS للقراءة فقط.

## الخطوات (حوالي ساعة)
1. اعمل مشروع Supabase **جديد**. مشروع منفصل للتجربة ومشروع منفصل للإنتاج.
2. Supabase > SQL Editor: شغّل **ملف واحد** على مشروع فاضي: `01-database/ERP_BASE_CURRENT.sql`. التفاصيل في `01-database/README-DB.md`.
3. Authentication > Providers: فعّل Email. قرر هل التسجيل العام مسموح. بعد أول أدمن اقفله.
4. Edge Functions: انشر كل مجلد من `02-edge-functions` بالاسم بالظبط: `login-with-identifier` (مع `--no-verify-jwt`)، `admin-create-user`، `full-backup`، `full-restore`. ضبط الـsecrets المطلوبة من أول الملف.
5. **الواجهة - غيّر الرابط والمفتاح في مكانين:**
   - `03-frontend/app.js` السطر الأول: `URL_` = رابط مشروعك الجديد، و`KEY` = المفتاح `publishable` (anon) بتاع المشروع الجديد.
   - `03-frontend/index.html`: غيّر الـ`preconnect` وCSP (`connect-src`) لنفس رابط المشروع الجديد. الرابط الحالي فيه `qzvnuyapnkkhxdlocpms.supabase.co` (تجريبي).
   - بعدها ارفع مجلد `03-frontend` بس على الاستضافة (Cloudflare Pages أو أي static host). **متتشرش** SQL ولا docs ولا tests على الاستضافة.
   - أضف رابط الموقع في Supabase > Authentication > URL Configuration.
6. أول مستخدم بيسجّل بيبقى **أدمن** تلقائياً (`handle_new_user`). بعدها اقفل التسجيل العام، وفعّل MFA للأدمن.
7. الإعدادات من داخل النظام: بيانات الشركة، ولوجو الشركة، وتخصيص الطباعة، وبعدين الفروع والخزائن والمخازن والمستخدمين.
8. النسخ الاحتياطي: انسخ `04-backup` لريبو **خاص** منفصل على GitHub، وحط الـsecrets بالأسماء دي بالظبط: `SUPABASE_URL`، `SUPABASE_SERVICE_ROLE_KEY`، `SUPABASE_DB_URL` (session pooler)، `BACKUP_PASSPHRASE` (احفظ نسخة منها بره GitHub!)، `GDRIVE_CLIENT_ID`، `GDRIVE_CLIENT_SECRET`، `GDRIVE_REFRESH_TOKEN`، `GDRIVE_FOLDER_ID`، و`GDRIVE_SERVICE_ACCOUNT_JSON` بس لو السكريبت بيستخدمه (راجع `backup/drive_tool.py`). شغّل الـworkflow يدوياً مرة، واعمل تجربة استرجاع على مشروع تاني (RESTORE_AR.md).
9. التحقق: شغّل `05-tests/check_erp.py` على مشروع **تجريبي**، وامشي على `05-tests/SCENARIOS.md`. وبعدين `07-local-test/ERP_rls_audit_READ_ONLY.sql` على Supabase الحقيقي، لازم الفحوص الخمسة تطلع صفر.

## قواعد اتعلمناها بالطريقة الصعبة
- كل إصدار جديد للواجهة: غيّر `APP_VERSION` في `app.js` **و** اسم الكاش في `sw.js`.
- عدّل `app.js` بـreplacements مُتأكَّد منها (exact + assert). ممنوع الـregex الواسع.
- مفتاح النسخ الاحتياطي خارج GitHub. من غيره النسخة مش هتتفتح.
- المحاسبة والأرصدة: اكتب الاختبار الأول، بعدين الكود.
- أي دالة RPC جديدة لازم يتعملها GRANT EXECUTE صريح للـauthenticated، لأن الصلاحيات الافتراضية مقفولة.

## حاجات لسه مفتوحة
- الاسترجاع من النسخة الاحتياطية لسه متجربش end-to-end على مشروع حقيقي.
- شاشات كتير اتجربت على stub بدون داتا حقيقية: الداشبورد (الأرقام)، شاشة الدخول على Supabase حقيقي، طباعة الفاتورة الفعلية.
- الترجمة الإنجليزي جزئية (dictionary-based).
- الخروج والدخول بيعملوا reload عن قصد، سيبهم زي ما هم.
- الوضع الداكن للنظام كله اتعمل بالـaudit، لكن محتاج مراجعة بصرية على داتا حقيقية.
- لوجو الـPWA (الأيقونات) لسه بالشكل القديم، ومحتاج تحويل من SVG لـPNG.
