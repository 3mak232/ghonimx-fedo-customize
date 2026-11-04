# FEDO Customize — HANDOFF للمطور التالي

**آخر تحديث:** 2026-11-04 · **الفرع:** `arena/e7fb774f-ghonimx-fedo-customize` · **Pull Request:** #1 (OPEN، لم يُدمج)

> اقرأ هذا الملف كاملًا قبل أي سطر كود. كل ما فيه ناتج تشغيل فعلي على قاعدة محلية، وليس خطة.

---

## 0) في 60 ثانية

| البند | الحالة |
|---|---|
| المرحلة 1 (دفتر الرولات) | ✅ **مكتملة ومختبرة** — مدفوعة في PR #1 |
| المرحلة 2 (إنتاج جزئي / اعتماد / إلغاء / قيود) | 🟡 **الكود مكتوب ويعمل، غير مدفوع، وبلا اختبار منهجي ولا واجهة** |
| المرحلة 3 (مرتجعات/جرد/تحويل أصناف متتبعة) | ⏳ لم تبدأ |
| الواجهة | شاشة «المصنع — الرولات» (المرحلة 1) فقط؛ المرحلة 2 بلا واجهة |
| الإنتاج / Supabase / بيانات عميل | ❌ لم يُلمس إطلاقًا |

الخطوة التالية الأهم: **اختبار المرحلة 2 منهجيًا (`factory_production_v6_test.sql`) ثم الواجهة، ثم commit وPR.**

---

## 1) المستودع والبنية

```
ghonimx-fedo-customize/
└── FEDO_factory_latest/erp-licensed-repo-FIXED/
    ├── erp-kit/01-database/        ← SQL فقط (الأساس + التخصيصات)
    │   ├── ERP_BASE_CURRENT.sql                 (FEDO الأصلي — ممنوع التعديل)
    │   ├── LICENSE_MODULE.sql                   (ترخيص — ممنوع التعديل)
    │   ├── ERP_FACTORY_CUSTOMIZE_v1.sql         (تأسيس المصنع — Codex)
    │   ├── ERP_FACTORY_FIX_MANUAL_JOURNAL_v2.sql (إصلاح BUG-01)
    │   ├── ERP_FACTORY_SMOKE_RETURN_TAX_v3.sql  (تصحيح توقع ضريبة المرتجع)
    │   ├── ERP_FACTORY_ROLL_LEDGER_v4.sql       (دفتر رولات تجريبي — Codex)
    │   ├── ERP_FACTORY_ROLL_LEDGER_v5.sql       ← عملنا: المرحلة 1 (مدفوع)
    │   ├── ERP_FACTORY_PRODUCTION_v6.sql        ← عملنا: المرحلة 2 (غير مدفوع)
    │   └── 99_final_lockdown.sql                (يُشغَّل دائمًا آخرًا)
    ├── erp-kit/03-frontend/        ← app.js (FEDO 433KB) + factory-v5.js (جديد)
    ├── erp-kit/05-tests/           ← كل الاختبارات + run_all_local.sh
    ├── erp-kit/07-local-test/      ← supabase_shim.sql
    └── QA/                         ← تقاريرنا + تعليمات Codex + سجلات
```

**قواعد صارمة:**
1. لا تعديل على `ERP_BASE_CURRENT.sql` ولا `LICENSE_MODULE.sql` ولا على `app.js` خارج حدود صغيرة موثقة.
2. لا إعادة بناء وحدة موجودة: نضيف migration جديدة فوق السابقة.
3. كل migration جديدة تعمل **مرتين** بلا خطأ (idempotent) وتنتهي بـ `COMMIT;`.
4. كل ملف بالترتيب: `BEGIN;` … `COMMIT;`.

---

## 2) الحالة الحقيقية للمرحلة 1 (مدفوعة في PR #1)

