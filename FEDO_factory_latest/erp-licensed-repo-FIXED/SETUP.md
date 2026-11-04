# دليل الرفع والتجربة — النسخة المصححة (FIXED)

> هذه النسخة مصححة من `erp-licensed-repo.zip` الأصلي. تم استبدال الروابط التجريبية بعلامات `__SUPABASE_URL__` حتى لا تنسى تغييرها.

---

## 0) المطلوب قبل أي شيء
- حساب Supabase (supabase.com)
- Node.js 18+ (للأداة `gen_keys.mjs` فقط)
- استضافة Static (Cloudflare Pages أو Netlify أو Vercel) للواجهة والداشبورد
- لا ترفع الملف الأصلي على GitHub علناً — فيه منطق ترخيصك

---

## 1) اللوحة المركزية (مرة واحدة فقط)

1. **أنشئ مشروع Supabase جديد** سمّه `erp-panel` (هو اللوحة فقط، لا تضع فيه بيانات العملاء)
2. افتح **SQL Editor** > الصق محتوى `control-plane/01-central/central_schema.sql` > Run
3. على جهازك شغّل:
   ```
   node control-plane/03-tools/gen_keys.mjs
   ```
   سيطبع سطرين — **احفظهما**:
   - `LICENSE_PRIVATE_KEY=...` (خاص — لا يخرج من لوحتك أبداً، احفظ نسخة في Password Manager)
   - `LICENSE_PUBLIC_KEY=...` (عام — ستضعه عند كل عميل)
4. **أنشئ حسابك:** Supabase > Authentication > Add user (email+password) > سجل دخول مرة > فعّل MFA من إعدادات المستخدم > ثم في SQL Editor:
   ```sql
   INSERT INTO panel_staff(user_id,name,role) VALUES('<UUID حسابك>','اسمك','owner');
   -- لمعرفة UUID: Authentication > Users > انسخ الـ ID
   ```
   ثم اقفل التسجيل: Authentication > Providers > Email > Disable sign-ups
5. **انشر دالة الإرسال:**
   ```
   supabase link --project-ref <panel-ref>
   supabase functions deploy push-license
   -- ثم في Dashboard > Edge Functions > push-license > Secrets ضع:
   -- LICENSE_PRIVATE_KEY = (الخاص من الخطوة 3)
   -- ADMIN_SECRET_KEY    = (مفتاح service_role لمشروع اللوحة نفسه من Project Settings > API)
   ```
6. **ارفع الداشبورد:** افتح `control-plane/04-dashboard/index.html` وبدّل أول سطرين:
   ```js
   const SUPABASE_URL = "https://<panel-ref>.supabase.co";
   const SUPABASE_KEY = "<anon/publishable key للوحة>";
   ```
   ثم ارفع الملف على Cloudflare Pages (مجلد واحد يكفي). افتحه وجرب الدخول بـ MFA.
7. من الداشبورد > **الخطط** > أضف خطتك الأولى (مستخدمين/فروع/مخازن/وحدات).

---

## 2) كل عميل جديد (كررها لكل مشروع)

1. **أنشئ مشروع Supabase جديد** للعميل (مثال `erp-client-acme`)
2. **SQL Editor (مهم الترتيب):**
   - شغّل `erp-kit/01-database/ERP_BASE_CURRENT.sql` **وحده** على مشروع فاضي
   - بعدها مباشرة شغّل `erp-kit/01-database/LICENSE_MODULE.sql` (أو `control-plane/02-client/license_module.sql` — نفس الملف)
