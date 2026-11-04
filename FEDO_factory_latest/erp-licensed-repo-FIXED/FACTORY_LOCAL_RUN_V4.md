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