### ما يعمل ومختبر
- دفتر رولات append-only: أنواع `receipt / consumption / waste / scrap / remainder / return / adjustment`.
- صرف + هالك + بواقي في حركة واحدة مربوطة بحركة مخزون FEDO في نفس المعاملة.
- تقسيم بقية إلى رول مستقل (`parent_roll_id`).
- شراء رولات ذري: فاتورة FEDO + قيد الشراء + دفتر الاستلام + الرولات في معاملة واحدة.
- تفعيل التتبع لصنف: إما من رصيد صفر (`factory_enable_roll_tracking`)، أو تفعيل صنف قائم بعد تسجيل رولاته (`factory_activate_roll_control`) — والأخير يرفض إن لم تُعايَر تكلفة الرولات مع `products.avg_cost`.
- الواجهة: شاشة «المصنع — الرولات» بـ 6 تبويبات.

### نتائج التشغيل الفعلية (سجلات في `QA/PHASE1/`)
```
run_all_local.sh ............. ALL LOCAL CHECKS PASSED
factory_roll_ledger_v5_test ... 22/22
factory_roll_ledger_test (v4) . 10/10
factory_foundation ............ 12/12
factory_legacy_flows .......... PASS
factory_legacy_smoke (13 بند) . ok=true
factory_tax_return_test ....... PASS
factory_manual_journal_fix_test 7/7
race (جلستان) ................. PASS (10/10)
UI smoke (jsdom) .............. 28/28
lockdown ..................... 0/0/0
```

### مفاتيح تشغيل مهمة
```sql
-- شرط تشغيل RPC الرولات والإنتاج (لا يُضبط تلقائيًا عن قصد)
ALTER DATABASE fedo_factory_test SET erp.factory_ledger = 'on';
-- أو لجلسة واحدة
SELECT set_config('erp.factory_ledger','on',false);
```
بدون هذا المفتاح: `factory_buy_rolls` / `factory_issue_roll` / `factory_record_batch` / `factory_approve_batch` ترفض العمل برسالة صريحة.

---

## 3) المرحلة 2 — ملف غير مدفوع جاهز للاختبار

**الملف:** `erp-kit/01-database/ERP_FACTORY_PRODUCTION_v6.sql` (غير موجود في git بعد — موجود في مجلد العمل فقط).

### يعالج
| Bug (Codex) | كيف |
|---|---|
| **BUG-02** إنتاج جزئي بلا كمية فعلية | `factory_record_batch(request, order, good_qty, uses, waste_qty, scrap_qty, note)` — دفعات متعددة بأي كمية ≤ المخطط |
| **BUG-03** المنتج يدخل المخزون بلا اعتماد | `work_orders.production_mode='batched'` + `requires_approval` + `factory_approve_batch` — **لا تدخل الكمية المخزون القابل للبيع قبل الاعتماد** |
| **BUG-06** لا إلغاء | `factory_reject_batch(batch, reason)` لرفض دفعة غير معتمدة |
| القيود المحاسبية | `_rebuild_journal` جديد يضيف قيود الدفعات والاعتماد، و`rebuild_journal()` العامة أصبحت تنادي `_rebuild_journal(NULL,NULL)` (كانت نسخة قديمة تحذف قيود المصنع) |

### الجداول/الدوال المضافة
- `work_order_batches` (سجل الدفعات) + `work_order_batch_uses` (تفصيل الاستهلاك لكل رول/صنف).
- `work_order_production` (view: صالح / معتمد / تحت الاعتماد / هالك / تكاليف / عدد الدفعات).
- أعمدة `work_orders`: `production_mode`, `requires_approval`, `started_at`, `completed_at`, `cancelled_at`, `cancel_reason`, `closed_by`.
- أعمدة `factory_roll_moves`: `production_batch_id`.
- حساب جديد: `1210 Work In Process - Manufacturing`.
- دوال: `factory_start_work_order`, `factory_record_batch`, `factory_approve_batch`, `factory_reject_batch`, `factory_manual_requirement`.
- trigger `factory_batch_journal` → ترحيل القيود فورًا بعد كل دفعة/اعتماد.