- **آخر ملف SQL:** شغّل `erp-kit/01-database/99_final_lockdown.sql` بعد القاعدة والترخيص (وبعد أي تحديث SQL لاحق)، وبعده `erp-kit/07-local-test/ERP_rls_check_combined_READ_ONLY.sql` (المطلوب: النوع 1 و2 و3 فاضيين، والنوع 4 = `app_version` و`app_lock_state` بس).
3. **Edge Functions عند العميل:**
   ```
   supabase link --project-ref <client-ref>
   supabase functions deploy login-with-identifier --no-verify-jwt
   supabase functions deploy admin-create-user
   supabase functions deploy full-backup
   supabase functions deploy full-restore
   supabase functions deploy license-sync --no-verify-jwt
   ```
   ثم في Dashboard > Edge Functions > `license-sync` > Secrets:
   - `LICENSE_PUBLIC_KEY` = (العام من الخطوة 1.3)
   - `CLIENT_ID`          = (UUID العميل من لوحتك: لوحة > العملاء > انسخ الـ ID)
   - `ADMIN_SECRET_KEY`   = (service_role لمشروع **العميل** نفسه)
   > وباقي الدوال (`login-with-identifier` وغيرها) تحتاج نفس `ADMIN_SECRET_KEY`/`SUPABASE_*` حسب أول ملف — راجع أول 10 أسطر من كل `index.ts`.

4. **الواجهة (أهم إصلاح):** افتح المجلد `erp-kit/03-frontend/`:
   - في `app.js` السطر 1 بدّل:
     ```js
     const URL_='__SUPABASE_URL__',KEY='__SUPABASE_ANON_KEY__';
     // إلى مثلاً:
     const URL_='https://<client-ref>.supabase.co',KEY='<anon/publishable key للعميل>';
     ```
   - في `index.html` بدّل:
     ```html
     <link rel="preconnect" href="__SUPABASE_URL__" crossorigin>
     <!-- ومعها CSP: connect-src 'self' __SUPABASE_URL__ wss://... -->
     ```
     اجعلها نفس رابط العميل. بدون هذا سيفشل تسجيل الدخول.
   - ارفع **مجلد `03-frontend` فقط** على الاستضافة (لا ترفع SQL ولا docs).
   - في Supabase > Authentication > URL Configuration ضع رابط موقعك.

5. **أول دخول:** سجل مستخدم أول — سيصبح `admin` تلقائياً (`handle_new_user`) > بعدها اقفل التسجيل العام وفعّل MFA للأدمن.

6. **أهم خطوة — تفعيل الترخيص (بدونها العميل بلا حدود!):**
   - في اللوحة > **العملاء** > + عميل > احفظه > افتحه > انسخ `CLIENT_ID` وضعه Secret عند العميل (تم أعلاه)
   - ضع `license_endpoint` = `https://<client-ref>.supabase.co/functions/v1/license-sync`
   - ثم **الاشتراك** (اختر الخطة والتاريخ) > **إرسال الترخيص** > **فحص**
   - تأكد أن `seq` في اللوحة = `seq` عند العميل (يظهر في `v_watch` و `license_state()`)

7. **الاختبار:** شغّل على مشروع **تجريبي فقط**:
   ```
   ERP_URL=https://<site> ERP_USER=<user> ERP_PASS=<pass> python 05-tests/check_erp.py
   ```
   ثم في SQL Editor للعميل شغّل `07-local-test/ERP_rls_audit_READ_ONLY.sql` — يجب أن تكون الخمس فحوص = 0.

---

## 3) النسخ الاحتياطي
- انسخ `erp-kit/04-backup` إلى ريبو **خاص** منفصل على GitHub
- ضع Secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL` (session pooler), `BACKUP_PASSPHRASE` (احفظ نسخة خارج GitHub!), `GDRIVE_*`
- شغّل الـ workflow يدوياً مرة + جرب استرجاع على مشروع ثاني (راجع `04-backup/backup/RESTORE_AR.md`)

---

## 4) قائمة الفحص السريع (CHECKLIST.md)
راجع `CHECKLIST.md` قبل التسليم لأي عميل.

---

## تنبيهات
- المطور كتب: الكود تم اختباره للتوقيع فقط بـ Node — **لم يُشغّل على Supabase حقيقي بعد**. جرّب على مشروعين تجريبيين (لوحة + عميل) أولاً.
- لو انتهى الاشتراك ولم تغيّر الحالة يدوياً، العميل يبقى شغال (تنبيه فقط).
- لو ضاع `LICENSE_PRIVATE_KEY` ستحتاج تغيير العام عند كل عميل.

بالتوفيق!
