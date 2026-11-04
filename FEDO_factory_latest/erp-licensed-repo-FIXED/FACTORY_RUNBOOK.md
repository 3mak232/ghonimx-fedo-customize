# تشغيل الحزمة التجريبية — ليس للإنتاج

1. نسخة أرشيف المصدر قبل تعديل الملفات محفوظة في `ORIGINAL_BACKUP/erp-licensed-repo-LOCKED-original.zip`؛ SHA-256: `1c34c96e2494e35b46226a8a711a12bde6e7863162231c326b73a5c03ae6d70e`. ليست نسخة من قاعدة بيانات. قبل أي تطوير لاحق على قاعدة فعلية اطلب نسخة متسقة ومشفرة من قاعدة البيانات والـauth والـstorage وتحقق من الاسترجاع على مشروع تجريبي باستخدام آلية المشروع، دون مشاركة الأسرار.
2. أنشئ PostgreSQL تجريبيًا فارغًا. مثال (مستخدم قاعدة مناسب):
   ```sh
   createdb fedo_factory_test
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/07-local-test/supabase_shim.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_BASE_CURRENT.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_CUSTOMIZE_v1.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_FIX_MANUAL_JOURNAL_v2.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/99_final_lockdown.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_manual_journal_fix_test.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_foundation.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_legacy_flows.sql
   psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_legacy_smoke.sql
   node --check erp-kit/03-frontend/app.js
   ```
   اختبار smoke يتجاوز القيد اليدوي بعد إصلاح v2 لكنه يفشل في توقع رصيد العميل؛ راجع `QA_RESPONSE_2026-11-04.md` للنتيجة والتحليل المحدود. `FACTORY_TEST_REPORT.md` يوثق التشغيل السابق قبل الإصلاح. المحاكاة ليست Supabase، ولم يُختبر الترخيص هنا. على staging حقيقي اتبع ترتيب الأساس والترخيص والتحديثات وlockdown كما في وثائق المشروع، بعد استكمال التطوير، ولا تضع أسرارًا بالواجهة.
3. واجهة التطبيق لم تُختبر بصريًا. تعرض تنبيهًا داخل التصنيع وجدول الرولات المسجلة إن كانت الجداول متاحة. عملية `إكمال` الأصلية ما زالت غير متوافقة مع المصنع ولا يجب استخدامها لهذا الغرض. لم تُبنَ شاشات الإدخال النهائية.
4. لا تطبق migration الحالية على الإنتاج: التسجيل وصفي وغير متكامل مع الصرف والمرتجع والإلغاء، وRPC التصنيع القديمة ما زالت خطرة على نموذج المصنع. استكمل العناصر المفتوحة في التصميم وكرر الاختبارات على staging قبل اتخاذ أي قرار نشر.

## قرارات/بيانات العميل المطلوبة لاحقًا
- وحدات قياس طول وعرض كل خامة والتحويلات، وترميز الألوان والمقاسات والباركود والقوائم والأسعار.
- حسابات المواد تحت التشغيل والهالك والعمالة وسياسة تقييم التكلفة، وتوزيع الخصومات واعتماد المحاسب.
- ربط المستخدم الفعلي بدور المالك منفصلًا عن المدير وحدود التعديل والاعتمادات.
- المراحل الفعلية لكل منتج ووصفاتها، وأرصدة البداية على مستوى الرول وطريقة ترحيل البيانات.
- بيانات شركات الشحن والمتجر عند الاتفاق؛ أي بوابات دفع أو فاتورة إلكترونية تتطلب اتفاقًا منفصلًا.