### القيود المحاسبية (مُتحقَّق منها فعليًا)
مثال حقيقي من التشغيل: 60 وحدة قماش بـ 10، أمر 5 قطع بعمالة 50، دفعة 3 قطع (استهلاك 5 + هالك 1):

| القيد | الحساب | مدين | دائن |
|---|---|---:|---:|
| دفعة إنتاج | 1210 إنتاج تحت التشغيل | 80.00 | |
| | 1200 المخزون | | 60.00 |
| | 2200 مستحق التصنيع | | 30.00 |
| | 6100 هالك التصنيع | 10.00 | |
| **اعتماد المخزن** | 1200 المخزون | 90.00 | |
| | 1210 إنتاج تحت التشغيل | | 90.00 |

- كل قيد متوازن، و`rebuild_journal()` الكامل يعطي **نفس** النتيجة الحرفية (تم التحقق: `rebuild parity: IDENTICAL`).
- تكلفة القطعة = 30 = (6 وحدة × 10 + عمالة 30) / 3.

### نتائج تشغيل v6 الحالية
```
تحميل migration ........... ✅ (وشغّلناه مرتين)
الاختبارات القديمة كلها .... ✅ rc=0 (v5: 22/22 · v4: 10/10 · foundation 12/12 · smoke ok · tax · manual journal)
فحص يدوي لمسار كامل ...... ✅ أمر → دفعة → اعتماد → مخزون 3 · رول متبقي 54 · قيد متوازن
rebuild parity ............ ✅ IDENTICAL
```
**لكن:** لا يوجد بعد ملف اختبار رسمي للمرحلة 2 (`factory_production_v6_test.sql`), ولا واجهة، ولا تحديث لـ `run_all_local.sh`. هذا هو النقص الحقيقي.

### أخطاء أُصلحت أثناء العمل (لا تُعِدها)
1. `END $function$` بلا `;` → خطأ صياغة عند إضافة SQL بعده.
2. الملف كان بلا `COMMIT;` → كل شيء كان يُلغى صامتًا.
3. `b.consumed_at` غير موجود → الصحيح `b.recorded_at`.
4. `m.product_id` غير موجود على `factory_roll_moves` → يجب `JOIN factory_rolls r`.
5. الحارس كان يمنع RPC نفسه من كتابة التكلفة → صار يمنع تغيير الكميات دائمًا، والتكلفة بعد الاعتماد فقط.
6. إعادة الترحيل كانت تكرر قيود الاعتماد → الحذف الجزئي يمسح `work_order_approval` أيضًا.
7. قيد الدفعة كان غير متوازن (لا يُحمّل العمالة على WIP) → صُحّح.
8. `rebuild_journal()` العامة نسخة قديمة تحذف قيود المصنع → وُجّهت إلى `_rebuild_journal(NULL,NULL)`.

---

## 4) المطلوب منك بالترتيب (Definition of Done للمرحلة 2)

### أ) بيئة الاختبار
تحتاج PostgreSQL ≥ 14 (اختبرنا 16.2). في هذه الحاوية لا يوجد PostgreSQL مثبت:
```sh
python3 -m venv /tmp/pgenv && /tmp/pgenv/bin/pip install pgserver
export PATH=/tmp/pgenv/lib/python3.11/site-packages/pgserver/pginstall/bin:$PATH
export PGUSER=postgres PGHOST=/tmp/pgsock PGPORT=5433
export PGDATA=/tmp/pgdata_fedo && mkdir -p /tmp/pgsock
initdb -D $PGDATA -U postgres --auth=trust -E UTF8 >/dev/null
pg_ctl -D $PGDATA -o "-p 5433 -k /tmp/pgsock -c listen_addresses=''" -l /tmp/pg.log start
```
> ملاحظة: نسخة `pgserver` لا تحتوي `pgcrypto`. الحل المستخدم: ملفا stub في
> `share/postgresql/extension/pgcrypto.control` و `pgcrypto--1.3.sql` (body فاضي)،
> لأن المخطط يستخدم فقط `gen_random_uuid()` و`sha256()` و`encode()` المدمجة.

