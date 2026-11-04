# ERP + لوحة التحكم
- `erp-kit/`: كيت الـERP (v3) + وحدة الترخيص (`LICENSE_MODULE.sql` و`license-sync`).
- `control-plane/`: اللوحة المركزية (SQL، دالة الإرسال الموقّعة، الداشبورد `04-dashboard/index.html`).
ابدأ من `control-plane/README-AR.md`. **ماترفعش أي مفتاح خاص أو secrets هنا أبدًا.**
- ترتيب SQL لكل عميل: `ERP_BASE_CURRENT.sql` ← `LICENSE_MODULE.sql` ← `99_final_lockdown.sql` ← فحص `ERP_rls_check_combined_READ_ONLY.sql`.
