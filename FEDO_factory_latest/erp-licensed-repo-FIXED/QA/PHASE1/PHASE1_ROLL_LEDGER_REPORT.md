# المرحلة 1 — دفتر الرولات التشغيلي (Roll Ledger v5)

**التاريخ:** 2026-11-04
**الفرع:** `arena/e7fb774f-ghonimx-fedo-customize`
**الحالة:** ✅ مكتملة محليًا — BUG‑04 (الرولات) من تقرير Codex مُغلق على المستوى الوظيفي، وBUG‑05 (الواجهة) مفتوح جزئيًا.
**بيئة الاختبار:** PostgreSQL 16.2 محلي + `supabase_shim.sql`. **لا Supabase، لا بيانات عميل، لا إنتاج.**

---

## 1) ما كان مفتوحًا في تقرير Codex

| Bug | الوصف | الحالة بعد هذه المرحلة |
|---|---|---|
| BUG‑04 HIGH | `factory_rolls` بلا رصيد متبقٍ ولا حركات ولا ربط بأمر تصنيع | ✅ **مُغلق** — دفتر حركات append‑only + أرصدة محسوبة + ربط بالأمر وحركة المخزون |
| BUG‑05 MEDIUM | الواجهة لا تستدعي `factory_register_rolls`/`factory_link_variant` | 🟡 **معالَج جزئيًا** — شاشة «المصنع — الرولات» تستدعي RPC الحقيقية للصرف/التقسيم/الشراء/التفعيل. `factory_link_variant` ما زالت من شاشة التصنيع (المرحلة 2) |
| BUG‑02 HIGH | لا كمية إنتاج فعلية | ⏳ المرحلة 2 |
| BUG‑03 HIGH | المنتج يدخل المخزون بلا اعتماد المخزن | ⏳ المرحلة 2 |
| BUG‑06 MEDIUM | لا دالة إلغاء لأمر التصنيع | ⏳ المرحلة 2 |

---

## 2) الملفات المضافة/المعدّلة

| الملف | النوع | الغرض |
|---|---|---|
| `erp-kit/01-database/ERP_FACTORY_ROLL_LEDGER_v5.sql` | جديد | دفتر الرولات التشغيلي (7 أنواع حركة، تجزئة الهالك/البواقي، تقسيم البقية، شراء ذري، تفعيل التتبع، معايرة التكلفة) |
| `erp-kit/05-tests/factory_roll_ledger_v5_test.sql` | جديد | 22 تحققًا تغطي الدورة كاملة + الصلاحيات + الحمايات |
| `erp-kit/05-tests/factory_roll_v5_race_setup.sql` | جديد | بيانات اختبار التزامن (قاعدة منفصلة) |
| `erp-kit/05-tests/factory_roll_v5_race_test.py` | جديد | جلستان تتنافسان على نفس الرول |
| `erp-kit/05-tests/factory_ui_smoke_test.js` | جديد | 28 تحقق واجهة على jsdom (بلا متصفح حقيقي) |
| `erp-kit/05-tests/package.json` | جديد | تشغيل الاختبارات (`npm run ui` / `npm run all`) |
| `erp-kit/05-tests/run_all_local.sh` | جديد | مشغّل واحد لكل شيء على قاعدة محلية |
| `erp-kit/03-frontend/factory-v5.js` | جديد | شاشة «المصنع — الرولات» (6 تبويبات) |
| `erp-kit/03-frontend/app.js` | تعديل محدود | إضافة مسار `factory` في NAV + صلاحيات admin/store + `APP_VERSION=DEV-2` |
| `erp-kit/03-frontend/index.html` | تعديل محدود | تحميل `factory-v5.js` |
| `erp-kit/03-frontend/sw.js` | تعديل محدود | كاش `v2` + إضافة الملف الجديد |

> لم يُعَد بناء أي وحدة موجودة: `ERP_BASE_CURRENT.sql` لم يُمس، ونمط العمل FEDO (فواتير/قيود/مخزون) لم يتغير.

---

## 3) ما يفعله الملف `ERP_FACTORY_ROLL_LEDGER_v5.sql`