### ب) اختبار المرحلة 2 — اكتب `erp-kit/05-tests/factory_production_v6_test.sql`
غطِّ على الأقل (كلها داخل `BEGIN … ROLLBACK`):

1. إنشاء أمر بالمسار الجديد لا يمس المخزون، ولا يوجد أي منتج قابل للبيع.
2. دفعة جزئية 3 من 5: المخزون النهائي **صفر** قبل الاعتماد، والرول نقص فعلًا.
3. اعتماد الدفعة: المخزون يصبح 3، الأمر `In Progress`، تكلفة القطعة صحيحة.
4. إعادة نفس مفتاح الاعتماد → نفس النتيجة بلا تكرار.
5. إعادة تسجيل نفس مفتاح الدفعة → نفس المعرّف بلا خصم مضاعف؛ ومفتاح متعارض ببيانات مختلفة → رفض.
6. اعتماد 2 من 3 (اعتماد جزئي): يبقى 1 تحت الاعتماد، والقيد يعكس 2 فقط.
7. اعتماد الدفعات خارج الترتيب → رفض.
8. رفض دفعة (reject) → لا حركة مخزون، ولا تُحتسب في `work_order_production`.
9. تجاوز الكمية المخططة (good+waste) → رفض.
10. الإكمال الكامل: آخر دفعة تُعتمد → `status='Completed'` و`produced_qty` صحيح.
11. قيود: كل قيد متوازن، و`rebuild_journal()` يعطي نفس السطور حرفيًا (parity).
12. صلاحيات: `sales` ممنوع، `store` يعتمد ولا يسجّل بلا `mfg`، `custom` بلا `stk` ممنوع، `anon` ممنوع، والكتابة المباشرة على `work_order_batches` ممنوعة.
13. رفض أي استهلاك يتجاوز رصيد الرول (يأتي منطبقة من v5 — تأكد أنه يعمل داخل الدفعة).

### ج) ضمّ المرحلة 2 إلى الحزمة
- أضف `ERP_FACTORY_PRODUCTION_v6.sql` إلى `erp-kit/05-tests/run_all_local.sh` (قبل `99_final_lockdown.sql`، وشغّله مرتين).
- أضف `factory_production_v6_test.sql` إلى نفس السكربت.
- شغّل `./run_all_local.sh` حتى يطبع `ALL LOCAL CHECKS PASSED`.

### د) واجهة المرحلة 2
أضف إلى `erp-kit/03-frontend/factory-v5.js` (أو ملف جديد `factory-v6.js` يُحمَّل بعده) شاشة «أوامر الإنتاج»:
- جدول `work_order_production` (مخطط/صالح/معتمد/تحت الاعتماد/هالك/تكلفة).
- نموذج تسجيل دفعة: اختيار الرولات + الكميات المستهلكة/الهالك/البواقي + الكمية الصالحة.
- زر اعتماد (لمن يملك `stk`) وزر رفض بسبب.
- مفاتيح idempotency في المتصفح: نفس نمط `FM.req()` الموجود (أعد استخدامه).
- اختبر بـ `erp-kit/05-tests/factory_ui_smoke_test.js` (jsdom) — أضف تبويبًا وتحققات له.

