# أوامر إعادة الاختبار المحلي — تجريبي فقط

**ممنوع استخدام قاعدة إنتاج أو عميل.** تعمل هذه الخطوات على قاعدة PostgreSQL فارغة محلية وتستخدم محاكاة Supabase؛ يفترض وجود الأدوار المناسبة. توجيهات المشروع الأصلية للترخيص والإنتاج لا تُستبدل بهذه الأوامر.

```sh
createdb fedo_factory_test
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/07-local-test/supabase_shim.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_BASE_CURRENT.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_CUSTOMIZE_v1.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_FIX_MANUAL_JOURNAL_v2.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_SMOKE_RETURN_TAX_v3.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_ROLL_LEDGER_v4.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/99_final_lockdown.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_manual_journal_fix_test.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_tax_return_test.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_foundation.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_legacy_flows.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_roll_ledger_test.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_legacy_smoke.sql
```

اختبار التزامن يُنشئ بيانات فعلية في قاعدة منفصلة باسم ثابت `fedo_roll_race` ويجب حذفها بعدها. مثلًا إن كان الاتصال المحلي يتطلب postgres عبر sudo:

```sh
sudo -u postgres createdb -T fedo_factory_test fedo_roll_race
python3 erp-kit/05-tests/factory_roll_race_test.py --sudo-postgres
sudo -u postgres dropdb fedo_roll_race
```

لا تُفعّل تتبع صنف على قاعدة حقيقية: التفعيل يمنع مسارات FEDO القديمة غير المربوطة بدفتر الرولات. لا تُستدعَ دالة الصرف الداخلية خارج الاختبار؛ قيود التصنيع والاعتماد وواجهة المستخدم لم تكتمل. النتائج والقيود في `FACTORY_PHASE_PROGRESS_2026-11-04.md`.

---

## تحديث 2026-11-04 — دفتر الرولات v5 (المرحلة 1)

أبسط طريقة: مشغّل واحد على قاعدة محلية فارغة.

```sh
cd erp-kit/05-tests && npm install && ./run_all_local.sh --keep
```

الترتيب اليدوي المكافئ (كل ملف v1→v5 مرتين لإثبات idempotency):

```sh
createdb fedo_factory_test
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/07-local-test/supabase_shim.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_BASE_CURRENT.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_CUSTOMIZE_v1.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_FIX_MANUAL_JOURNAL_v2.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_SMOKE_RETURN_TAX_v3.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_ROLL_LEDGER_v4.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/ERP_FACTORY_ROLL_LEDGER_v5.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/01-database/99_final_lockdown.sql
psql -v ON_ERROR_STOP=1 -d fedo_factory_test -f erp-kit/05-tests/factory_roll_ledger_v5_test.sql
```

### مفتاح تشغيل مسار الرولات

RPC الشراء/الصرف من الرول ترفض العمل (رسالة صريحة) إلا إذا كان
`erp.factory_ledger = 'on'` لهذه القاعدة أو الجلسة. لا يُضبط تلقائيًا عن قصد:

```sql
-- لقاعدة اختبار فقط
ALTER DATABASE fedo_factory_test SET erp.factory_ledger = 'on';
-- أو لجلسة واحدة
SELECT set_config('erp.factory_ledger','on',false);
```

### نتيجة المرحلة 1

- `factory_roll_ledger_v5_test.sql`: 22/22.
- اختبار التزامن: جلستان على رول واحد ← نجاح واحد ورفض الآخر، والرصيد النهائي 10/10.
- اختبار الواجهة (jsdom): 28/28.
- `lockdown 0/0/0`.

التفاصيل والقيود في `QA/PHASE1/PHASE1_ROLL_LEDGER_REPORT.md`.