1. **أنواع حركة موسّعة:** `receipt | consumption | waste | scrap | remainder | return | adjustment` مع قيد إشارة لكل نوع.
2. **تفصيل الاستخدام على الحركة:** `consumed_qty / waste_qty / scrap_qty` بحيث `المجموع = -quantity_delta` دائمًا (لا انفصال بين دفتر الرولات وحركة المخزون).
3. **تجزئة البقايا:** دالة `factory_split_roll_remainder` تنقل الكمية إلى رول جديد بكود مستقل، مع حركة `remainder` سالبة على الأصل و`receipt` موجبة على الجديد مرتبطة بـ`parent_roll_id` (بقية واحدة فقط لكل رول).
4. **الصرف:** `factory_roll_issue_internal` (خاصة، مسحوبة من كل الأدوار) + `factory_issue_roll` (عامة، تتطلب `mfg` + `stk`).
   - تقفل الرول ثم صف `stock_balances` ثم تستدعي `apply_stock` في نفس المعاملة.
   - تمنع تجاوز المتبقي، وتفرض مفتاح idempotency على `(request_id, roll_id)`.
5. **الشراء:** `factory_buy_rolls` تعيد استخدام `factory_purchase_managed_rolls` من v4 (فاتورة FEDO + قيود + رولات + حركات استلام في معاملة واحدة) مع رسالة واضحة إن لم يكن التتبع مفعّلًا.
6. **بدء التتبع:** `factory_enable_roll_tracking` — مسار آمن لصنف جديد برصيد صفر (0 = 0)، لأن التفعيل القديم يرفض أي فرق بين المخزون والرولات.
7. **معايرة التكلفة:** `factory_normalize_roll_costs` + trigger `factory_require_roll_costs` — لا يمكن التفعيل إن اختلفت تكلفة أي رول عن `products.avg_cost`، حتى لا تختلف قيمة المخزون عن قيمة دفتر الرولات.
8. **حارس الدفتر:** يمنع سالب أو تجاوز الكمية الأصلية ويمنع UPDATE/DELETE على الحركات.
9. **مفتاح تشغيل:** `erp.factory_ledger` يجب أن يكون `'on'` حتى تعمل RPC الشراء/الصرف — حتى لا يتفعل التتبع بالخطأ على قاعدة قائمة. لا يُضبط تلقائيًا.

---

## 4) نتائج الاختبار (سجل فعلي في `QA/PHASE1/`)

```
PASS  migration supabase_shim.sql
PASS  migration ERP_BASE_CURRENT.sql
PASS  migration ERP_FACTORY_CUSTOMIZE_v1.sql   (مرتين — idempotent)
PASS  migration ERP_FACTORY_FIX_MANUAL_JOURNAL_v2.sql (مرتين)
PASS  migration ERP_FACTORY_SMOKE_RETURN_TAX_v3.sql  (مرتين)
PASS  migration ERP_FACTORY_ROLL_LEDGER_v4.sql       (مرتين)
PASS  migration ERP_FACTORY_ROLL_LEDGER_v5.sql       (مرتين)
PASS  migration 99_final_lockdown.sql
PASS  factory_manual_journal_fix_test.sql
PASS  factory_tax_return_test.sql
PASS  factory_foundation.sql                 (12/12)
PASS  factory_legacy_flows.sql
PASS  factory_roll_ledger_test.sql           (v4 — 10/10)
PASS  factory_roll_ledger_v5_test.sql        (v5 — 22/22)
PASS  factory_legacy_smoke.sql               (13/13، ok=true)
PASS  lockdown 0/0/0
PASS  race: two concurrent work orders -> one succeeds, roll & stock both 10
PASS  ALL 28 UI CHECKS PASSED
PASS  node --check app.js / sw.js
ALL LOCAL CHECKS PASSED
```

### تفصيل `factory_roll_ledger_v5_test.sql` (22 تحققًا)