### هـ) الترتيب والتسليم
1. `git add` للملفات الأربعة (migration + الاختبار + الواجهة + السكربت).
2. commit رسالته تبدأ `feat(factory): phase 2 ...`.
3. `git push origin arena/e7fb774f-ghonimx-fedo-customize` (نفس الفرع، PR #1 يتحدث تلقائيًا).
4. أضف قسم `## المرحلة 2` إلى وصف PR عبر `gh pr edit 1 --body-file <file>`.
5. حدّث `QA/PHASE1/…` أو أنشئ `QA/PHASE2/PHASE2_PRODUCTION_REPORT.md` بسجلات التشغيل.

> **مهم:** لا تُدمج PR بنفسك. المالك هو من يطلب الدمج.

---

## 5) المرحلة 3 — ما تبقى (لم يبدأ)

- مرتجع شراء/جرد/تحويل لصنف **متتبع**: حاليًا مرفوض بـ«اختلاف مخزون الصنف» (مقصود من v4). يحتاج مسارًا ذريًا يحرّك الدفتر والمخزون معًا.
- البواقي كصنف مستقل قابل للبيع/الاستخدام (`scrap_qty` يُسجَّل الآن ككمية فقط).
- مراحل التصنيع القابلة للتهيئة (`work_order_stages`).
- شحن وتحصيل ومصدر الطلب (`sales_orders` → شحنة → COD).
- فصل المالك عن المدير (policy ملكية + صلاحيات ذرية).
- توسيع BOM: SKU الناتج يحدد اللون/المقاس، وربط خامة/رول محدد لكل مكوّن.

---

## 6) دورة QA مع Codex

- التعليمات الرسمية في `QA/CODEX_INSTRUCTIONS.md` (مكتوبة ومتفق عليها).
- Codex يشغّل: `cd erp-kit/05-tests && npm install && ./run_all_local.sh --keep`.
- يرفع `QA/<DATE>_PHASE<N>/CODEX_REPORT.md` بأربعة أقسام إلزامية، وكل بند فاشل بـ `BUG-xxx` + ملف:سطر + خطوات إعادة إنتاج.
- **لا تصلح تقارير QA داخل ملفات `01-database` أو `03-frontend`.** الإصلاح مسؤوليتك، والتقرير يبقى شاهدًا.
- بوابات القبول (9 نقاط) في القسم 6 من `QA/CODEX_INSTRUCTIONS.md` — لا تعلن مرحلة مكتملة قبل اجتيازها.

---

## 7) أرقام وحقائق تعتمد عليها

- أصل FEDO: 100 جدول في `public` بعد كل migrations (كان 100 قبل المرحلة 1 أيضًا).
- `has_perm`/`require_perm` موجودة أصلًا؛ `role_default_perms` تحدد `store→mfg` (أُضيف في v5).
- `apply_stock` هو المسار الوحيد لتغيير `stock_balances` ولا بد أن يبقى متسقًا مع الدفتر؛ حارسه مؤجل `CONSTRAINT TRIGGER` على `stock_balances`.
- `journal_entries.doc_type` للتصنيع: `work_order` (قديم) · `work_order_batch` · `work_order_approval`.
- رمز `factory_roll_issue` في `stock_movements.doc_type` يربط الحركة بالدفتر.
- حسابات: 1200 مخزون · 1210 إنتاج تحت التشغيل · 2200 مستحق التصنيع · 6100 هالك · 5000 تكلفة مبيعات · 1300 عملاء · 2100/1410 ضريبة.
- اختبار التزامن يحتاج قاعدة باسم محدد `fedo_roll_v5_race` (fixture يرفض غيرها).

---

## 8) تحذيرات

- **لا تشغّل أي شيء على Supabase حقيقي أو قاعدة عميل.** كل الاختبارات محلية.
- لا تضع أسرارًا أو `sb_secret` في الواجهة أو في المستودع.
- `factory_activate_roll_control` على صنف له رصيد يمنع كل مسارات FEDO القديمة لذلك الصنف — لا تفعّله على قاعدة حقيقية قبل المرحلة 3.
- تغيير `app.js` كبير ومتشابك (433KB): بعد أي تعديل نفّذ `node --check app.js` وشغّل UI smoke.
- ملفات `.dump` و`*.zip` في `LOCAL_CHECKPOINTS/` ليست نسخ احتياطية لإنتاج.