| # | التحقق |
|---|---|
| T0 | بدء التتبع يرفض صنفًا له رصيد، ويقبل الصنف عند رصيد صفر |
| T1 | شراء 100 وحدة برولين: فاتورة + قيد متوازن 1000/1000 + دفتر استلام بلا خصم مخزون مزدوج |
| T1 | إعادة نفس الطلب لا تكرر شيئًا، وإعادة الطلب ببيانات مختلفة تُرفض |
| T2 | التفعيل يرفض تكلفة رول غير معايرة، ثم ينجح بعد المعايرة |
| T2 | أرصدة الرولات 100 = مخزون FEDO 100، وقيمتها = المخزون × متوسط التكلفة |
| T3 | إنشاء أمر تصنيع لا يخصم شيئًا |
| T3 | صرف 10 + هالك 2 من رول واحد: المتبقي 28، المخزون 88، التفصيل مسجل |
| T3 | حركة المخزون مرتبطة بالدفتر (`factory_roll_issue`) |
| T3 | إعادة نفس الطلب بلا خصم إضافي |
| T3 | رفض صرف أكبر من المتبقي |
| T3 | رفض نفس المفتاح بكمية مختلفة |
| T4 | تقسيم بقية ينشئ رولًا مستقلًا (16/12) ولا يسمح بالتقسيم المزدوج |
| T5 | مجموع أرصدة الرولات = مخزون FEDO في كل خطوة، والقيمة متطابقة |
| T6 | منع أي حركة مخزون تتجاوز الدفتر، والدفتر append‑only |
| T7 | رفض دور المبيعات، ورفض مستخدم custom بلا `mfg`، ورفض الكتابة المباشرة، ورفض anon |
| T8 | منع تسجيل رول إضافي بعد التفعيل، ومنع رصيد سالب |
| T9 | دور `store` يحتفظ بصلاحية `mfg` بعد migration |

### اختبار التزامن (جلستان حقيقيتان)

- رول واحد برصيد 40، أمران مستقلان يطلبان 30 لكل منهما ← نجاح واحد فقط، الثاني يُرفض بـ«المتبقي بالرول لا يكفي».
- النتيجة النهائية: متبقي الرول 10، مخزون FEDO 10، حركة صرف واحدة بكمية 30.

---

## 5) الواجهة الجديدة — «المصنع — الرولات»

مسار `factory` في الشريط الجانبي (admin/accountant/store)، 6 تبويبات:

1. **أرصدة الرولات** — الرول، الخامة، المخزن، اللون، العرض، الأصلية، المتبقي، التكلفة، القيمة، الحالة.
2. **صرف واستخدام** — اختيار الرول وأمر التصنيع، كمية صرف + هالك + بواقي في نفس الطلب، وجدول آخر 50 حركة مع تفصيل الهالك/البواقي.
3. **تقسيم بقية** — نقل كمية إلى رول جديد بكود مستقل.
4. **شراء رولات** — صفوف ديناميكية، ثم `factory_buy_rolls` ذرية.
5. **تفعيل التتبع** — بدء التتبع لصنف برصيد صفر + معايرة تكلفة الأصناف المتتبعة.
6. **التركيبات** — عرض للقراءة فقط.

كل عملية كتابة تحمل مفتاح `request` عشوائيًا (UUID) يُعاد استخدامه عند الفشل ويُجدَّد بعد النجاح — وهذا مُختبر في `ui_smoke.log`.

---

## 6) كيف يعيد Codex التشغيل

```sh
# 1) قاعدة محلية فارغة + كل اختبارات SQL والتزامن والواجهة
cd erp-kit/05-tests
npm install            # لمرة واحدة (jsdom)
export PGHOST=/tmp PGPORT=5432 PGUSER=postgres   # حسب بيئتك
./run_all_local.sh --keep

# 2) اختبارات فقط على قاعدة قائمة
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f factory_roll_ledger_v5_test.sql

# 3) واجهة فقط
node factory_ui_smoke_test.js
```

---

## 7) قيود مقصودة (لم تُدّعَ كمكتملة)

- **إكمال التصنيع** ما زال يستخدم `complete_work_order` القديمة، ولا يستهلك من دفتر الرولات. المرحلة 2.
- **البواقي** تُسجَّل ككمية على الحركة وليست صنفًا مستقلًا قابلًا للبيع.
- **مرتجعات المشتريات/الجرد** لصنف متتبع ما زالت مرفوضة (كما في v4) حتى المرحلة 3.
- **صرف أكثر من رول لنفس أمر التصنيع** مدعوم بنيويًا (مفتاح `(request_id, roll_id)`) لكن الواجهة تصرف من رول واحد في كل استدعاء.
- **بوابة `erp.factory_ledger`** يجب ضبطها يدويًا؛ لا يوجد زر لها في الواجهة (مقصود).
- **Supabase الحقيقي / المتصفح الحقيقي / الموبايل / RTL المرئي** لم تُختبر؛ الواجهة اختُبرت على jsdom فقط.
