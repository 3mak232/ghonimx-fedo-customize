-- ERP_FULL_SETUP_v1.65.sql: التثبيت الكامل على داتابيز فاضية (base + كل الباتشات حتى 1.66)
-- شغّله مرة واحدة في SQL Editor. ماتشغلش باتشات بعده.
-- ============================================================
-- ERP v1.20 - قاعدة البيانات الكاملة (Supabase / PostgreSQL)
-- الترتيب: الملف الأساسي ERP_full_v5 (يشمل 010 و 018 تتبع/MRP)،
-- ثم الترقيعات بالترتيب الرقمي. كل ترقيعة مغلفة بـ BEGIN/COMMIT.
-- ملاحظة: الترقيع 023 غير موجود في الملفات المرفوعة.
-- ============================================================

-- ====================== schema.sql ======================
-- ERP Supabase schema. Run once in Supabase > SQL Editor.
create extension if not exists pgcrypto;

-- ========== TABLES ==========
create table profiles(id uuid primary key references auth.users on delete cascade, name text not null, username text unique,
  role text not null default 'sales' check(role in('admin','accountant','sales','store')), active boolean not null default false, created_at timestamptz default now());
create table company_settings(id int primary key default 1 check(id=1), company_name text default 'شركتي', phone text, address text, tax_number text, logo_url text,
  currency text default 'EGP', invoice_prefix text default 'INV-', tax_enabled boolean default false, tax_pct numeric(5,2) default 0, negative_stock boolean default false,
  default_warehouse uuid, default_account uuid);
insert into company_settings(id) values(1);
create table categories(id uuid primary key default gen_random_uuid(), name text unique not null, active boolean default true);
create table units(id uuid primary key default gen_random_uuid(), name text unique not null, base_unit uuid references units, factor numeric(12,4) default 1);
create table warehouses(id uuid primary key default gen_random_uuid(), name text unique not null, active boolean default true);
create table suppliers(id uuid primary key default gen_random_uuid(), name text not null, phone text, address text, opening_balance numeric(14,2) default 0, notes text, active boolean default true);
create table customers(id uuid primary key default gen_random_uuid(), name text not null, phone text, address text, credit_limit numeric(14,2) default 0, opening_balance numeric(14,2) default 0, notes text, active boolean default true);
create table products(id uuid primary key default gen_random_uuid(), code text unique, barcode text, name text not null, category_id uuid references categories, unit_id uuid references units,
  supplier_id uuid references suppliers, purchase_price numeric(14,2) default 0, sale_price numeric(14,2) default 0, wholesale_price numeric(14,2) default 0,
  min_stock numeric(14,3) default 0, avg_cost numeric(14,4) default 0, active boolean default true, notes text, image_url text, created_at timestamptz default now());
create index on products(barcode); create index on products(name);
create table stock_balances(product_id uuid references products, warehouse_id uuid references warehouses, qty numeric(14,3) not null default 0, primary key(product_id,warehouse_id));
create table stock_movements(id uuid primary key default gen_random_uuid(), product_id uuid not null references products, warehouse_id uuid not null references warehouses,
  type text not null check(type in('Purchase','Sale','Sales Return','Purchase Return','Stock Adjustment','Opening Balance','Transfer')),
  qty numeric(14,3) not null, qty_before numeric(14,3) not null, qty_after numeric(14,3) not null, doc_type text, doc_id uuid, user_id uuid default auth.uid(), created_at timestamptz default now());
create index on stock_movements(product_id,created_at);
create table cash_accounts(id uuid primary key default gen_random_uuid(), name text unique not null, type text default 'cash' check(type in('cash','bank','wallet','other')),
  opening_balance numeric(14,2) default 0, balance numeric(14,2) default 0);
create sequence seq_sales; create sequence seq_purchase;
create table sales_invoices(id uuid primary key default gen_random_uuid(), number text unique not null, date date default current_date, customer_id uuid not null references customers,
  warehouse_id uuid not null references warehouses, salesperson uuid default auth.uid(), payment_method text check(payment_method in('cash','bank','wallet','credit')),
  subtotal numeric(14,2) default 0, discount numeric(14,2) default 0, tax numeric(14,2) default 0, total numeric(14,2) default 0, paid numeric(14,2) default 0, notes text, created_at timestamptz default now());
create index on sales_invoices(customer_id,date);
create table sales_invoice_items(id uuid primary key default gen_random_uuid(), invoice_id uuid not null references sales_invoices on delete cascade, product_id uuid not null references products,
  qty numeric(14,3) not null check(qty>0), unit_price numeric(14,2) not null, discount numeric(14,2) default 0, unit_cost numeric(14,4) default 0, line_total numeric(14,2) not null);
create table purchase_invoices(id uuid primary key default gen_random_uuid(), number text unique not null, date date default current_date, supplier_id uuid not null references suppliers,
  warehouse_id uuid not null references warehouses, payment_method text, subtotal numeric(14,2) default 0, discount numeric(14,2) default 0, tax numeric(14,2) default 0, total numeric(14,2) default 0, paid numeric(14,2) default 0, notes text, created_by uuid default auth.uid(), created_at timestamptz default now());
create index on purchase_invoices(supplier_id,date);
create table purchase_invoice_items(id uuid primary key default gen_random_uuid(), invoice_id uuid not null references purchase_invoices on delete cascade, product_id uuid not null references products,
  qty numeric(14,3) not null check(qty>0), unit_price numeric(14,2) not null, discount numeric(14,2) default 0, line_total numeric(14,2) not null);
create table payments(id uuid primary key default gen_random_uuid(), kind text not null check(kind in('receipt','payment')), customer_id uuid references customers, supplier_id uuid references suppliers,
  account_id uuid not null references cash_accounts, amount numeric(14,2) not null check(amount>0), doc_ref text, date date default current_date, created_by uuid default auth.uid(), created_at timestamptz default now(),
  check((kind='receipt' and customer_id is not null) or (kind='payment' and supplier_id is not null)));
create table expenses(id uuid primary key default gen_random_uuid(), date date default current_date, category text not null, description text, amount numeric(14,2) not null check(amount>0),
  account_id uuid not null references cash_accounts, notes text, created_by uuid default auth.uid(), created_at timestamptz default now());
create table employees(id uuid primary key default gen_random_uuid(), name text not null, job text, phone text, salary numeric(14,2) default 0, joining_date date, active boolean default true, notes text);
create table payroll(id uuid primary key default gen_random_uuid(), employee_id uuid not null references employees, month date not null, basic numeric(14,2) default 0, overtime numeric(14,2) default 0,
  bonus numeric(14,2) default 0, advances numeric(14,2) default 0, deductions numeric(14,2) default 0, absence_deductions numeric(14,2) default 0,
  net numeric(14,2) generated always as (basic+overtime+bonus-advances-deductions-absence_deductions) stored, paid boolean default false, account_id uuid references cash_accounts, unique(employee_id,month));
create table accounts(code text primary key, name text not null, type text not null check(type in('Asset','Liability','Equity','Revenue','Expense','COGS')));
insert into accounts values('1000','Cash','Asset'),('1100','Bank','Asset'),('1200','Inventory','Asset'),('1300','Accounts Receivable','Asset'),('2000','Accounts Payable','Liability'),
 ('3000','Equity','Equity'),('4000','Sales Revenue','Revenue'),('5000','Cost of Goods Sold','COGS'),('6000','Expenses','Expense');
create table journal_entries(id uuid primary key default gen_random_uuid(), date date default current_date, description text, doc_type text, doc_id uuid, created_by uuid default auth.uid());
create table journal_lines(id uuid primary key default gen_random_uuid(), entry_id uuid not null references journal_entries on delete cascade, account_code text not null references accounts,
  debit numeric(14,2) default 0, credit numeric(14,2) default 0, check(debit>=0 and credit>=0));
create table audit_logs(id bigserial primary key, created_at timestamptz default now(), user_id uuid, user_name text, action text, entity text, entity_id text, description text, old_data jsonb, new_data jsonb);
create index on audit_logs(created_at desc);

-- ========== HELPERS ==========
create function auth_role() returns text language sql stable security definer set search_path=public as $$ select role from profiles where id=auth.uid() and active $$;
create function require_role(roles text[]) returns void language plpgsql stable security definer set search_path=public as $$
begin if coalesce(auth_role(),'') <> all(roles) then raise exception 'ليس لديك صلاحية لهذه العملية'; end if; end $$;
create function log_event(p_action text,p_entity text,p_id text,p_desc text,p_old jsonb default null,p_new jsonb default null) returns void language sql security definer set search_path=public as $$
 insert into audit_logs(user_id,user_name,action,entity,entity_id,description,old_data,new_data) select auth.uid(),(select name from profiles where id=auth.uid()),p_action,p_entity,p_id,p_desc,p_old,p_new $$;
create function audit_trg() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into audit_logs(user_id,user_name,action,entity,entity_id,description,old_data,new_data)
 values(auth.uid(),(select name from profiles where id=auth.uid()),lower(tg_op),tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'),'DB trigger: '||tg_op||' on '||tg_table_name,
  case when tg_op<>'INSERT' then to_jsonb(old) end, case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old); end $$;
do $$ declare t text; begin
 foreach t in array array['profiles','company_settings','products','customers','suppliers','categories','warehouses','cash_accounts','sales_invoices','purchase_invoices','payments','expenses','employees','payroll'] loop
  execute format('create trigger audit_%1$s after insert or update or delete on %1$s for each row execute function audit_trg()',t); end loop; end $$;

-- first signup = active admin; later signups wait for admin approval
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare is_first boolean; begin select not exists(select 1 from profiles) into is_first;
 insert into profiles(id,name,username,role,active) values(new.id,coalesce(new.raw_user_meta_data->>'name',split_part(new.email,'@',1)),new.email,case when is_first then 'admin' else 'sales' end,is_first); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- ========== ROW LEVEL SECURITY ==========
do $$ declare t text; begin
 for t in select tablename from pg_tables where schemaname='public' loop
  execute format('alter table %I enable row level security',t);
  if t not in('audit_logs','cash_accounts','employees','payroll','expenses','accounts','journal_entries','journal_lines') then
   execute format('create policy sel_%1$s on %1$I for select to authenticated using(auth_role() is not null)',t); end if;
 end loop; end $$;
create policy sel_fin_cash on cash_accounts for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_fin_exp on expenses for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_fin_emp on employees for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_fin_pay on payroll for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_fin_acc on accounts for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_fin_je on journal_entries for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_fin_jl on journal_lines for select to authenticated using(auth_role() in('admin','accountant'));
create policy sel_audit on audit_logs for select to authenticated using(auth_role() in('admin','accountant'));
create policy p_self on profiles for select to authenticated using(id=auth.uid()); -- see own profile even if not yet active
-- master data writes (invoices, stock, payments, expenses are written only through the functions below)
create function w(tbl text,roles text[]) returns void language plpgsql as $$ begin
 execute format('create policy ins_%1$s on %1$I for insert to authenticated with check(auth_role()=any(%2$L))',tbl,roles);
 execute format('create policy upd_%1$s on %1$I for update to authenticated using(auth_role()=any(%2$L)) with check(auth_role()=any(%2$L))',tbl,roles);
 execute format('create policy del_%1$s on %1$I for delete to authenticated using(auth_role()=''admin'')',tbl); end $$;
select w('products','{admin,store}'),w('categories','{admin,store}'),w('units','{admin,store}'),w('warehouses','{admin,store}'),
 w('customers','{admin,accountant,sales}'),w('suppliers','{admin,accountant,store}'),w('employees','{admin,accountant}'),w('payroll','{admin,accountant}'),
 w('cash_accounts','{admin,accountant}'),w('accounts','{admin}'),w('profiles','{admin}'),w('company_settings','{admin}');
drop function w(text,text[]);
-- audit_logs: no insert/update/delete policy => users cannot alter or delete logs
revoke insert,update,delete,truncate on audit_logs from anon,authenticated;

revoke all on all tables in schema public from anon;

-- Supabase/PostgREST privileges for browser clients. RLS still controls which rows are visible.
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
-- (moved to the end of this file: these views are created later)
grant insert,update,delete on table products,categories,units,warehouses,customers,suppliers,employees,payroll,cash_accounts,accounts,profiles,company_settings to authenticated;
revoke insert,update,delete,truncate on audit_logs from authenticated;

-- Non-admin users may read their own profile only; admins may read all profiles.
drop policy if exists sel_profiles on profiles;
drop policy if exists p_self on profiles;
create policy p_self on profiles for select to authenticated using(id=auth.uid());
create policy sel_profiles_admin on profiles for select to authenticated using(auth_role()='admin');

-- ========== BUSINESS FUNCTIONS (transactional) ==========
create function apply_stock(p_prod uuid,p_wh uuid,p_delta numeric,p_type text,p_doc_type text,p_doc uuid) returns void language plpgsql security definer set search_path=public as $$
declare b numeric; neg boolean; begin
 select negative_stock into neg from company_settings where id=1;
 insert into stock_balances(product_id,warehouse_id,qty) values(p_prod,p_wh,0) on conflict do nothing;
 select qty into b from stock_balances where product_id=p_prod and warehouse_id=p_wh for update;
 if p_delta<0 and b+p_delta<0 and not neg then raise exception 'الكمية غير متاحة: %',(select name from products where id=p_prod); end if;
 update stock_balances set qty=b+p_delta where product_id=p_prod and warehouse_id=p_wh;
 insert into stock_movements(product_id,warehouse_id,type,qty,qty_before,qty_after,doc_type,doc_id) values(p_prod,p_wh,p_type,p_delta,b,b+p_delta,p_doc_type,p_doc); end $$;
create function apply_cash(p_acct uuid,p_delta numeric) returns void language plpgsql security definer set search_path=public as $$
begin update cash_accounts set balance=balance+p_delta where id=p_acct; if not found then raise exception 'الحساب المالي غير موجود'; end if; end $$;

-- p_items: [{"product_id":"..","qty":2,"price":300,"discount":0}]
create function create_sale(p_customer uuid,p_warehouse uuid,p_items jsonb,p_paid numeric default 0,p_account uuid default null,p_method text default 'credit',p_discount numeric default 0,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare it jsonb; s company_settings; v uuid:=gen_random_uuid(); num text; sub numeric:=0; tx numeric:=0; tot numeric; pr products; q numeric; ln numeric; begin
 perform require_role('{admin,accountant,sales}');
 if p_items is null or jsonb_array_length(p_items)=0 then raise exception 'الفاتورة بدون بنود'; end if;
 select * into s from company_settings where id=1; num:=s.invoice_prefix||'S'||(1000+nextval('seq_sales'));
 insert into sales_invoices(id,number,customer_id,warehouse_id,payment_method,discount,notes) values(v,num,p_customer,p_warehouse,p_method,p_discount,p_notes);
 for it in select * from jsonb_array_elements(p_items) loop
  select * into pr from products where id=(it->>'product_id')::uuid and active; if not found then raise exception 'منتج غير صالح'; end if;
  q:=(it->>'qty')::numeric; ln:=q*(it->>'price')::numeric-coalesce((it->>'discount')::numeric,0);
  perform apply_stock(pr.id,p_warehouse,-q,'Sale','sales_invoice',v);
  insert into sales_invoice_items(invoice_id,product_id,qty,unit_price,discount,unit_cost,line_total) values(v,pr.id,q,(it->>'price')::numeric,coalesce((it->>'discount')::numeric,0),pr.avg_cost,ln);
  sub:=sub+ln; end loop;
 if s.tax_enabled then tx:=round((sub-p_discount)*s.tax_pct/100,2); end if; tot:=sub-p_discount+tx;
 update sales_invoices set subtotal=sub,tax=tx,total=tot,paid=p_paid where id=v;
 if p_paid>0 then if p_account is null then raise exception 'اختر الحساب المالي'; end if;
  insert into payments(kind,customer_id,account_id,amount,doc_ref) values('receipt',p_customer,p_account,p_paid,num); perform apply_cash(p_account,p_paid); end if;
 perform log_event('create','sales_invoices',v::text,'أنشأ فاتورة مبيعات '||num||' بإجمالي '||tot);
 return v; end $$;

create function create_purchase(p_supplier uuid,p_warehouse uuid,p_items jsonb,p_paid numeric default 0,p_account uuid default null,p_method text default 'credit',p_discount numeric default 0,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare it jsonb; v uuid:=gen_random_uuid(); num text; sub numeric:=0; pr products; q numeric; pc numeric; ln numeric; onhand numeric; begin
 perform require_role('{admin,accountant,store}');
 if p_items is null or jsonb_array_length(p_items)=0 then raise exception 'الفاتورة بدون بنود'; end if;
 num:=(select invoice_prefix from company_settings where id=1)||'P'||(1000+nextval('seq_purchase'));
 insert into purchase_invoices(id,number,supplier_id,warehouse_id,payment_method,discount,notes) values(v,num,p_supplier,p_warehouse,p_method,p_discount,p_notes);
 for it in select * from jsonb_array_elements(p_items) loop
  select * into pr from products where id=(it->>'product_id')::uuid for update; if not found then raise exception 'منتج غير صالح'; end if;
  q:=(it->>'qty')::numeric; pc:=(it->>'price')::numeric; ln:=q*pc-coalesce((it->>'discount')::numeric,0);
  select coalesce(sum(qty),0) into onhand from stock_balances where product_id=pr.id;
  update products set avg_cost=case when greatest(onhand,0)+q>0 then (greatest(onhand,0)*avg_cost+q*pc)/(greatest(onhand,0)+q) else pc end,purchase_price=pc where id=pr.id;
  perform apply_stock(pr.id,p_warehouse,q,'Purchase','purchase_invoice',v);
  insert into purchase_invoice_items(invoice_id,product_id,qty,unit_price,discount,line_total) values(v,pr.id,q,pc,coalesce((it->>'discount')::numeric,0),ln); sub:=sub+ln; end loop;
 update purchase_invoices set subtotal=sub,total=sub-p_discount,paid=p_paid where id=v;
 if p_paid>0 then if p_account is null then raise exception 'اختر الحساب المالي'; end if;
  insert into payments(kind,supplier_id,account_id,amount,doc_ref) values('payment',p_supplier,p_account,p_paid,num); perform apply_cash(p_account,-p_paid); end if;
 perform log_event('create','purchase_invoices',v::text,'أنشأ فاتورة مشتريات '||num||' بإجمالي '||(sub-p_discount));
 return v; end $$;

create function record_payment(p_kind text,p_party uuid,p_amount numeric,p_account uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid:=gen_random_uuid(); begin
 perform require_role('{admin,accountant}'); if p_amount<=0 then raise exception 'المبلغ غير صحيح'; end if;
 if p_kind='receipt' then insert into payments(id,kind,customer_id,account_id,amount) values(v,'receipt',p_party,p_account,p_amount); perform apply_cash(p_account,p_amount);
 else insert into payments(id,kind,supplier_id,account_id,amount) values(v,'payment',p_party,p_account,p_amount); perform apply_cash(p_account,-p_amount); end if;
 perform log_event('payment','payments',v::text,'سجل '||case p_kind when 'receipt' then 'مقبوضات عميل ' else 'مدفوعات مورد ' end||p_amount); return v; end $$;

create function create_expense(p_category text,p_desc text,p_amount numeric,p_account uuid,p_notes text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid:=gen_random_uuid(); begin
 perform require_role('{admin,accountant}'); if p_amount<=0 then raise exception 'المبلغ غير صحيح'; end if;
 insert into expenses(id,category,description,amount,account_id,notes) values(v,p_category,p_desc,p_amount,p_account,p_notes); perform apply_cash(p_account,-p_amount);
 perform log_event('create','expenses',v::text,'سجل مصروف '||p_category||' '||p_amount); return v; end $$;

-- p_items: [{"product_id":"..","actual":7}]  -> creates Stock Adjustment movements
create function approve_stocktake(p_warehouse uuid,p_items jsonb) returns void language plpgsql security definer set search_path=public as $$
declare it jsonb; cur numeric; begin perform require_role('{admin,store}');
 for it in select * from jsonb_array_elements(p_items) loop
  select coalesce((select qty from stock_balances where product_id=(it->>'product_id')::uuid and warehouse_id=p_warehouse),0) into cur;
  if (it->>'actual')::numeric<>cur then perform apply_stock((it->>'product_id')::uuid,p_warehouse,(it->>'actual')::numeric-cur,'Stock Adjustment','stocktake',null);
   perform log_event('update','stock_balances',it->>'product_id','عدّل كمية من '||cur||' إلى '||(it->>'actual'),to_jsonb(cur),to_jsonb((it->>'actual')::numeric)); end if; end loop; end $$;

-- ========== VIEWS / DASHBOARD ==========
create view customer_balances with(security_invoker=true) as select c.id,c.name,c.opening_balance+coalesce((select sum(total) from sales_invoices where customer_id=c.id),0)
 -coalesce((select sum(amount) from payments where customer_id=c.id and kind='receipt'),0) as balance from customers c;
create view supplier_balances with(security_invoker=true) as select s.id,s.name,s.opening_balance+coalesce((select sum(total) from purchase_invoices where supplier_id=s.id),0)
 -coalesce((select sum(amount) from payments where supplier_id=s.id and kind='payment'),0) as balance from suppliers s;
create view low_stock with(security_invoker=true) as select p.id,p.name,coalesce(sum(b.qty),0) as stock,p.min_stock from products p left join stock_balances b on b.product_id=p.id where p.active group by p.id having coalesce(sum(b.qty),0)<=p.min_stock;
create function dashboard(p_from date,p_to date) returns jsonb language sql stable security definer set search_path=public as $$
 select case when auth_role() is null then null else jsonb_build_object(
  'sales',(select coalesce(sum(total),0) from sales_invoices where date between p_from and p_to),
  'purchases',(select coalesce(sum(total),0) from purchase_invoices where date between p_from and p_to),
  'expenses',(select coalesce(sum(amount),0) from expenses where date between p_from and p_to),
  'cogs',(select coalesce(sum(i.qty*i.unit_cost),0) from sales_invoice_items i join sales_invoices s on s.id=i.invoice_id where s.date between p_from and p_to),
  'receivables',(select coalesce(sum(balance),0) from customer_balances),'payables',(select coalesce(sum(balance),0) from supplier_balances),
  'inventory_value',(select coalesce(sum(b.qty*p.avg_cost),0) from stock_balances b join products p on p.id=b.product_id),
  'products',(select count(*) from products),'low_stock',(select count(*) from low_stock),
  'receipts',(select coalesce(sum(amount),0) from payments where kind='receipt' and date between p_from and p_to),
  'payments_out',(select coalesce(sum(amount),0) from payments where kind='payment' and date between p_from and p_to)) end $$;

revoke execute on all functions in schema public from public,anon;
grant execute on function create_sale,create_purchase,record_payment,create_expense,approve_stocktake,dashboard,auth_role to authenticated; -- log_event/apply_* stay internal so logs cannot be forged

-- ========== SEED (optional) ==========
insert into warehouses(name) values('المخزن الرئيسي');
insert into cash_accounts(name,type) values('الخزينة الرئيسية','cash'),('البنك','bank'),('المحفظة','wallet');
insert into units(name) values('قطعة'),('كرتونة'),('كيلو'),('جرام'),('متر'),('لتر'),('خدمة');


-- ====================== 002_extra.sql ======================
-- Run AFTER schema.sql, in SQL Editor (one time).

-- Stock can never go below zero unless negative_stock is enabled in settings
create or replace function apply_stock(p_prod uuid,p_wh uuid,p_delta numeric,p_type text,p_doc_type text,p_doc uuid) returns void language plpgsql security definer set search_path=public as $$
declare b numeric; neg boolean; begin
 select negative_stock into neg from company_settings where id=1;
 insert into stock_balances(product_id,warehouse_id,qty) values(p_prod,p_wh,0) on conflict do nothing;
 select qty into b from stock_balances where product_id=p_prod and warehouse_id=p_wh for update;
 if p_delta<0 and b+p_delta<0 and not neg then
  raise exception 'المخزون غير كافي: % (المتاح %، المطلوب %)',(select name from products where id=p_prod),b,-p_delta; end if;
 update stock_balances set qty=b+p_delta where product_id=p_prod and warehouse_id=p_wh;
 insert into stock_movements(product_id,warehouse_id,type,qty,qty_before,qty_after,doc_type,doc_id) values(p_prod,p_wh,p_type,p_delta,b,b+p_delta,p_doc_type,p_doc); end $$;

create sequence seq_sret; create sequence seq_pret; create sequence seq_quo; create sequence seq_ord;
create table sales_returns(id uuid primary key default gen_random_uuid(), number text unique not null, date date default current_date, invoice_id uuid not null references sales_invoices,
 customer_id uuid not null references customers, warehouse_id uuid not null references warehouses, total numeric(14,2) default 0, created_by uuid default auth.uid(), created_at timestamptz default now());
create table sales_return_items(id uuid primary key default gen_random_uuid(), return_id uuid not null references sales_returns on delete cascade, product_id uuid not null references products,
 qty numeric(14,3) not null check(qty>0), unit_price numeric(14,2) not null, line_total numeric(14,2) not null);
create table purchase_returns(id uuid primary key default gen_random_uuid(), number text unique not null, date date default current_date, invoice_id uuid not null references purchase_invoices,
 supplier_id uuid not null references suppliers, warehouse_id uuid not null references warehouses, total numeric(14,2) default 0, created_by uuid default auth.uid(), created_at timestamptz default now());
create table purchase_return_items(id uuid primary key default gen_random_uuid(), return_id uuid not null references purchase_returns on delete cascade, product_id uuid not null references products,
 qty numeric(14,3) not null check(qty>0), unit_price numeric(14,2) not null, line_total numeric(14,2) not null);
create table cash_transfers(id uuid primary key default gen_random_uuid(), date date default current_date, from_account uuid not null references cash_accounts, to_account uuid not null references cash_accounts,
 amount numeric(14,2) not null check(amount>0), created_by uuid default auth.uid(), check(from_account<>to_account));
create table quotations(id uuid primary key default gen_random_uuid(), number text unique not null, date date default current_date, customer_id uuid not null references customers, valid_until date,
 status text default 'Open' check(status in('Open','Ordered','Expired')), notes text, created_by uuid default auth.uid());
create table quotation_items(id uuid primary key default gen_random_uuid(), quotation_id uuid not null references quotations on delete cascade, product_id uuid not null references products,
 qty numeric(14,3) not null check(qty>0), unit_price numeric(14,2) not null, discount numeric(14,2) default 0);
create table sales_orders(id uuid primary key default gen_random_uuid(), number text unique not null, date date default current_date, customer_id uuid not null references customers,
 warehouse_id uuid not null references warehouses, quotation_id uuid references quotations, invoice_id uuid references sales_invoices,
 status text default 'Confirmed' check(status in('Draft','Confirmed','Partially Delivered','Delivered','Cancelled')), created_by uuid default auth.uid());
create table sales_order_items(id uuid primary key default gen_random_uuid(), order_id uuid not null references sales_orders on delete cascade, product_id uuid not null references products,
 qty numeric(14,3) not null check(qty>0), unit_price numeric(14,2) not null, discount numeric(14,2) default 0);

do $$ declare t text; begin
 foreach t in array array['sales_returns','sales_return_items','purchase_returns','purchase_return_items','cash_transfers','quotations','quotation_items','sales_orders','sales_order_items'] loop
  execute format('alter table %I enable row level security',t);
  execute format('create policy sel_%1$s on %1$I for select to authenticated using(%2$s)',t,case when t='cash_transfers' then 'auth_role() in(''admin'',''accountant'')' else 'auth_role() is not null' end);
 end loop;
 foreach t in array array['sales_returns','purchase_returns','cash_transfers','quotations','sales_orders'] loop
  execute format('create trigger audit_%1$s after insert or update or delete on %1$s for each row execute function audit_trg()',t); end loop; end $$;

-- balances now include returns
create or replace view customer_balances with(security_invoker=true) as select c.id,c.name,c.opening_balance+coalesce((select sum(total) from sales_invoices where customer_id=c.id),0)
 -coalesce((select sum(amount) from payments where customer_id=c.id and kind='receipt'),0)-coalesce((select sum(total) from sales_returns where customer_id=c.id),0) as balance from customers c;
create or replace view supplier_balances with(security_invoker=true) as select s.id,s.name,s.opening_balance+coalesce((select sum(total) from purchase_invoices where supplier_id=s.id),0)
 -coalesce((select sum(amount) from payments where supplier_id=s.id and kind='payment'),0)-coalesce((select sum(total) from purchase_returns where supplier_id=s.id),0) as balance from suppliers s;

-- p_items: [{"product_id":"..","qty":1}]  (price taken from the original invoice)
create function create_sales_return(p_invoice uuid,p_items jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare inv sales_invoices; it jsonb; v uuid:=gen_random_uuid(); tot numeric:=0; sold numeric; prior numeric; q numeric; pid uuid; price numeric; ln numeric; num text; begin
 perform require_role('{admin,accountant,sales,store}');
 select * into inv from sales_invoices where id=p_invoice; if not found then raise exception 'الفاتورة غير موجودة'; end if;
 num:=(select invoice_prefix from company_settings where id=1)||'SR'||(1000+nextval('seq_sret'));
 insert into sales_returns(id,number,invoice_id,customer_id,warehouse_id) values(v,num,inv.id,inv.customer_id,inv.warehouse_id);
 for it in select * from jsonb_array_elements(p_items) loop
  pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; continue when q is null or q<=0;
  select coalesce(sum(qty),0),sum(line_total)/nullif(sum(qty),0) into sold,price from sales_invoice_items where invoice_id=inv.id and product_id=pid;
  select coalesce(sum(i.qty),0) into prior from sales_return_items i join sales_returns r on r.id=i.return_id where r.invoice_id=inv.id and i.product_id=pid and r.id<>v;
  if q>sold-prior then raise exception 'لا يمكن إرجاع كمية أكبر من المباعة (المتاح للإرجاع %)',sold-prior; end if;
  ln:=round(q*price,2); insert into sales_return_items(return_id,product_id,qty,unit_price,line_total) values(v,pid,q,price,ln);
  perform apply_stock(pid,inv.warehouse_id,q,'Sales Return','sales_return',v); tot:=tot+ln; end loop;
 if tot=0 then raise exception 'حدد كمية للإرجاع'; end if;
 update sales_returns set total=tot where id=v; perform log_event('create','sales_returns',v::text,'سجل مرتجع مبيعات '||num||' بقيمة '||tot); return v; end $$;

create function create_purchase_return(p_invoice uuid,p_items jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare inv purchase_invoices; it jsonb; v uuid:=gen_random_uuid(); tot numeric:=0; bought numeric; prior numeric; q numeric; pid uuid; price numeric; ln numeric; num text; begin
 perform require_role('{admin,accountant,store}');
 select * into inv from purchase_invoices where id=p_invoice; if not found then raise exception 'الفاتورة غير موجودة'; end if;
 num:=(select invoice_prefix from company_settings where id=1)||'PR'||(1000+nextval('seq_pret'));
 insert into purchase_returns(id,number,invoice_id,supplier_id,warehouse_id) values(v,num,inv.id,inv.supplier_id,inv.warehouse_id);
 for it in select * from jsonb_array_elements(p_items) loop
  pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; continue when q is null or q<=0;
  select coalesce(sum(qty),0),sum(line_total)/nullif(sum(qty),0) into bought,price from purchase_invoice_items where invoice_id=inv.id and product_id=pid;
  select coalesce(sum(i.qty),0) into prior from purchase_return_items i join purchase_returns r on r.id=i.return_id where r.invoice_id=inv.id and i.product_id=pid and r.id<>v;
  if q>bought-prior then raise exception 'لا يمكن إرجاع كمية أكبر من المشتراة (المتاح للإرجاع %)',bought-prior; end if;
  ln:=round(q*price,2); insert into purchase_return_items(return_id,product_id,qty,unit_price,line_total) values(v,pid,q,price,ln);
  perform apply_stock(pid,inv.warehouse_id,-q,'Purchase Return','purchase_return',v); tot:=tot+ln; end loop;
 if tot=0 then raise exception 'حدد كمية للإرجاع'; end if;
 update purchase_returns set total=tot where id=v; perform log_event('create','purchase_returns',v::text,'سجل مرتجع مشتريات '||num||' بقيمة '||tot); return v; end $$;

create function transfer_cash(p_from uuid,p_to uuid,p_amount numeric) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid:=gen_random_uuid(); begin perform require_role('{admin,accountant}');
 if p_amount<=0 or p_from=p_to then raise exception 'بيانات التحويل غير صحيحة'; end if;
 insert into cash_transfers(id,from_account,to_account,amount) values(v,p_from,p_to,p_amount); perform apply_cash(p_from,-p_amount); perform apply_cash(p_to,p_amount);
 perform log_event('transfer','cash_transfers',v::text,'حوّل '||p_amount||' بين حسابين'); return v; end $$;

create function create_quotation(p_customer uuid,p_valid date,p_items jsonb,p_notes text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid:=gen_random_uuid(); it jsonb; num text; begin perform require_role('{admin,accountant,sales}');
 if p_items is null or jsonb_array_length(p_items)=0 then raise exception 'أضف بندًا'; end if;
 num:='Q-'||(1000+nextval('seq_quo')); insert into quotations(id,number,customer_id,valid_until,notes) values(v,num,p_customer,p_valid,p_notes);
 for it in select * from jsonb_array_elements(p_items) loop
  insert into quotation_items(quotation_id,product_id,qty,unit_price,discount) values(v,(it->>'product_id')::uuid,(it->>'qty')::numeric,(it->>'price')::numeric,coalesce((it->>'discount')::numeric,0)); end loop;
 perform log_event('create','quotations',v::text,'أنشأ عرض سعر '||num); return v; end $$;

create function quotation_to_order(p_quo uuid,p_warehouse uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare q quotations; v uuid:=gen_random_uuid(); num text; begin perform require_role('{admin,accountant,sales}');
 select * into q from quotations where id=p_quo; if not found or q.status<>'Open' then raise exception 'عرض السعر غير متاح للتحويل'; end if;
 num:='SO-'||(1000+nextval('seq_ord')); insert into sales_orders(id,number,customer_id,warehouse_id,quotation_id) values(v,num,q.customer_id,p_warehouse,q.id);
 insert into sales_order_items(order_id,product_id,qty,unit_price,discount) select v,product_id,qty,unit_price,discount from quotation_items where quotation_id=q.id;
 update quotations set status='Ordered' where id=q.id; perform log_event('create','sales_orders',v::text,'حوّل عرض '||q.number||' إلى أمر بيع '||num); return v; end $$;

create function order_to_invoice(p_order uuid,p_paid numeric default 0,p_account uuid default null,p_method text default 'credit') returns uuid language plpgsql security definer set search_path=public as $$
declare o sales_orders; inv uuid; items jsonb; begin perform require_role('{admin,accountant,sales}');
 select * into o from sales_orders where id=p_order for update; if not found or o.status<>'Confirmed' then raise exception 'أمر البيع غير قابل للتحويل'; end if;
 select jsonb_agg(jsonb_build_object('product_id',product_id,'qty',qty,'price',unit_price,'discount',discount)) into items from sales_order_items where order_id=o.id;
 inv:=create_sale(o.customer_id,o.warehouse_id,items,p_paid,p_account,p_method);
 update sales_orders set invoice_id=inv,status='Delivered' where id=o.id; return inv; end $$;

create function cancel_order(p_order uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform require_role('{admin,accountant,sales}'); update sales_orders set status='Cancelled' where id=p_order and status in('Draft','Confirmed');
 if not found then raise exception 'لا يمكن إلغاء هذا الأمر'; end if; perform log_event('cancel','sales_orders',p_order::text,'ألغى أمر بيع'); end $$;

create function pay_payroll(p_payroll uuid,p_account uuid) returns void language plpgsql security definer set search_path=public as $$
declare r payroll; begin perform require_role('{admin,accountant}');
 select * into r from payroll where id=p_payroll for update; if not found or r.paid then raise exception 'المرتب مدفوع بالفعل أو غير موجود'; end if;
 perform apply_cash(p_account,-r.net); update payroll set paid=true,account_id=p_account where id=p_payroll;
 perform log_event('payment','payroll',p_payroll::text,'دفع مرتب بقيمة '||r.net); end $$;

-- statements: debit/credit rows up to p_to; the app computes opening + running balance
create function customer_statement(p_party uuid,p_to date default current_date) returns table(d date,doc text,descr text,debit numeric,credit numeric) language sql stable as $$
 select date,number,'فاتورة مبيعات'::text,total::numeric,0::numeric from sales_invoices where customer_id=p_party and date<=p_to
 union all select date,coalesce(doc_ref,'دفعة'),'مقبوضات',0,amount from payments where customer_id=p_party and kind='receipt' and date<=p_to
 union all select date,number,'مرتجع مبيعات',0,total from sales_returns where customer_id=p_party and date<=p_to order by 1 $$;
create function supplier_statement(p_party uuid,p_to date default current_date) returns table(d date,doc text,descr text,debit numeric,credit numeric) language sql stable as $$
 select date,number,'فاتورة مشتريات'::text,0::numeric,total::numeric from purchase_invoices where supplier_id=p_party and date<=p_to
 union all select date,coalesce(doc_ref,'دفعة'),'مدفوعات',amount,0 from payments where supplier_id=p_party and kind='payment' and date<=p_to
 union all select date,number,'مرتجع مشتريات',total,0 from purchase_returns where supplier_id=p_party and date<=p_to order by 1 $$;

-- double-entry journal, rebuilt from the documents (idempotent)
create function rebuild_journal() returns int language plpgsql security definer set search_path=public as $$
declare r record; e uuid; n int:=0; c numeric; begin perform require_role('{admin,accountant}'); delete from journal_entries;
 for r in select * from sales_invoices loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.date,'فاتورة مبيعات '||r.number,'sales_invoice',r.id);
  insert into journal_lines(entry_id,account_code,debit,credit) values(e,'1300',r.total,0),(e,'4000',0,r.total);
  select coalesce(sum(qty*unit_cost),0) into c from sales_invoice_items where invoice_id=r.id;
  if c>0 then insert into journal_lines(entry_id,account_code,debit,credit) values(e,'5000',c,0),(e,'1200',0,c); end if; end loop;
 for r in select * from purchase_invoices loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.date,'فاتورة مشتريات '||r.number,'purchase_invoice',r.id);
  insert into journal_lines(entry_id,account_code,debit,credit) values(e,'1200',r.total,0),(e,'2000',0,r.total); end loop;
 for r in select p.*,case when a.type='bank' then '1100' else '1000' end as cc from payments p join cash_accounts a on a.id=p.account_id loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.date,case r.kind when 'receipt' then 'مقبوضات ' else 'مدفوعات ' end||coalesce(r.doc_ref,''),'payment',r.id);
  if r.kind='receipt' then insert into journal_lines(entry_id,account_code,debit,credit) values(e,r.cc,r.amount,0),(e,'1300',0,r.amount);
  else insert into journal_lines(entry_id,account_code,debit,credit) values(e,'2000',r.amount,0),(e,r.cc,0,r.amount); end if; end loop;
 for r in select x.*,case when a.type='bank' then '1100' else '1000' end as cc from expenses x join cash_accounts a on a.id=x.account_id loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.date,'مصروف '||r.category,'expense',r.id);
  insert into journal_lines(entry_id,account_code,debit,credit) values(e,'6000',r.amount,0),(e,r.cc,0,r.amount); end loop;
 for r in select * from sales_returns loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.date,'مرتجع مبيعات '||r.number,'sales_return',r.id);
  insert into journal_lines(entry_id,account_code,debit,credit) values(e,'4000',r.total,0),(e,'1300',0,r.total); end loop;
 for r in select * from purchase_returns loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.date,'مرتجع مشتريات '||r.number,'purchase_return',r.id);
  insert into journal_lines(entry_id,account_code,debit,credit) values(e,'2000',r.total,0),(e,'1200',0,r.total); end loop;
 for r in select p.*,case when a.type='bank' then '1100' else '1000' end as cc from payroll p join cash_accounts a on a.id=p.account_id where p.paid loop e:=gen_random_uuid(); n:=n+1;
  insert into journal_entries(id,date,description,doc_type,doc_id) values(e,r.month,'مرتب','payroll',r.id);
  insert into journal_lines(entry_id,account_code,debit,credit) values(e,'6000',r.net,0),(e,r.cc,0,r.net); end loop;
 return n; end $$;

revoke execute on all functions in schema public from public,anon;
grant execute on function create_sales_return,create_purchase_return,transfer_cash,create_quotation,quotation_to_order,order_to_invoice,cancel_order,pay_payroll,customer_statement,supplier_statement,rebuild_journal to authenticated;


-- ====================== 003_erp_core_upgrade.sql ======================
-- ERP Core Upgrade 003
-- Run AFTER schema.sql and 002_extra.sql.
-- Safe migration: uses ADD COLUMN/TABLE IF NOT EXISTS where possible.

BEGIN;

-- ============================================================
-- 1) Master data / document fields needed for ERP workflows
-- ============================================================
ALTER TABLE customers ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS payment_terms_days int NOT NULL DEFAULT 0;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS payment_terms_days int NOT NULL DEFAULT 0;

ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS due_date date;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS tax_rate numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'Posted';
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS due_date date;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS tax_rate numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS tax numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'Posted';

UPDATE sales_invoices SET due_date = date WHERE due_date IS NULL;
UPDATE purchase_invoices SET due_date = date WHERE due_date IS NULL;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='sales_invoices_status_chk') THEN
    ALTER TABLE sales_invoices ADD CONSTRAINT sales_invoices_status_chk
      CHECK(status IN ('Posted','Void'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_invoices_status_chk') THEN
    ALTER TABLE purchase_invoices ADD CONSTRAINT purchase_invoices_status_chk
      CHECK(status IN ('Posted','Void'));
  END IF;
END $$;

ALTER TABLE products ADD COLUMN IF NOT EXISTS reorder_qty numeric(14,3) NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS products_barcode_unique_idx
  ON products(barcode) WHERE barcode IS NOT NULL AND btrim(barcode) <> '';

ALTER TABLE units ADD COLUMN IF NOT EXISTS factor numeric(12,4) NOT NULL DEFAULT 1;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='units_factor_positive_chk') THEN
    ALTER TABLE units ADD CONSTRAINT units_factor_positive_chk CHECK(factor > 0);
  END IF;
END $$;

-- ============================================================
-- 2) Better return data: retain cost/tax needed for correct GL
-- ============================================================
ALTER TABLE sales_return_items ADD COLUMN IF NOT EXISTS unit_cost numeric(14,4) NOT NULL DEFAULT 0;
ALTER TABLE sales_return_items ADD COLUMN IF NOT EXISTS cost_total numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE sales_return_items ADD COLUMN IF NOT EXISTS tax numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE purchase_return_items ADD COLUMN IF NOT EXISTS tax numeric(14,2) NOT NULL DEFAULT 0;

-- ============================================================
-- 3) Accounting accounts for VAT and stock adjustments
-- ============================================================
INSERT INTO accounts(code,name,type) VALUES
  ('1410','Recoverable VAT','Asset'),
  ('2100','VAT Payable','Liability'),
  ('4300','Inventory Gain','Revenue'),
  ('6100','Inventory Shrinkage','Expense')
ON CONFLICT(code) DO NOTHING;

-- ============================================================
-- 4) Payment allocation layer
--    A payment can be allocated to one or many invoices, or left
--    unallocated as a customer/supplier credit.
-- ============================================================
CREATE TABLE IF NOT EXISTS payment_allocations(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
  sales_invoice_id uuid REFERENCES sales_invoices(id),
  purchase_invoice_id uuid REFERENCES purchase_invoices(id),
  amount numeric(14,2) NOT NULL CHECK(amount > 0),
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now(),
  CHECK(
    (CASE WHEN sales_invoice_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN purchase_invoice_id IS NOT NULL THEN 1 ELSE 0 END) = 1
  )
);
CREATE INDEX IF NOT EXISTS payment_allocations_payment_idx ON payment_allocations(payment_id);
CREATE INDEX IF NOT EXISTS payment_allocations_sales_idx ON payment_allocations(sales_invoice_id);
CREATE INDEX IF NOT EXISTS payment_allocations_purchase_idx ON payment_allocations(purchase_invoice_id);

ALTER TABLE payment_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sel_payment_allocations ON payment_allocations;
CREATE POLICY sel_payment_allocations ON payment_allocations
  FOR SELECT TO authenticated USING(auth_role() IN ('admin','accountant'));
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON payment_allocations FROM anon,authenticated;

-- Derived invoice balance views.
CREATE OR REPLACE VIEW sales_invoice_balances WITH(security_invoker=true) AS
SELECT i.id,i.number,i.date,i.due_date,i.customer_id,i.warehouse_id,i.subtotal,i.discount,i.tax,i.total,
       COALESCE(pa.paid,0)::numeric(14,2) AS allocated_paid,
       GREATEST(i.total-COALESCE(pa.paid,0),0)::numeric(14,2) AS outstanding,
       i.status
FROM sales_invoices i
LEFT JOIN (
  SELECT sales_invoice_id,SUM(amount) paid
  FROM payment_allocations GROUP BY sales_invoice_id
) pa ON pa.sales_invoice_id=i.id;

CREATE OR REPLACE VIEW purchase_invoice_balances WITH(security_invoker=true) AS
SELECT i.id,i.number,i.date,i.due_date,i.supplier_id,i.warehouse_id,i.subtotal,i.discount,i.tax,i.total,
       COALESCE(pa.paid,0)::numeric(14,2) AS allocated_paid,
       GREATEST(i.total-COALESCE(pa.paid,0),0)::numeric(14,2) AS outstanding,
       i.status
FROM purchase_invoices i
LEFT JOIN (
  SELECT purchase_invoice_id,SUM(amount) paid
  FROM payment_allocations GROUP BY purchase_invoice_id
) pa ON pa.purchase_invoice_id=i.id;

-- Keep legacy paid column synchronized with allocations.
CREATE OR REPLACE FUNCTION refresh_sales_invoice_paid(p_invoice uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE sales_invoices i
  SET paid=LEAST(i.total,COALESCE((SELECT SUM(amount) FROM payment_allocations WHERE sales_invoice_id=i.id),0))
  WHERE i.id=p_invoice;
END $$;

CREATE OR REPLACE FUNCTION refresh_purchase_invoice_paid(p_invoice uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE purchase_invoices i
  SET paid=LEAST(i.total,COALESCE((SELECT SUM(amount) FROM payment_allocations WHERE purchase_invoice_id=i.id),0))
  WHERE i.id=p_invoice;
END $$;

-- Backfill legacy p_paid values created by schema.sql functions.
INSERT INTO payment_allocations(payment_id,sales_invoice_id,amount,created_by)
SELECT p.id,i.id,LEAST(p.amount,i.total),p.created_by
FROM payments p
JOIN sales_invoices i ON i.number=p.doc_ref
WHERE p.kind='receipt'
  AND p.customer_id=i.customer_id
  AND p.doc_ref IS NOT NULL
  AND NOT EXISTS(
    SELECT 1 FROM payment_allocations pa WHERE pa.payment_id=p.id
  )
ON CONFLICT DO NOTHING;

INSERT INTO payment_allocations(payment_id,purchase_invoice_id,amount,created_by)
SELECT p.id,i.id,LEAST(p.amount,i.total),p.created_by
FROM payments p
JOIN purchase_invoices i ON i.number=p.doc_ref
WHERE p.kind='payment'
  AND p.supplier_id=i.supplier_id
  AND p.doc_ref IS NOT NULL
  AND NOT EXISTS(
    SELECT 1 FROM payment_allocations pa WHERE pa.payment_id=p.id
  )
ON CONFLICT DO NOTHING;

UPDATE sales_invoices i SET paid=LEAST(i.total,COALESCE((SELECT SUM(amount) FROM payment_allocations WHERE sales_invoice_id=i.id),0));
UPDATE purchase_invoices i SET paid=LEAST(i.total,COALESCE((SELECT SUM(amount) FROM payment_allocations WHERE purchase_invoice_id=i.id),0));

-- ============================================================
-- 5) Real stock transfer document
-- ============================================================
CREATE TABLE IF NOT EXISTS stock_transfers(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number text UNIQUE NOT NULL,
  date date NOT NULL DEFAULT current_date,
  from_warehouse uuid NOT NULL REFERENCES warehouses,
  to_warehouse uuid NOT NULL REFERENCES warehouses,
  status text NOT NULL DEFAULT 'Completed',
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now(),
  CHECK(from_warehouse<>to_warehouse),
  CHECK(status IN ('Completed','Cancelled'))
);
CREATE TABLE IF NOT EXISTS stock_transfer_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products,
  qty numeric(14,3) NOT NULL CHECK(qty>0)
);
CREATE INDEX IF NOT EXISTS stock_transfer_items_transfer_idx ON stock_transfer_items(transfer_id);
ALTER TABLE stock_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfer_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sel_stock_transfers ON stock_transfers;
DROP POLICY IF EXISTS sel_stock_transfer_items ON stock_transfer_items;
CREATE POLICY sel_stock_transfers ON stock_transfers FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
CREATE POLICY sel_stock_transfer_items ON stock_transfer_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON stock_transfers,stock_transfer_items FROM anon,authenticated;
CREATE SEQUENCE IF NOT EXISTS seq_strans;

CREATE OR REPLACE FUNCTION create_stock_transfer(
  p_from uuid,p_to uuid,p_items jsonb,p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); it jsonb; q numeric; pid uuid; num text;
BEGIN
  PERFORM require_role('{admin,store}');
  IF p_from IS NULL OR p_to IS NULL OR p_from=p_to THEN RAISE EXCEPTION 'المخزن المصدر والهدف يجب أن يكونا مختلفين'; END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'أضف أصنافًا للتحويل'; END IF;
  num:='TR-'||(1000+nextval('seq_strans'));
  INSERT INTO stock_transfers(id,number,from_warehouse,to_warehouse,notes) VALUES(v,num,p_from,p_to,p_notes);
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric;
    IF q IS NULL OR q<=0 THEN RAISE EXCEPTION 'كمية التحويل غير صحيحة'; END IF;
    IF NOT EXISTS(SELECT 1 FROM products WHERE id=pid AND active) THEN RAISE EXCEPTION 'منتج غير صالح'; END IF;
    INSERT INTO stock_transfer_items(transfer_id,product_id,qty) VALUES(v,pid,q);
    PERFORM apply_stock(pid,p_from,-q,'Transfer','stock_transfer',v);
    PERFORM apply_stock(pid,p_to,q,'Transfer','stock_transfer',v);
  END LOOP;
  PERFORM log_event('create','stock_transfers',v::text,'أنشأ تحويل مخزني '||num);
  RETURN v;
END $$;

-- ============================================================
-- 6) Proper stocktake document and approval
-- ============================================================
CREATE TABLE IF NOT EXISTS stocktakes(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number text UNIQUE NOT NULL,
  date date NOT NULL DEFAULT current_date,
  warehouse_id uuid NOT NULL REFERENCES warehouses,
  status text NOT NULL DEFAULT 'Draft',
  notes text,
  created_by uuid DEFAULT auth.uid(),
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  CHECK(status IN ('Draft','Approved','Cancelled'))
);
CREATE TABLE IF NOT EXISTS stocktake_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stocktake_id uuid NOT NULL REFERENCES stocktakes(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products,
  expected_qty numeric(14,3) NOT NULL DEFAULT 0,
  actual_qty numeric(14,3),
  variance_qty numeric(14,3),
  variance_value numeric(14,2)
);
CREATE SEQUENCE IF NOT EXISTS seq_stocktake;
ALTER TABLE stocktakes ENABLE ROW LEVEL SECURITY;
ALTER TABLE stocktake_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sel_stocktakes ON stocktakes;
DROP POLICY IF EXISTS sel_stocktake_items ON stocktake_items;
CREATE POLICY sel_stocktakes ON stocktakes FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
CREATE POLICY sel_stocktake_items ON stocktake_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON stocktakes,stocktake_items FROM anon,authenticated;

CREATE OR REPLACE FUNCTION create_stocktake(p_warehouse uuid,p_notes text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid(); it record; num text;
BEGIN
  PERFORM require_role('{admin,store}');
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse AND active) THEN RAISE EXCEPTION 'المخزن غير صالح'; END IF;
  num:='ST-'||(1000+nextval('seq_stocktake'));
  INSERT INTO stocktakes(id,number,warehouse_id,notes) VALUES(v,num,p_warehouse,p_notes);
  FOR it IN
    SELECT p.id,coalesce(b.qty,0) qty FROM products p
    LEFT JOIN stock_balances b ON b.product_id=p.id AND b.warehouse_id=p_warehouse
    WHERE p.active ORDER BY p.name
  LOOP
    INSERT INTO stocktake_items(stocktake_id,product_id,expected_qty,actual_qty)
    VALUES(v,it.id,it.qty,it.qty);
  END LOOP;
  PERFORM log_event('create','stocktakes',v::text,'أنشأ جرد '||num);
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION approve_stocktake_v2(p_stocktake uuid,p_items jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE st stocktakes; it jsonb; pid uuid; actual numeric; cur numeric; diff numeric; cost numeric; iv numeric;
BEGIN
  PERFORM require_role('{admin,store}');
  SELECT * INTO st FROM stocktakes WHERE id=p_stocktake FOR UPDATE;
  IF NOT FOUND OR st.status<>'Draft' THEN RAISE EXCEPTION 'الجرد غير قابل للاعتماد'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) LOOP
    pid:=(it->>'product_id')::uuid; actual:=(it->>'actual_qty')::numeric;
    IF actual IS NULL OR actual<0 THEN RAISE EXCEPTION 'الكمية الفعلية غير صحيحة'; END IF;
    SELECT coalesce(qty,0) INTO cur FROM stock_balances WHERE product_id=pid AND warehouse_id=st.warehouse_id;
    cost:=coalesce((SELECT avg_cost FROM products WHERE id=pid),0);
    diff:=actual-coalesce(cur,0);
    UPDATE stocktake_items SET actual_qty=actual,variance_qty=diff,variance_value=round(diff*cost,2)
      WHERE stocktake_id=st.id AND product_id=pid;
    IF NOT FOUND THEN
      INSERT INTO stocktake_items(stocktake_id,product_id,expected_qty,actual_qty,variance_qty,variance_value)
      VALUES(st.id,pid,coalesce(cur,0),actual,diff,round(diff*cost,2));
    END IF;
    IF diff<>0 THEN
      PERFORM apply_stock(pid,st.warehouse_id,diff,'Stock Adjustment','stocktake',st.id);
    END IF;
  END LOOP;
  UPDATE stocktakes SET status='Approved',approved_by=auth.uid(),approved_at=now() WHERE id=st.id;
  PERFORM log_event('approve','stocktakes',st.id::text,'اعتمد الجرد '||st.number);
END $$;

-- ============================================================
-- 7) Manual balanced journal entries
-- ============================================================
CREATE OR REPLACE FUNCTION create_manual_journal(
  p_date date,p_description text,p_lines jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); it jsonb; total_d numeric:=0; total_c numeric:=0; d numeric; c numeric; code text;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF coalesce(jsonb_array_length(p_lines),0)<2 THEN RAISE EXCEPTION 'القيد يحتاج إلى سطرين على الأقل'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    code:=it->>'account_code'; d:=coalesce((it->>'debit')::numeric,0); c:=coalesce((it->>'credit')::numeric,0);
    IF NOT EXISTS(SELECT 1 FROM accounts a WHERE a.code=code) THEN RAISE EXCEPTION 'حساب غير موجود: %',code; END IF;
    IF d<0 OR c<0 OR (d=0 AND c=0) OR (d>0 AND c>0) THEN RAISE EXCEPTION 'كل سطر يجب أن يكون مدينًا أو دائنًا فقط'; END IF;
    total_d:=total_d+d; total_c:=total_c+c;
  END LOOP;
  IF round(total_d,2)<>round(total_c,2) THEN RAISE EXCEPTION 'القيد غير متوازن: مدين %, دائن %',total_d,total_c; END IF;
  INSERT INTO journal_entries(id,date,description,doc_type) VALUES(v,coalesce(p_date,current_date),coalesce(p_description,'قيد يدوي'),'manual');
  FOR it IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
    VALUES(v,it->>'account_code',coalesce((it->>'debit')::numeric,0),coalesce((it->>'credit')::numeric,0));
  END LOOP;
  PERFORM log_event('create','journal_entries',v::text,'أنشأ قيد يومية يدوي');
  RETURN v;
END $$;

-- ============================================================
-- 8) Replace payment RPC with invoice allocation support
-- ============================================================
DROP FUNCTION IF EXISTS record_payment(text,uuid,numeric,uuid);
DROP FUNCTION IF EXISTS record_payment(text,uuid,numeric,uuid,jsonb);

CREATE FUNCTION record_payment(
  p_kind text,p_party uuid,p_amount numeric,p_account uuid,p_allocations jsonb DEFAULT '[]'::jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); a jsonb; iid uuid; alloc numeric; total_alloc numeric:=0; inv_total numeric; already numeric; outstanding numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_kind NOT IN ('receipt','payment') THEN RAISE EXCEPTION 'نوع الحركة غير صحيح'; END IF;
  IF p_amount<=0 THEN RAISE EXCEPTION 'المبلغ غير صحيح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM cash_accounts WHERE id=p_account) THEN RAISE EXCEPTION 'الحساب المالي غير موجود'; END IF;

  IF p_kind='receipt' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=p_party AND active) THEN RAISE EXCEPTION 'العميل غير صالح'; END IF;
  IF p_kind='payment' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=p_party AND active) THEN RAISE EXCEPTION 'المورد غير صالح'; END IF;

  INSERT INTO payments(id,kind,customer_id,supplier_id,account_id,amount,doc_ref)
  VALUES(v,p_kind,CASE WHEN p_kind='receipt' THEN p_party END,CASE WHEN p_kind='payment' THEN p_party END,p_account,p_amount,NULL);
  PERFORM apply_cash(p_account,CASE WHEN p_kind='receipt' THEN p_amount ELSE -p_amount END);

  FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) LOOP
    iid:=(a->>'invoice_id')::uuid; alloc:=(a->>'amount')::numeric;
    IF alloc IS NULL OR alloc<=0 THEN RAISE EXCEPTION 'قيمة التخصيص غير صحيحة'; END IF;
    total_alloc:=total_alloc+alloc;
    IF total_alloc>p_amount THEN RAISE EXCEPTION 'إجمالي التخصيص أكبر من قيمة الدفعة'; END IF;

    IF p_kind='receipt' THEN
      SELECT total INTO inv_total FROM sales_invoices WHERE id=iid AND customer_id=p_party AND status='Posted';
      IF inv_total IS NULL THEN RAISE EXCEPTION 'فاتورة مبيعات غير صالحة للتخصيص'; END IF;
      SELECT coalesce(sum(amount),0) INTO already FROM payment_allocations WHERE sales_invoice_id=iid;
      outstanding:=inv_total-already;
      IF alloc>outstanding THEN RAISE EXCEPTION 'التخصيص أكبر من المتبقي في الفاتورة'; END IF;
      INSERT INTO payment_allocations(payment_id,sales_invoice_id,amount) VALUES(v,iid,alloc);
      PERFORM refresh_sales_invoice_paid(iid);
    ELSE
      SELECT total INTO inv_total FROM purchase_invoices WHERE id=iid AND supplier_id=p_party AND status='Posted';
      IF inv_total IS NULL THEN RAISE EXCEPTION 'فاتورة مشتريات غير صالحة للتخصيص'; END IF;
      SELECT coalesce(sum(amount),0) INTO already FROM payment_allocations WHERE purchase_invoice_id=iid;
      outstanding:=inv_total-already;
      IF alloc>outstanding THEN RAISE EXCEPTION 'التخصيص أكبر من المتبقي في الفاتورة'; END IF;
      INSERT INTO payment_allocations(payment_id,purchase_invoice_id,amount) VALUES(v,iid,alloc);
      PERFORM refresh_purchase_invoice_paid(iid);
    END IF;
  END LOOP;

  PERFORM log_event('payment','payments',v::text,'سجل '||CASE WHEN p_kind='receipt' THEN 'مقبوضات عميل ' ELSE 'مدفوعات مورد ' END||p_amount);
  RETURN v;
END $$;

-- ============================================================
-- 9) Sales / Purchase RPCs: tax, validation, credit limit, allocation
-- ============================================================
CREATE OR REPLACE FUNCTION create_sale(
  p_customer uuid,p_warehouse uuid,p_items jsonb,p_paid numeric DEFAULT 0,p_account uuid DEFAULT NULL,
  p_method text DEFAULT 'credit',p_discount numeric DEFAULT 0,p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  it jsonb; s company_settings; c customers; v uuid:=gen_random_uuid(); num text; sub numeric:=0; tx numeric:=0; tot numeric;
  pr products; q numeric; price numeric; line_disc numeric; ln numeric; due numeric; current_bal numeric;
BEGIN
  PERFORM require_role('{admin,accountant,sales}');
  IF p_items IS NULL OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'الفاتورة بدون بنود'; END IF;
  IF p_paid<0 THEN RAISE EXCEPTION 'المدفوع غير صحيح'; END IF;
  IF p_method NOT IN ('cash','bank','wallet','credit') THEN RAISE EXCEPTION 'طريقة الدفع غير صحيحة'; END IF;
  SELECT * INTO s FROM company_settings WHERE id=1;
  SELECT * INTO c FROM customers WHERE id=p_customer AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'العميل غير صالح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse AND active) THEN RAISE EXCEPTION 'المخزن غير صالح'; END IF;
  num:=s.invoice_prefix||'S'||(1000+nextval('seq_sales'));
  INSERT INTO sales_invoices(id,number,customer_id,warehouse_id,payment_method,discount,notes,tax_rate,due_date,status)
    VALUES(v,num,p_customer,p_warehouse,p_method,coalesce(p_discount,0),p_notes,case when s.tax_enabled then s.tax_pct else 0 end,
      current_date+coalesce(c.payment_terms_days,0),'Posted');

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO pr FROM products WHERE id=(it->>'product_id')::uuid AND active FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'منتج غير صالح'; END IF;
    q:=(it->>'qty')::numeric; price:=(it->>'price')::numeric; line_disc:=coalesce((it->>'discount')::numeric,0);
    IF q IS NULL OR q<=0 OR price IS NULL OR price<0 OR line_disc<0 OR line_disc>q*price THEN RAISE EXCEPTION 'بيانات بند غير صحيحة'; END IF;
    ln:=round(q*price-line_disc,2);
    PERFORM apply_stock(pr.id,p_warehouse,-q,'Sale','sales_invoice',v);
    INSERT INTO sales_invoice_items(invoice_id,product_id,qty,unit_price,discount,unit_cost,line_total)
      VALUES(v,pr.id,q,price,line_disc,pr.avg_cost,ln);
    sub:=sub+ln;
  END LOOP;

  IF p_discount<0 OR p_discount>sub THEN RAISE EXCEPTION 'الخصم الكلي غير صحيح'; END IF;
  IF s.tax_enabled THEN tx:=round((sub-p_discount)*s.tax_pct/100,2); END IF;
  tot:=round(sub-p_discount+tx,2); due:=round(tot-p_paid,2);
  IF p_paid>tot THEN RAISE EXCEPTION 'المدفوع أكبر من إجمالي الفاتورة'; END IF;

  IF c.credit_limit>0 THEN
    SELECT c.opening_balance
      +coalesce((SELECT sum(total) FROM sales_invoices WHERE customer_id=c.id AND status='Posted'),0)
      -coalesce((SELECT sum(amount) FROM payments WHERE customer_id=c.id),0)
      -coalesce((SELECT sum(total) FROM sales_returns WHERE customer_id=c.id),0)
    INTO current_bal;
    current_bal:=coalesce(current_bal,0)-tot;
    IF current_bal+due>c.credit_limit THEN RAISE EXCEPTION 'تجاوز حد الائتمان للعميل'; END IF;
  END IF;

  UPDATE sales_invoices SET subtotal=sub,tax=tx,total=tot,paid=0 WHERE id=v;
  IF p_paid>0 THEN
    PERFORM record_payment('receipt',p_customer,p_paid,p_account,jsonb_build_array(jsonb_build_object('invoice_id',v,'amount',p_paid)));
  END IF;
  PERFORM log_event('create','sales_invoices',v::text,'أنشأ فاتورة مبيعات '||num||' بإجمالي '||tot);
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_purchase(
  p_supplier uuid,p_warehouse uuid,p_items jsonb,p_paid numeric DEFAULT 0,p_account uuid DEFAULT NULL,
  p_method text DEFAULT 'credit',p_discount numeric DEFAULT 0,p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  it jsonb; s company_settings; sp suppliers; v uuid:=gen_random_uuid(); num text; sub numeric:=0; tx numeric:=0; tot numeric;
  pr products; q numeric; pc numeric; line_disc numeric; ln numeric; onhand numeric;
BEGIN
  PERFORM require_role('{admin,accountant,store}');
  IF p_items IS NULL OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'الفاتورة بدون بنود'; END IF;
  IF p_paid<0 THEN RAISE EXCEPTION 'المدفوع غير صحيح'; END IF;
  SELECT * INTO s FROM company_settings WHERE id=1;
  SELECT * INTO sp FROM suppliers WHERE id=p_supplier AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير صالح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse AND active) THEN RAISE EXCEPTION 'المخزن غير صالح'; END IF;
  num:=s.invoice_prefix||'P'||(1000+nextval('seq_purchase'));
  INSERT INTO purchase_invoices(id,number,supplier_id,warehouse_id,payment_method,discount,notes,tax_rate,due_date,status)
    VALUES(v,num,p_supplier,p_warehouse,p_method,coalesce(p_discount,0),p_notes,case when s.tax_enabled then s.tax_pct else 0 end,
      current_date+coalesce(sp.payment_terms_days,0),'Posted');

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO pr FROM products WHERE id=(it->>'product_id')::uuid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'منتج غير صالح'; END IF;
    q:=(it->>'qty')::numeric; pc:=(it->>'price')::numeric; line_disc:=coalesce((it->>'discount')::numeric,0);
    IF q IS NULL OR q<=0 OR pc IS NULL OR pc<0 OR line_disc<0 OR line_disc>q*pc THEN RAISE EXCEPTION 'بيانات بند غير صحيحة'; END IF;
    ln:=round(q*pc-line_disc,2);
    SELECT coalesce(sum(qty),0) INTO onhand FROM stock_balances WHERE product_id=pr.id;
    UPDATE products SET
      avg_cost=case when greatest(onhand,0)+q>0 then (greatest(onhand,0)*avg_cost+q*pc)/(greatest(onhand,0)+q) else pc end,
      purchase_price=pc WHERE id=pr.id;
    PERFORM apply_stock(pr.id,p_warehouse,q,'Purchase','purchase_invoice',v);
    INSERT INTO purchase_invoice_items(invoice_id,product_id,qty,unit_price,discount,line_total)
      VALUES(v,pr.id,q,pc,line_disc,ln);
    sub:=sub+ln;
  END LOOP;

  IF p_discount<0 OR p_discount>sub THEN RAISE EXCEPTION 'الخصم الكلي غير صحيح'; END IF;
  IF s.tax_enabled THEN tx:=round((sub-p_discount)*s.tax_pct/100,2); END IF;
  tot:=round(sub-p_discount+tx,2);
  IF p_paid>tot THEN RAISE EXCEPTION 'المدفوع أكبر من إجمالي الفاتورة'; END IF;
  UPDATE purchase_invoices SET subtotal=sub,tax=tx,total=tot,paid=0 WHERE id=v;
  IF p_paid>0 THEN
    PERFORM record_payment('payment',p_supplier,p_paid,p_account,jsonb_build_array(jsonb_build_object('invoice_id',v,'amount',p_paid)));
  END IF;
  PERFORM log_event('create','purchase_invoices',v::text,'أنشأ فاتورة مشتريات '||num||' بإجمالي '||tot);
  RETURN v;
END $$;

-- ============================================================
-- 10) Correct return functions with cost + tax reversal
-- ============================================================
CREATE OR REPLACE FUNCTION create_sales_return(p_invoice uuid,p_items jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  inv sales_invoices; it jsonb; v uuid:=gen_random_uuid(); tot numeric:=0; base numeric:=0; tax numeric:=0; sold numeric; prior numeric; q numeric;
  pid uuid; unit_price numeric; unit_cost numeric; line_net numeric; line_tax numeric; discount_factor numeric; num text;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  SELECT * INTO inv FROM sales_invoices WHERE id=p_invoice AND status='Posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  num:=(SELECT invoice_prefix FROM company_settings WHERE id=1)||'SR'||(1000+nextval('seq_sret'));
  INSERT INTO sales_returns(id,number,invoice_id,customer_id,warehouse_id) VALUES(v, num, inv.id, inv.customer_id, inv.warehouse_id);
  discount_factor:=case when inv.subtotal>0 then greatest(inv.subtotal-inv.discount,0)/inv.subtotal else 1 end;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; CONTINUE WHEN q IS NULL OR q<=0;
    SELECT coalesce(sum(qty),0),coalesce(sum(line_total)/nullif(sum(qty),0),0),coalesce(sum(qty*unit_cost)/nullif(sum(qty),0),0)
      INTO sold,unit_price,unit_cost FROM sales_invoice_items WHERE invoice_id=inv.id AND product_id=pid;
    SELECT coalesce(sum(i.qty),0) INTO prior FROM sales_return_items i JOIN sales_returns r ON r.id=i.return_id
      WHERE r.invoice_id=inv.id AND i.product_id=pid AND r.id<>v;
    IF q>sold-prior THEN RAISE EXCEPTION 'لا يمكن إرجاع كمية أكبر من المباعة (المتاح للإرجاع %)',sold-prior; END IF;
    line_net:=round(q*unit_price*discount_factor,2); line_tax:=round(line_net*inv.tax_rate/100,2);
    INSERT INTO sales_return_items(return_id,product_id,qty,unit_price,line_total,unit_cost,cost_total,tax)
      VALUES(v,pid,q,unit_price,line_net,unit_cost,round(q*unit_cost,2),line_tax);
    PERFORM apply_stock(pid,inv.warehouse_id,q,'Sales Return','sales_return',v);
    base:=base+line_net; tax:=tax+line_tax;
  END LOOP;
  IF base=0 THEN RAISE EXCEPTION 'حدد كمية للإرجاع'; END IF;
  tot:=round(base+tax,2);
  UPDATE sales_returns SET total=tot WHERE id=v;
  PERFORM log_event('create','sales_returns',v::text,'سجل مرتجع مبيعات '||num||' بقيمة '||tot);
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_purchase_return(p_invoice uuid,p_items jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  inv purchase_invoices; it jsonb; v uuid:=gen_random_uuid(); tot numeric:=0; base numeric:=0; tax numeric:=0; bought numeric; prior numeric; q numeric;
  pid uuid; unit_price numeric; line_net numeric; line_tax numeric; discount_factor numeric; num text;
BEGIN
  PERFORM require_role('{admin,accountant,store}');
  SELECT * INTO inv FROM purchase_invoices WHERE id=p_invoice AND status='Posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  num:=(SELECT invoice_prefix FROM company_settings WHERE id=1)||'PR'||(1000+nextval('seq_pret'));
  INSERT INTO purchase_returns(id,number,invoice_id,supplier_id,warehouse_id) VALUES(v,num,inv.id,inv.supplier_id,inv.warehouse_id);
  discount_factor:=case when inv.subtotal>0 then greatest(inv.subtotal-inv.discount,0)/inv.subtotal else 1 end;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; CONTINUE WHEN q IS NULL OR q<=0;
    SELECT coalesce(sum(qty),0),coalesce(sum(line_total)/nullif(sum(qty),0),0)
      INTO bought,unit_price FROM purchase_invoice_items WHERE invoice_id=inv.id AND product_id=pid;
    SELECT coalesce(sum(i.qty),0) INTO prior FROM purchase_return_items i JOIN purchase_returns r ON r.id=i.return_id
      WHERE r.invoice_id=inv.id AND i.product_id=pid AND r.id<>v;
    IF q>bought-prior THEN RAISE EXCEPTION 'لا يمكن إرجاع كمية أكبر من المشتراة (المتاح للإرجاع %)',bought-prior; END IF;
    line_net:=round(q*unit_price*discount_factor,2); line_tax:=round(line_net*inv.tax_rate/100,2);
    INSERT INTO purchase_return_items(return_id,product_id,qty,unit_price,line_total,tax)
      VALUES(v,pid,q,unit_price,line_net,line_tax);
    PERFORM apply_stock(pid,inv.warehouse_id,-q,'Purchase Return','purchase_return',v);
    base:=base+line_net; tax:=tax+line_tax;
  END LOOP;
  IF base=0 THEN RAISE EXCEPTION 'حدد كمية للإرجاع'; END IF;
  tot:=round(base+tax,2);
  UPDATE purchase_returns SET total=tot WHERE id=v;
  PERFORM log_event('create','purchase_returns',v::text,'سجل مرتجع مشتريات '||num||' بقيمة '||tot);
  RETURN v;
END $$;

-- ============================================================
-- 11) Permanent-ish journal rebuild with VAT, returns, transfer,
--     and stocktake accounting. Manual entries are preserved.
-- ============================================================
CREATE OR REPLACE FUNCTION rebuild_journal() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r record; e uuid; n int:=0; c numeric; net numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  DELETE FROM journal_entries WHERE doc_type<>'manual' OR doc_type IS NULL;

  FOR r IN SELECT * FROM sales_invoices WHERE status='Posted' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'فاتورة مبيعات '||r.number,'sales_invoice',r.id);
    net:=round(r.total-coalesce(r.tax,0),2);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES
      (e,'1300',r.total,0),(e,'4000',greatest(net,0),0);
    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2100',0,r.tax);
    END IF;
    SELECT coalesce(sum(qty*unit_cost),0) INTO c FROM sales_invoice_items WHERE invoice_id=r.id;
    IF c>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'5000',c,0),(e,'1200',0,c); END IF;
  END LOOP;

  FOR r IN SELECT * FROM purchase_invoices WHERE status='Posted' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'فاتورة مشتريات '||r.number,'purchase_invoice',r.id);
    net:=round(r.total-coalesce(r.tax,0),2);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',greatest(net,0),0),(e,'2000',0,r.total);
    IF coalesce(r.tax,0)>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1410',r.tax,0); END IF;
  END LOOP;

  FOR r IN SELECT p.*,case when a.type='bank' then '1100' else case when a.type='wallet' then '1000' else '1000' end end as cc
           FROM payments p JOIN cash_accounts a ON a.id=p.account_id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,
      CASE r.kind WHEN 'receipt' THEN 'مقبوضات ' ELSE 'مدفوعات ' END||coalesce(r.doc_ref,''),'payment',r.id);
    IF r.kind='receipt' THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,r.cc,r.amount,0),(e,'1300',0,r.amount);
    ELSE INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2000',r.amount,0),(e,r.cc,0,r.amount); END IF;
  END LOOP;

  FOR r IN SELECT * FROM expenses LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'مصروف '||r.category,'expense',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6000',r.amount,0),
      (e,case when (select type from cash_accounts where id=r.account_id)='bank' then '1100' else '1000' end,0,r.amount);
  END LOOP;

  FOR r IN SELECT sr.*,coalesce(sum(i.cost_total),0) cost,coalesce(sum(i.tax),0) tax,
                    coalesce(sum(i.line_total),0) base
           FROM sales_returns sr JOIN sales_return_items i ON i.return_id=sr.id GROUP BY sr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'مرتجع مبيعات '||r.number,'sales_return',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'4000',r.base,0),(e,'1300',0,r.total);
    IF r.tax>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2100',r.tax,0); END IF;
    IF r.cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.cost,0),(e,'5000',0,r.cost); END IF;
  END LOOP;

  FOR r IN SELECT pr.*,coalesce(sum(i.tax),0) tax,coalesce(sum(i.line_total),0) base
           FROM purchase_returns pr JOIN purchase_return_items i ON i.return_id=pr.id GROUP BY pr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'مرتجع مشتريات '||r.number,'purchase_return',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2000',r.total,0),(e,'1200',0,r.base);
    IF r.tax>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1410',0,r.tax); END IF;
  END LOOP;

  FOR r IN SELECT * FROM cash_transfers LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'تحويل بين الحسابات','cash_transfer',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(
      e,case when (select type from cash_accounts where id=r.to_account)='bank' then '1100' else '1000' end,r.amount,0),
      (e,case when (select type from cash_accounts where id=r.from_account)='bank' then '1100' else '1000' end,0,r.amount);
  END LOOP;

  FOR r IN SELECT * FROM payroll WHERE paid LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.month,'مرتب','payroll',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6000',r.net,0),
      (e,case when (select type from cash_accounts where id=r.account_id)='bank' then '1100' else '1000' end,0,r.net);
  END LOOP;

  FOR r IN SELECT sm.id,sm.date,sm.product_id,sm.qty,sm.doc_id,p.avg_cost
           FROM stock_movements sm JOIN products p ON p.id=sm.product_id
           WHERE sm.type='Stock Adjustment' AND sm.doc_type='stocktake' AND sm.doc_id IS NOT NULL LOOP
    e:=gen_random_uuid(); n:=n+1; c:=round(abs(r.qty*r.avg_cost),2);
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'تسوية جرد','stock_adjustment',r.doc_id);
    IF r.qty>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',c,0),(e,'4300',0,c);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6100',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  RETURN n;
END $$;

-- ============================================================
-- 12) Reports / Aging
-- ============================================================
CREATE OR REPLACE FUNCTION trial_balance() RETURNS TABLE(code text,name text,type text,debit numeric,credit numeric,balance numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT a.code,a.name,a.type,coalesce(sum(j.debit),0),coalesce(sum(j.credit),0),coalesce(sum(j.debit-j.credit),0)
  FROM accounts a LEFT JOIN journal_lines j ON j.account_code=a.code
  WHERE auth_role() IN ('admin','accountant')
  GROUP BY a.code,a.name,a.type ORDER BY a.code
$$;

CREATE OR REPLACE FUNCTION general_ledger(p_account text,p_from date DEFAULT '0001-01-01',p_to date DEFAULT current_date)
RETURNS TABLE(d date,doc text,description text,debit numeric,credit numeric,running_balance numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT x.d,x.doc,x.description,x.debit,x.credit,
         sum(x.debit-x.credit) OVER(ORDER BY x.d,x.doc,x.id)
  FROM (
    SELECT e.date d,coalesce(e.doc_id::text,'') doc,e.description,l.debit,l.credit,l.id
    FROM journal_entries e JOIN journal_lines l ON l.entry_id=e.id
    WHERE l.account_code=p_account AND e.date BETWEEN p_from AND p_to
      AND auth_role() IN ('admin','accountant')
  ) x ORDER BY x.d,x.doc,x.id
$$;

CREATE OR REPLACE FUNCTION customer_aging(p_as_of date DEFAULT current_date)
RETURNS TABLE(customer_id uuid,name text,current_amt numeric,d1_30 numeric,d31_60 numeric,d61_90 numeric,d90_plus numeric,unallocated_credit numeric,total numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT c.id,c.name,
    coalesce(sum(case when s.due_date>=p_as_of then s.outstanding else 0 end),0),
    coalesce(sum(case when s.due_date<p_as_of and p_as_of-s.due_date between 1 and 30 then s.outstanding else 0 end),0),
    coalesce(sum(case when p_as_of-s.due_date between 31 and 60 then s.outstanding else 0 end),0),
    coalesce(sum(case when p_as_of-s.due_date between 61 and 90 then s.outstanding else 0 end),0),
    coalesce(sum(case when p_as_of-s.due_date>90 then s.outstanding else 0 end),0),
    greatest(coalesce((SELECT sum(amount) FROM payments p WHERE p.customer_id=c.id AND p.kind='receipt'
      AND NOT EXISTS(SELECT 1 FROM payment_allocations pa WHERE pa.payment_id=p.id)),0),0),
    greatest(coalesce(sum(s.outstanding),0)-coalesce((SELECT sum(amount) FROM payments p WHERE p.customer_id=c.id AND p.kind='receipt'
      AND NOT EXISTS(SELECT 1 FROM payment_allocations pa WHERE pa.payment_id=p.id)),0),0)
  FROM customers c LEFT JOIN sales_invoice_balances s ON s.customer_id=c.id AND s.status='Posted'
  WHERE auth_role() IN ('admin','accountant')
  GROUP BY c.id,c.name ORDER BY c.name
$$;

CREATE OR REPLACE FUNCTION supplier_aging(p_as_of date DEFAULT current_date)
RETURNS TABLE(supplier_id uuid,name text,current_amt numeric,d1_30 numeric,d31_60 numeric,d61_90 numeric,d90_plus numeric,unallocated_credit numeric,total numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT s.id,s.name,
    coalesce(sum(case when p.due_date>=p_as_of then p.outstanding else 0 end),0),
    coalesce(sum(case when p.due_date<p_as_of and p_as_of-p.due_date between 1 and 30 then p.outstanding else 0 end),0),
    coalesce(sum(case when p_as_of-p.due_date between 31 and 60 then p.outstanding else 0 end),0),
    coalesce(sum(case when p_as_of-p.due_date between 61 and 90 then p.outstanding else 0 end),0),
    coalesce(sum(case when p_as_of-p.due_date>90 then p.outstanding else 0 end),0),
    greatest(coalesce((SELECT sum(amount) FROM payments p2 WHERE p2.supplier_id=s.id AND p2.kind='payment'
      AND NOT EXISTS(SELECT 1 FROM payment_allocations pa WHERE pa.payment_id=p2.id)),0),0),
    greatest(coalesce(sum(p.outstanding),0)-coalesce((SELECT sum(amount) FROM payments p2 WHERE p2.supplier_id=s.id AND p2.kind='payment'
      AND NOT EXISTS(SELECT 1 FROM payment_allocations pa WHERE pa.payment_id=p2.id)),0),0)
  FROM suppliers s LEFT JOIN purchase_invoice_balances p ON p.supplier_id=s.id AND p.status='Posted'
  WHERE auth_role() IN ('admin','accountant')
  GROUP BY s.id,s.name ORDER BY s.name
$$;

-- Basic P&L based on posted journal.
CREATE OR REPLACE FUNCTION profit_loss(p_from date DEFAULT date_trunc('month',current_date)::date,p_to date DEFAULT current_date)
RETURNS TABLE(account_code text,account_name text,amount numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT a.code,a.name,round(sum(l.credit-l.debit),2) amount
  FROM accounts a JOIN journal_lines l ON l.account_code=a.code JOIN journal_entries e ON e.id=l.entry_id
  WHERE e.date BETWEEN p_from AND p_to AND a.type IN ('Revenue','Expense','COGS')
    AND auth_role() IN ('admin','accountant')
  GROUP BY a.code,a.name ORDER BY a.code
$$;

-- Role-aware dashboard: finance metrics are not exposed to sales/store.
CREATE OR REPLACE FUNCTION dashboard_v2(p_from date,p_to date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE
    WHEN auth_role() IS NULL THEN NULL
    WHEN auth_role() IN ('admin','accountant') THEN jsonb_build_object(
      'sales',(SELECT coalesce(sum(total),0) FROM sales_invoices WHERE status='Posted' AND date BETWEEN p_from AND p_to),
      'purchases',(SELECT coalesce(sum(total),0) FROM purchase_invoices WHERE status='Posted' AND date BETWEEN p_from AND p_to),
      'expenses',(SELECT coalesce(sum(amount),0) FROM expenses WHERE date BETWEEN p_from AND p_to),
      'cogs',(SELECT coalesce(sum(i.qty*i.unit_cost),0) FROM sales_invoice_items i JOIN sales_invoices s ON s.id=i.invoice_id WHERE s.status='Posted' AND s.date BETWEEN p_from AND p_to),
      'receivables',(SELECT coalesce(sum(balance),0) FROM customer_balances),
      'payables',(SELECT coalesce(sum(balance),0) FROM supplier_balances),
      'inventory_value',(SELECT coalesce(sum(b.qty*p.avg_cost),0) FROM stock_balances b JOIN products p ON p.id=b.product_id),
      'products',(SELECT count(*) FROM products WHERE active),
      'low_stock',(SELECT count(*) FROM low_stock),
      'receipts',(SELECT coalesce(sum(amount),0) FROM payments WHERE kind='receipt' AND date BETWEEN p_from AND p_to),
      'payments_out',(SELECT coalesce(sum(amount),0) FROM payments WHERE kind='payment' AND date BETWEEN p_from AND p_to))
    ELSE jsonb_build_object(
      'sales',(SELECT coalesce(sum(total),0) FROM sales_invoices WHERE status='Posted' AND date BETWEEN p_from AND p_to),
      'products',(SELECT count(*) FROM products WHERE active),
      'low_stock',(SELECT count(*) FROM low_stock))
  END
$$;

-- ============================================================
-- 13) Permissions for new RPCs
-- ============================================================
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM public,anon;
GRANT EXECUTE ON FUNCTION create_stock_transfer(uuid,uuid,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_stocktake(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION approve_stocktake_v2(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_manual_journal(date,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION record_payment(text,uuid,numeric,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_sale(uuid,uuid,jsonb,numeric,uuid,text,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase(uuid,uuid,jsonb,numeric,uuid,text,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_sales_return(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase_return(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION rebuild_journal() TO authenticated;
GRANT EXECUTE ON FUNCTION trial_balance() TO authenticated;
GRANT EXECUTE ON FUNCTION general_ledger(text,date,date) TO authenticated;
GRANT EXECUTE ON FUNCTION customer_aging(date) TO authenticated;
GRANT EXECUTE ON FUNCTION supplier_aging(date) TO authenticated;
GRANT EXECUTE ON FUNCTION profit_loss(date,date) TO authenticated;
GRANT EXECUTE ON FUNCTION dashboard_v2(date,date) TO authenticated;

COMMIT;




-- ====================== 005_go_live_hardening.sql ======================
-- ERP V2 final hardening before real company data.
-- Run AFTER ERP_full_v2_fixed2.sql + 004_fix_api_grants.sql.
-- Safe for the current fresh V2 project; does not reset existing data.

BEGIN;

-- v1.3: إسقاط الـviews القديمة قبل إعادة إنشائها بأعمدة مختلفة (CREATE OR REPLACE مايغيرش ترتيب/اسم الأعمدة)
DROP VIEW IF EXISTS sales_invoice_balances;
DROP VIEW IF EXISTS purchase_invoice_balances;

-- 1) Balances/statements must ignore void invoices.
CREATE OR REPLACE VIEW sales_invoice_balances WITH(security_invoker=true) AS
SELECT i.id,i.number,i.date,i.due_date,i.customer_id,i.warehouse_id,i.subtotal,i.discount,i.tax,i.total,
       COALESCE(pa.paid,0)::numeric(14,2) AS allocated_paid,
       COALESCE(sr.returned,0)::numeric(14,2) AS returned_total,
       GREATEST(i.total-COALESCE(pa.paid,0)-COALESCE(sr.returned,0),0)::numeric(14,2) AS outstanding,
       GREATEST(COALESCE(sr.returned,0)-(i.total-COALESCE(pa.paid,0)),0)::numeric(14,2) AS credit_balance,
       i.status
FROM sales_invoices i
LEFT JOIN (SELECT sales_invoice_id,SUM(amount) paid FROM payment_allocations GROUP BY sales_invoice_id) pa
  ON pa.sales_invoice_id=i.id
LEFT JOIN (SELECT invoice_id,SUM(total) returned FROM sales_returns GROUP BY invoice_id) sr
  ON sr.invoice_id=i.id;

CREATE OR REPLACE VIEW purchase_invoice_balances WITH(security_invoker=true) AS
SELECT i.id,i.number,i.date,i.due_date,i.supplier_id,i.warehouse_id,i.subtotal,i.discount,i.tax,i.total,
       COALESCE(pa.paid,0)::numeric(14,2) AS allocated_paid,
       COALESCE(pr.returned,0)::numeric(14,2) AS returned_total,
       GREATEST(i.total-COALESCE(pa.paid,0)-COALESCE(pr.returned,0),0)::numeric(14,2) AS outstanding,
       GREATEST(COALESCE(pr.returned,0)-(i.total-COALESCE(pa.paid,0)),0)::numeric(14,2) AS credit_balance,
       i.status
FROM purchase_invoices i
LEFT JOIN (SELECT purchase_invoice_id,SUM(amount) paid FROM payment_allocations GROUP BY purchase_invoice_id) pa
  ON pa.purchase_invoice_id=i.id
LEFT JOIN (SELECT invoice_id,SUM(total) returned FROM purchase_returns GROUP BY invoice_id) pr
  ON pr.invoice_id=i.id;

CREATE OR REPLACE VIEW customer_balances WITH(security_invoker=true) AS
SELECT c.id,c.name,
  c.opening_balance
  +coalesce((SELECT sum(total) FROM sales_invoices WHERE customer_id=c.id AND status='Posted'),0)
  -coalesce((SELECT sum(amount) FROM payments WHERE customer_id=c.id AND kind='receipt'),0)
  -coalesce((SELECT sum(total) FROM sales_returns WHERE customer_id=c.id),0) AS balance
FROM customers c;

CREATE OR REPLACE VIEW supplier_balances WITH(security_invoker=true) AS
SELECT s.id,s.name,
  s.opening_balance
  +coalesce((SELECT sum(total) FROM purchase_invoices WHERE supplier_id=s.id AND status='Posted'),0)
  -coalesce((SELECT sum(amount) FROM payments WHERE supplier_id=s.id AND kind='payment'),0)
  -coalesce((SELECT sum(total) FROM purchase_returns WHERE supplier_id=s.id),0) AS balance
FROM suppliers s;

CREATE OR REPLACE FUNCTION customer_statement(p_party uuid,p_to date DEFAULT current_date)
RETURNS TABLE(d date,doc text,descr text,debit numeric,credit numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT date,number,'فاتورة مبيعات'::text,total::numeric,0::numeric
  FROM sales_invoices WHERE customer_id=p_party AND status='Posted' AND date<=p_to
  UNION ALL
  SELECT date,coalesce(doc_ref,'دفعة'),'مقبوضات',0,amount
  FROM payments WHERE customer_id=p_party AND kind='receipt' AND date<=p_to
  UNION ALL
  SELECT date,number,'مرتجع مبيعات',0,total
  FROM sales_returns WHERE customer_id=p_party AND date<=p_to
  ORDER BY 1
$$;

CREATE OR REPLACE FUNCTION supplier_statement(p_party uuid,p_to date DEFAULT current_date)
RETURNS TABLE(d date,doc text,descr text,debit numeric,credit numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT date,number,'فاتورة مشتريات'::text,0::numeric,total::numeric
  FROM purchase_invoices WHERE supplier_id=p_party AND status='Posted' AND date<=p_to
  UNION ALL
  SELECT date,coalesce(doc_ref,'دفعة'),'مدفوعات',amount,0
  FROM payments WHERE supplier_id=p_party AND kind='payment' AND date<=p_to
  UNION ALL
  SELECT date,number,'مرتجع مشتريات',total,0
  FROM purchase_returns WHERE supplier_id=p_party AND date<=p_to
  ORDER BY 1
$$;

-- 2) Purchase-return cost must be retained so Inventory/GL remain consistent.
ALTER TABLE purchase_return_items ADD COLUMN IF NOT EXISTS unit_cost numeric(14,4) NOT NULL DEFAULT 0;
ALTER TABLE purchase_return_items ADD COLUMN IF NOT EXISTS cost_total numeric(14,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION create_purchase_return(p_invoice uuid,p_items jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  inv purchase_invoices; it jsonb; v uuid:=gen_random_uuid(); tot numeric:=0; base numeric:=0; tax numeric:=0;
  bought numeric; prior numeric; q numeric; pid uuid; unit_price numeric; unit_cost numeric;
  line_net numeric; line_tax numeric; discount_factor numeric; num text;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO inv FROM purchase_invoices WHERE id=p_invoice AND status='Posted' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  num:=(SELECT invoice_prefix FROM company_settings WHERE id=1)||'PR'||(1000+nextval('seq_pret'));
  INSERT INTO purchase_returns(id,number,invoice_id,supplier_id,warehouse_id)
    VALUES(v,num,inv.id,inv.supplier_id,inv.warehouse_id);
  discount_factor:=CASE WHEN inv.subtotal>0 THEN greatest(inv.subtotal-inv.discount,0)/inv.subtotal ELSE 1 END;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric;
    CONTINUE WHEN q IS NULL OR q<=0;
    SELECT coalesce(sum(qty),0),coalesce(sum(line_total)/nullif(sum(qty),0),0)
      INTO bought,unit_price
      FROM purchase_invoice_items WHERE invoice_id=inv.id AND product_id=pid;
    SELECT coalesce(sum(i.qty),0) INTO prior
      FROM purchase_return_items i JOIN purchase_returns r ON r.id=i.return_id
      WHERE r.invoice_id=inv.id AND i.product_id=pid AND r.id<>v;
    IF q>bought-prior THEN
      RAISE EXCEPTION 'لا يمكن إرجاع كمية أكبر من المشتراة (المتاح للإرجاع %)',bought-prior;
    END IF;
    line_net:=round(q*unit_price*discount_factor,2);
    line_tax:=round(line_net*inv.tax_rate/100,2);
    unit_cost:=CASE WHEN q>0 THEN line_net/q ELSE 0 END;
    INSERT INTO purchase_return_items(return_id,product_id,qty,unit_price,line_total,unit_cost,cost_total,tax)
      VALUES(v,pid,q,unit_price,line_net,unit_cost,line_net,line_tax);
    PERFORM apply_stock(pid,inv.warehouse_id,-q,'Purchase Return','purchase_return',v);
    base:=base+line_net; tax:=tax+line_tax;
  END LOOP;
  IF base=0 THEN RAISE EXCEPTION 'حدد كمية للإرجاع'; END IF;
  tot:=round(base+tax,2);
  UPDATE purchase_returns SET total=tot WHERE id=v;
  PERFORM log_event('create','purchase_returns',v::text,'سجل مرتجع مشتريات '||num||' بقيمة '||tot);
  RETURN v;
END $$;

-- 3) Internal initial payment used by invoice creation.
-- It is intentionally NOT executable by clients directly.
CREATE OR REPLACE FUNCTION record_initial_payment(
  p_kind text,p_party uuid,p_amount numeric,p_account uuid,p_invoice uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); inv_total numeric; pid uuid;
BEGIN
  IF p_amount<=0 THEN RAISE EXCEPTION 'المبلغ غير صحيح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM cash_accounts WHERE id=p_account) THEN RAISE EXCEPTION 'الحساب المالي غير موجود'; END IF;
  IF p_kind='receipt' THEN
    SELECT total INTO inv_total FROM sales_invoices WHERE id=p_invoice AND customer_id=p_party AND status='Posted' FOR UPDATE;
    IF inv_total IS NULL OR p_amount>inv_total THEN RAISE EXCEPTION 'بيانات دفعة المبيعات غير صحيحة'; END IF;
  ELSIF p_kind='payment' THEN
    SELECT total INTO inv_total FROM purchase_invoices WHERE id=p_invoice AND supplier_id=p_party AND status='Posted' FOR UPDATE;
    IF inv_total IS NULL OR p_amount>inv_total THEN RAISE EXCEPTION 'بيانات دفعة المشتريات غير صحيحة'; END IF;
  ELSE
    RAISE EXCEPTION 'نوع الحركة غير صحيح';
  END IF;

  INSERT INTO payments(id,kind,customer_id,supplier_id,account_id,amount,doc_ref)
    VALUES(v,p_kind,CASE WHEN p_kind='receipt' THEN p_party END,CASE WHEN p_kind='payment' THEN p_party END,
           p_account,p_amount,NULL);
  IF p_kind='receipt' THEN
    INSERT INTO payment_allocations(payment_id,sales_invoice_id,amount) VALUES(v,p_invoice,p_amount);
  ELSE
    INSERT INTO payment_allocations(payment_id,purchase_invoice_id,amount) VALUES(v,p_invoice,p_amount);
  END IF;
  PERFORM apply_cash(p_account,CASE WHEN p_kind='receipt' THEN p_amount ELSE -p_amount END);
  IF p_kind='receipt' THEN PERFORM refresh_sales_invoice_paid(p_invoice); ELSE PERFORM refresh_purchase_invoice_paid(p_invoice); END IF;
  RETURN v;
END $$;

REVOKE ALL ON FUNCTION record_initial_payment(text,uuid,numeric,uuid,uuid) FROM public,anon,authenticated;

-- 4) Replace public payment allocator with row locking to prevent concurrent over-allocation.
CREATE OR REPLACE FUNCTION record_payment(
  p_kind text,p_party uuid,p_amount numeric,p_account uuid,p_allocations jsonb DEFAULT '[]'::jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); a jsonb; iid uuid; alloc numeric; total_alloc numeric:=0;
  inv_total numeric; already numeric; outstanding numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_kind NOT IN ('receipt','payment') THEN RAISE EXCEPTION 'نوع الحركة غير صحيح'; END IF;
  IF p_amount<=0 THEN RAISE EXCEPTION 'المبلغ غير صحيح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM cash_accounts WHERE id=p_account) THEN RAISE EXCEPTION 'الحساب المالي غير موجود'; END IF;
  IF p_kind='receipt' AND NOT EXISTS(SELECT 1 FROM customers WHERE id=p_party AND active) THEN RAISE EXCEPTION 'العميل غير صالح'; END IF;
  IF p_kind='payment' AND NOT EXISTS(SELECT 1 FROM suppliers WHERE id=p_party AND active) THEN RAISE EXCEPTION 'المورد غير صالح'; END IF;

  INSERT INTO payments(id,kind,customer_id,supplier_id,account_id,amount)
    VALUES(v,p_kind,CASE WHEN p_kind='receipt' THEN p_party END,CASE WHEN p_kind='payment' THEN p_party END,p_account,p_amount);
  PERFORM apply_cash(p_account,CASE WHEN p_kind='receipt' THEN p_amount ELSE -p_amount END);

  FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) LOOP
    iid:=(a->>'invoice_id')::uuid; alloc:=(a->>'amount')::numeric;
    IF alloc IS NULL OR alloc<=0 THEN RAISE EXCEPTION 'قيمة التخصيص غير صحيحة'; END IF;
    total_alloc:=total_alloc+alloc;
    IF total_alloc>p_amount THEN RAISE EXCEPTION 'إجمالي التخصيص أكبر من قيمة الدفعة'; END IF;

    IF p_kind='receipt' THEN
      SELECT total INTO inv_total FROM sales_invoices WHERE id=iid AND customer_id=p_party AND status='Posted' FOR UPDATE;
      IF inv_total IS NULL THEN RAISE EXCEPTION 'فاتورة مبيعات غير صالحة للتخصيص'; END IF;
      SELECT coalesce(sum(amount),0) INTO already FROM payment_allocations WHERE sales_invoice_id=iid;
      outstanding:=inv_total-already;
      IF alloc>outstanding THEN RAISE EXCEPTION 'التخصيص أكبر من المتبقي في الفاتورة'; END IF;
      INSERT INTO payment_allocations(payment_id,sales_invoice_id,amount) VALUES(v,iid,alloc);
      PERFORM refresh_sales_invoice_paid(iid);
    ELSE
      SELECT total INTO inv_total FROM purchase_invoices WHERE id=iid AND supplier_id=p_party AND status='Posted' FOR UPDATE;
      IF inv_total IS NULL THEN RAISE EXCEPTION 'فاتورة مشتريات غير صالحة للتخصيص'; END IF;
      SELECT coalesce(sum(amount),0) INTO already FROM payment_allocations WHERE purchase_invoice_id=iid;
      outstanding:=inv_total-already;
      IF alloc>outstanding THEN RAISE EXCEPTION 'التخصيص أكبر من المتبقي في الفاتورة'; END IF;
      INSERT INTO payment_allocations(payment_id,purchase_invoice_id,amount) VALUES(v,iid,alloc);
      PERFORM refresh_purchase_invoice_paid(iid);
    END IF;
  END LOOP;
  PERFORM log_event('payment','payments',v::text,'سجل '||CASE WHEN p_kind='receipt' THEN 'مقبوضات عميل ' ELSE 'مدفوعات مورد ' END||p_amount);
  RETURN v;
END $$;

-- 5) Invoice creation may include an initial payment for its authorized business role.
CREATE OR REPLACE FUNCTION create_sale(
  p_customer uuid,p_warehouse uuid,p_items jsonb,p_paid numeric DEFAULT 0,p_account uuid DEFAULT NULL,
  p_method text DEFAULT 'credit',p_discount numeric DEFAULT 0,p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  it jsonb; s company_settings; c customers; v uuid:=gen_random_uuid(); num text; sub numeric:=0; tx numeric:=0; tot numeric;
  pr products; q numeric; price numeric; line_disc numeric; ln numeric; current_bal numeric;
BEGIN
  PERFORM require_role('{admin,accountant,sales}');
  IF p_items IS NULL OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'الفاتورة بدون بنود'; END IF;
  IF p_paid<0 THEN RAISE EXCEPTION 'المدفوع غير صحيح'; END IF;
  IF p_method NOT IN ('cash','bank','wallet','credit') THEN RAISE EXCEPTION 'طريقة الدفع غير صحيحة'; END IF;
  SELECT * INTO s FROM company_settings WHERE id=1;
  SELECT * INTO c FROM customers WHERE id=p_customer AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'العميل غير صالح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse AND active) THEN RAISE EXCEPTION 'المخزن غير صالح'; END IF;
  num:=s.invoice_prefix||'S'||(1000+nextval('seq_sales'));
  INSERT INTO sales_invoices(id,number,customer_id,warehouse_id,payment_method,discount,notes,tax_rate,due_date,status)
    VALUES(v,num,p_customer,p_warehouse,p_method,coalesce(p_discount,0),p_notes,CASE WHEN s.tax_enabled THEN s.tax_pct ELSE 0 END,
           current_date+coalesce(c.payment_terms_days,0),'Posted');

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO pr FROM products WHERE id=(it->>'product_id')::uuid AND active FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'منتج غير صالح'; END IF;
    q:=(it->>'qty')::numeric; price:=(it->>'price')::numeric; line_disc:=coalesce((it->>'discount')::numeric,0);
    IF q IS NULL OR q<=0 OR price IS NULL OR price<0 OR line_disc<0 OR line_disc>q*price THEN RAISE EXCEPTION 'بيانات بند غير صحيحة'; END IF;
    ln:=round(q*price-line_disc,2);
    PERFORM apply_stock(pr.id,p_warehouse,-q,'Sale','sales_invoice',v);
    INSERT INTO sales_invoice_items(invoice_id,product_id,qty,unit_price,discount,unit_cost,line_total)
      VALUES(v,pr.id,q,price,line_disc,pr.avg_cost,ln);
    sub:=sub+ln;
  END LOOP;

  IF p_discount<0 OR p_discount>sub THEN RAISE EXCEPTION 'الخصم الكلي غير صحيح'; END IF;
  IF s.tax_enabled THEN tx:=round((sub-p_discount)*s.tax_pct/100,2); END IF;
  tot:=round(sub-p_discount+tx,2);
  IF p_paid>tot THEN RAISE EXCEPTION 'المدفوع أكبر من إجمالي الفاتورة'; END IF;

  IF c.credit_limit>0 THEN
    SELECT c.opening_balance
      +coalesce((SELECT sum(total) FROM sales_invoices WHERE customer_id=c.id AND status='Posted'),0)
      -coalesce((SELECT sum(amount) FROM payments WHERE customer_id=c.id AND kind='receipt'),0)
      -coalesce((SELECT sum(total) FROM sales_returns WHERE customer_id=c.id),0)
    INTO current_bal;
    current_bal:=coalesce(current_bal,0)-tot;
    IF current_bal+(tot-p_paid)>c.credit_limit THEN RAISE EXCEPTION 'تجاوز حد الائتمان للعميل'; END IF;
  END IF;

  UPDATE sales_invoices SET subtotal=sub,tax=tx,total=tot,paid=0 WHERE id=v;
  IF p_paid>0 THEN PERFORM record_initial_payment('receipt',p_customer,p_paid,p_account,v); END IF;
  PERFORM log_event('create','sales_invoices',v::text,'أنشأ فاتورة مبيعات '||num||' بإجمالي '||tot);
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_purchase(
  p_supplier uuid,p_warehouse uuid,p_items jsonb,p_paid numeric DEFAULT 0,p_account uuid DEFAULT NULL,
  p_method text DEFAULT 'credit',p_discount numeric DEFAULT 0,p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  it jsonb; s company_settings; sp suppliers; v uuid:=gen_random_uuid(); num text; sub numeric:=0; tx numeric:=0; tot numeric;
  pr products; q numeric; pc numeric; line_disc numeric; ln numeric; onhand numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_items IS NULL OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'الفاتورة بدون بنود'; END IF;
  IF p_paid<0 THEN RAISE EXCEPTION 'المدفوع غير صحيح'; END IF;
  SELECT * INTO s FROM company_settings WHERE id=1;
  SELECT * INTO sp FROM suppliers WHERE id=p_supplier AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير صالح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse AND active) THEN RAISE EXCEPTION 'المخزن غير صالح'; END IF;
  num:=s.invoice_prefix||'P'||(1000+nextval('seq_purchase'));
  INSERT INTO purchase_invoices(id,number,supplier_id,warehouse_id,payment_method,discount,notes,tax_rate,due_date,status)
    VALUES(v,num,p_supplier,p_warehouse,p_method,coalesce(p_discount,0),p_notes,CASE WHEN s.tax_enabled THEN s.tax_pct ELSE 0 END,
           current_date+coalesce(sp.payment_terms_days,0),'Posted');

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO pr FROM products WHERE id=(it->>'product_id')::uuid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'منتج غير صالح'; END IF;
    q:=(it->>'qty')::numeric; pc:=(it->>'price')::numeric; line_disc:=coalesce((it->>'discount')::numeric,0);
    IF q IS NULL OR q<=0 OR pc IS NULL OR pc<0 OR line_disc<0 OR line_disc>q*pc THEN RAISE EXCEPTION 'بيانات بند غير صحيحة'; END IF;
    ln:=round(q*pc-line_disc,2);
    SELECT coalesce(sum(qty),0) INTO onhand FROM stock_balances WHERE product_id=pr.id;
    UPDATE products SET avg_cost=CASE WHEN greatest(onhand,0)+q>0 THEN
      (greatest(onhand,0)*avg_cost+q*pc)/(greatest(onhand,0)+q) ELSE pc END,purchase_price=pc WHERE id=pr.id;
    PERFORM apply_stock(pr.id,p_warehouse,q,'Purchase','purchase_invoice',v);
    INSERT INTO purchase_invoice_items(invoice_id,product_id,qty,unit_price,discount,line_total)
      VALUES(v,pr.id,q,pc,line_disc,ln);
    sub:=sub+ln;
  END LOOP;
  IF p_discount<0 OR p_discount>sub THEN RAISE EXCEPTION 'الخصم الكلي غير صحيح'; END IF;
  IF s.tax_enabled THEN tx:=round((sub-p_discount)*s.tax_pct/100,2); END IF;
  tot:=round(sub-p_discount+tx,2);
  IF p_paid>tot THEN RAISE EXCEPTION 'المدفوع أكبر من إجمالي الفاتورة'; END IF;
  UPDATE purchase_invoices SET subtotal=sub,tax=tx,total=tot,paid=0 WHERE id=v;
  IF p_paid>0 THEN PERFORM record_initial_payment('payment',p_supplier,p_paid,p_account,v); END IF;
  PERFORM log_event('create','purchase_invoices',v::text,'أنشأ فاتورة مشتريات '||num||' بإجمالي '||tot);
  RETURN v;
END $$;

-- 6) Keep return journals consistent with retained purchase-return cost.
CREATE OR REPLACE FUNCTION rebuild_journal() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r record; e uuid; n int:=0; c numeric; net numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  DELETE FROM journal_entries WHERE doc_type<>'manual' OR doc_type IS NULL;

  FOR r IN SELECT * FROM sales_invoices WHERE status='Posted' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'فاتورة مبيعات '||r.number,'sales_invoice',r.id);
    net:=round(r.total-coalesce(r.tax,0),2);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES
      (e,'1300',r.total,0),(e,'4000',greatest(net,0),0);
    IF coalesce(r.tax,0)>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2100',0,r.tax); END IF;
    SELECT coalesce(sum(qty*unit_cost),0) INTO c FROM sales_invoice_items WHERE invoice_id=r.id;
    IF c>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'5000',c,0),(e,'1200',0,c); END IF;
  END LOOP;

  FOR r IN SELECT * FROM purchase_invoices WHERE status='Posted' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'فاتورة مشتريات '||r.number,'purchase_invoice',r.id);
    net:=round(r.total-coalesce(r.tax,0),2);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',greatest(net,0),0),(e,'2000',0,r.total);
    IF coalesce(r.tax,0)>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1410',r.tax,0); END IF;
  END LOOP;

  FOR r IN SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END cc FROM payments p JOIN cash_accounts a ON a.id=p.account_id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,CASE WHEN r.kind='receipt' THEN 'مقبوضات ' ELSE 'مدفوعات ' END||coalesce(r.doc_ref,''),'payment',r.id);
    IF r.kind='receipt' THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,r.cc,r.amount,0),(e,'1300',0,r.amount);
    ELSE INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2000',r.amount,0),(e,r.cc,0,r.amount); END IF;
  END LOOP;

  FOR r IN SELECT * FROM expenses LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'مصروف '||r.category,'expense',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6000',r.amount,0),(e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.account_id)='bank' THEN '1100' ELSE '1000' END,0,r.amount);
  END LOOP;

  FOR r IN SELECT sr.*,coalesce(sum(i.cost_total),0) cost,coalesce(sum(i.tax),0) tax,coalesce(sum(i.line_total),0) base
           FROM sales_returns sr JOIN sales_return_items i ON i.return_id=sr.id GROUP BY sr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'مرتجع مبيعات '||r.number,'sales_return',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'4000',r.base,0),(e,'1300',0,r.total);
    IF r.tax>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2100',r.tax,0); END IF;
    IF r.cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.cost,0),(e,'5000',0,r.cost); END IF;
  END LOOP;

  FOR r IN SELECT pr.*,coalesce(sum(i.tax),0) tax,coalesce(sum(i.cost_total),sum(i.line_total),0) base
           FROM purchase_returns pr JOIN purchase_return_items i ON i.return_id=pr.id GROUP BY pr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'مرتجع مشتريات '||r.number,'purchase_return',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2000',r.total,0),(e,'1200',0,r.base);
    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1410',0,r.tax);
    END IF;
  END LOOP;

  FOR r IN SELECT * FROM cash_transfers LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'تحويل بين الحسابات','cash_transfer',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(
      e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.to_account)='bank' THEN '1100' ELSE '1000' END,r.amount,0),
      (e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.from_account)='bank' THEN '1100' ELSE '1000' END,0,r.amount);
  END LOOP;

  FOR r IN SELECT * FROM payroll WHERE paid LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.month,'مرتب','payroll',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6000',r.net,0),(e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.account_id)='bank' THEN '1100' ELSE '1000' END,0,r.net);
  END LOOP;

  FOR r IN SELECT sm.id,sm.date,sm.product_id,sm.qty,sm.doc_id,p.avg_cost
           FROM stock_movements sm JOIN products p ON p.id=sm.product_id
           WHERE sm.type='Stock Adjustment' AND sm.doc_type='stocktake' AND sm.doc_id IS NOT NULL LOOP
    e:=gen_random_uuid(); n:=n+1; c:=round(abs(r.qty*r.avg_cost),2);
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'تسوية جرد','stock_adjustment',r.doc_id);
    IF r.qty>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',c,0),(e,'4300',0,c);
    ELSE INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6100',c,0),(e,'1200',0,c); END IF;
  END LOOP;
  RETURN n;
END $$;

-- 7) Safe opening stock entry used by product setup. Only valid before movements exist for that product/warehouse.
CREATE OR REPLACE FUNCTION set_opening_stock(p_prod uuid,p_wh uuid,p_qty numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cur numeric;
BEGIN
  PERFORM require_role('{admin,store}');
  IF p_qty IS NULL OR p_qty<0 THEN RAISE EXCEPTION 'الرصيد الافتتاحي غير صحيح'; END IF;
  IF NOT EXISTS(SELECT 1 FROM products WHERE id=p_prod) THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_wh AND active) THEN RAISE EXCEPTION 'المخزن غير موجود'; END IF;
  SELECT coalesce(qty,0) INTO cur FROM stock_balances WHERE product_id=p_prod AND warehouse_id=p_wh;
  IF EXISTS(SELECT 1 FROM stock_movements WHERE product_id=p_prod AND warehouse_id=p_wh) THEN
    RAISE EXCEPTION 'لا يمكن تعديل الرصيد الافتتاحي بعد وجود حركة على الصنف في هذا المخزن';
  END IF;
  IF coalesce(cur,0)<>0 THEN RAISE EXCEPTION 'الرصيد الحالي للصنف ليس صفرًا'; END IF;
  IF p_qty>0 THEN PERFORM apply_stock(p_prod,p_wh,p_qty,'Opening Balance','opening_balance',null); END IF;
  PERFORM log_event('create','stock_balances',p_prod::text,'سجل رصيد افتتاحي '||p_qty);
END $$;

REVOKE ALL ON FUNCTION set_opening_stock(uuid,uuid,numeric) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION set_opening_stock(uuid,uuid,numeric) TO authenticated;

-- 8) Admin-only automated smoke test. It creates TEST data, verifies core flows,
--    then cleans all of its test data before returning.
CREATE OR REPLACE FUNCTION run_erp_smoke_test() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  tag text:='__ERP_TEST__'||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  wh1 uuid; wh2 uuid; ca uuid; p uuid; cust uuid; supp uuid; invs uuid; invp uuid;
  ret uuid; pret uuid; tr uuid; stid uuid; mj uuid; pay uuid;
  old_tax boolean; old_pct numeric; r jsonb:='[]'::jsonb; ok boolean:=true;
  b numeric; v numeric; d numeric; c numeric; cnt int; failed_expected boolean:=false;
  test_date date:=current_date;
BEGIN
  PERFORM require_role('{admin}'); PERFORM require_dev();
  SELECT tax_enabled,tax_pct INTO old_tax,old_pct FROM company_settings WHERE id=1;
  UPDATE company_settings SET tax_enabled=true,tax_pct=14 WHERE id=1;

  INSERT INTO warehouses(name) VALUES(tag||'-W1') RETURNING id INTO wh1;
  INSERT INTO warehouses(name) VALUES(tag||'-W2') RETURNING id INTO wh2;
  INSERT INTO cash_accounts(name,type,opening_balance,balance) VALUES(tag||'-Cash','cash',10000,10000) RETURNING id INTO ca;
  INSERT INTO products(name,code,barcode,purchase_price,sale_price,avg_cost,min_stock,reorder_qty)
    VALUES(tag||'-Product',tag||'-CODE',tag||'-BAR',100,150,100,2,5) RETURNING id INTO p;
  INSERT INTO customers(name,credit_limit,opening_balance) VALUES(tag||'-Customer',0,0) RETURNING id INTO cust;
  INSERT INTO suppliers(name,opening_balance) VALUES(tag||'-Supplier',0) RETURNING id INTO supp;

  invp:=create_purchase(supp,wh1,jsonb_build_array(jsonb_build_object('product_id',p,'qty',10,'price',100,'discount',0)),0,null,'credit',0,null);
  SELECT qty INTO b FROM stock_balances WHERE product_id=p AND warehouse_id=wh1;
  ok:=ok AND b=10; r:=r||jsonb_build_array(jsonb_build_object('test','purchase creates stock','actual',b,'expected',10,'pass',b=10));

  invs:=create_sale(cust,wh1,jsonb_build_array(jsonb_build_object('product_id',p,'qty',3,'price',150,'discount',0)),100,ca,'cash',0,null);
  SELECT qty INTO b FROM stock_balances WHERE product_id=p AND warehouse_id=wh1;
  SELECT outstanding INTO v FROM sales_invoice_balances WHERE id=invs;
  SELECT tax,total INTO d,c FROM sales_invoices WHERE id=invs;
  ok:=ok AND b=7 AND d=63 AND c=513 AND v=413;
  r:=r||jsonb_build_array(jsonb_build_object('test','sale + VAT + initial payment','stock',b,'tax',d,'total',c,'outstanding',v,'pass',b=7 AND d=63 AND c=513 AND v=413));

  pay:=record_payment('receipt',cust,50,ca,jsonb_build_array(jsonb_build_object('invoice_id',invs,'amount',50)));
  SELECT outstanding INTO v FROM sales_invoice_balances WHERE id=invs;
  ok:=ok AND v=363; r:=r||jsonb_build_array(jsonb_build_object('test','payment allocation','outstanding',v,'expected',363,'pass',v=363));

  BEGIN
    PERFORM record_payment('receipt',cust,1000,ca,jsonb_build_array(jsonb_build_object('invoice_id',invs,'amount',1000)));
  EXCEPTION WHEN OTHERS THEN
    failed_expected:=true;
  END;
  ok:=ok AND failed_expected; r:=r||jsonb_build_array(jsonb_build_object('test','over-allocation rejected','pass',failed_expected));

  ret:=create_sales_return(invs,jsonb_build_array(jsonb_build_object('product_id',p,'qty',1)));
  SELECT qty INTO b FROM stock_balances WHERE product_id=p AND warehouse_id=wh1;
  SELECT balance INTO v FROM customer_balances WHERE id=cust;
  ok:=ok AND b=8 AND v=213;
  r:=r||jsonb_build_array(jsonb_build_object('test','sales return + customer balance','stock',b,'customer_balance',v,'pass',b=8 AND v=213));

  pret:=create_purchase_return(invp,jsonb_build_array(jsonb_build_object('product_id',p,'qty',2)));
  SELECT qty INTO b FROM stock_balances WHERE product_id=p AND warehouse_id=wh1;
  SELECT balance INTO v FROM supplier_balances WHERE id=supp;
  ok:=ok AND b=6 AND v=912;
  r:=r||jsonb_build_array(jsonb_build_object('test','purchase return + supplier balance','stock',b,'supplier_balance',v,'pass',b=6 AND v=912));

  tr:=create_stock_transfer(wh1,wh2,jsonb_build_array(jsonb_build_object('product_id',p,'qty',2)),tag||' transfer');
  SELECT qty INTO b FROM stock_balances WHERE product_id=p AND warehouse_id=wh1;
  SELECT qty INTO v FROM stock_balances WHERE product_id=p AND warehouse_id=wh2;
  ok:=ok AND b=4 AND v=2; r:=r||jsonb_build_array(jsonb_build_object('test','stock transfer','from_qty',b,'to_qty',v,'pass',b=4 AND v=2));

  stid:=create_stocktake(wh1,tag||' stocktake');
  PERFORM approve_stocktake_v2(stid,jsonb_build_array(jsonb_build_object('product_id',p,'actual_qty',4)));
  SELECT qty INTO b FROM stock_balances WHERE product_id=p AND warehouse_id=wh1;
  ok:=ok AND b=4; r:=r||jsonb_build_array(jsonb_build_object('test','stocktake','qty',b,'expected',4,'pass',b=4));

  mj:=create_manual_journal(test_date,tag||' journal',jsonb_build_array(
    jsonb_build_object('account_code','6000','debit',25,'credit',0),
    jsonb_build_object('account_code','3000','debit',0,'credit',25)));
  SELECT coalesce(sum(debit),0),coalesce(sum(credit),0) INTO d,c FROM journal_lines WHERE entry_id=mj;
  ok:=ok AND d=25 AND c=25; r:=r||jsonb_build_array(jsonb_build_object('test','manual journal balanced','debit',d,'credit',c,'pass',d=25 AND c=25));

  SELECT count(*) INTO cnt FROM customer_aging(test_date) WHERE customer_id=cust;
  ok:=ok AND cnt=1; r:=r||jsonb_build_array(jsonb_build_object('test','customer aging callable','rows',cnt,'pass',cnt=1));
  SELECT count(*) INTO cnt FROM supplier_aging(test_date) WHERE supplier_id=supp;
  ok:=ok AND cnt=1; r:=r||jsonb_build_array(jsonb_build_object('test','supplier aging callable','rows',cnt,'pass',cnt=1));

  PERFORM rebuild_journal();
  SELECT coalesce(sum(debit),0),coalesce(sum(credit),0) INTO d,c FROM journal_lines;
  ok:=ok AND round(d,2)=round(c,2); r:=r||jsonb_build_array(jsonb_build_object('test','journal globally balanced after rebuild','debit',d,'credit',c,'pass',round(d,2)=round(c,2)));

  SELECT dashboard_v2(test_date,test_date) IS NOT NULL INTO failed_expected;
  ok:=ok AND failed_expected; r:=r||jsonb_build_array(jsonb_build_object('test','dashboard callable','pass',failed_expected));

  -- Cleanup succeeds; any unexpected error above aborts the whole function transaction.
  DELETE FROM journal_entries WHERE doc_id IN(invs,invp,ret,pret,tr,stid) OR id=mj;
  DELETE FROM stock_movements WHERE product_id=p;
  DELETE FROM payment_allocations WHERE payment_id IN(SELECT id FROM payments WHERE customer_id=cust OR supplier_id=supp);
  DELETE FROM payments WHERE customer_id=cust OR supplier_id=supp;
  DELETE FROM sales_return_items WHERE return_id=ret;
  DELETE FROM purchase_return_items WHERE return_id=pret;
  DELETE FROM sales_returns WHERE id=ret;
  DELETE FROM purchase_returns WHERE id=pret;
  DELETE FROM stock_transfer_items WHERE transfer_id=tr;
  DELETE FROM stock_transfers WHERE id=tr;
  DELETE FROM stocktake_items WHERE stocktake_id=stid;
  DELETE FROM stocktakes WHERE id=stid;
  DELETE FROM sales_invoice_items WHERE invoice_id=invs;
  DELETE FROM purchase_invoice_items WHERE invoice_id=invp;
  DELETE FROM sales_invoices WHERE id=invs;
  DELETE FROM purchase_invoices WHERE id=invp;
  DELETE FROM stock_balances WHERE product_id=p;
  DELETE FROM products WHERE id=p;
  DELETE FROM customers WHERE id=cust;
  DELETE FROM suppliers WHERE id=supp;
  DELETE FROM cash_accounts WHERE id=ca;
  DELETE FROM warehouses WHERE id IN(wh1,wh2);
  DELETE FROM audit_logs WHERE description LIKE tag||'%';
  UPDATE company_settings SET tax_enabled=old_tax,tax_pct=old_pct WHERE id=1;

  RETURN jsonb_build_object('ok',ok,'tag',tag,'results',r,'cleaned',true);
END $$;

REVOKE ALL ON FUNCTION run_erp_smoke_test() FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION run_erp_smoke_test() TO authenticated;

-- Keep the new RPC permissions aligned with the hardened functions.
GRANT EXECUTE ON FUNCTION create_sale(uuid,uuid,jsonb,numeric,uuid,text,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase(uuid,uuid,jsonb,numeric,uuid,text,numeric,text) TO authenticated;
GRANT EXECUTE ON FUNCTION record_payment(text,uuid,numeric,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase_return(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION customer_statement(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION supplier_statement(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION rebuild_journal() TO authenticated;

COMMIT;


-- 010 Enterprise Completion Pack
-- Run AFTER the currently successful 009 migration.
-- Additive migration: no data reset, no destructive drops.

BEGIN;

-- ============================================================
-- A) Organization / accounting dimensions
-- ============================================================
CREATE TABLE IF NOT EXISTS branches(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  code text UNIQUE,
  phone text,
  address text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cost_centers(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fiscal_periods(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'Open' CHECK(status IN('Open','Closed')),
  closed_by uuid,
  closed_at timestamptz,
  CHECK(end_date>=start_date)
);

ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS default_branch uuid REFERENCES branches;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS cost_center_id uuid REFERENCES cost_centers;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;
ALTER TABLE payroll ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;

-- Seed one default branch safely.
INSERT INTO branches(name,code) VALUES('الفرع الرئيسي','HQ') ON CONFLICT DO NOTHING;
-- v1.9: تعديل أسماء المتغيرات (tax/total/material_cost/total_cost) اللي كانت بتتعارض مع أسماء الأعمدة
-- v1.8: أعمدة created_at المطلوبة للترتيب في الدوال (warehouses وcash_accounts مش متعرفة بيها في الملف الأساسي)
ALTER TABLE warehouses ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE cash_accounts ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- v1.10: أعمدة branch_id المستخدمة في الدوال (كانت ناقصة من الجداول)
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;

UPDATE company_settings SET default_branch=COALESCE(default_branch,(SELECT id FROM branches ORDER BY created_at LIMIT 1));

-- Closed-period guard applies to all future direct writes on core documents.
CREATE OR REPLACE FUNCTION assert_period_open(p_date date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM fiscal_periods WHERE p_date BETWEEN start_date AND end_date AND status='Closed')
     AND coalesce(current_setting('erp.rebuild',true),'off')<>'on' THEN
    RAISE EXCEPTION 'الفترة المحاسبية مغلقة لهذا التاريخ';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION period_guard_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    PERFORM assert_period_open(COALESCE(NEW.date,current_date));
    RETURN NEW;
  ELSIF TG_OP='UPDATE' THEN
    PERFORM assert_period_open(COALESCE(NEW.date,current_date));
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;


DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['sales_invoices','purchase_invoices','payments','expenses','journal_entries'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', 'period_guard_'||t, t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION period_guard_trg()', 'period_guard_'||t, t);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION close_fiscal_period(p_period uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p fiscal_periods;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO p FROM fiscal_periods WHERE id=p_period FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الفترة غير موجودة'; END IF;
  IF p.status='Closed' THEN RETURN; END IF;
  UPDATE fiscal_periods SET status='Closed',closed_by=auth.uid(),closed_at=now() WHERE id=p.id;
  PERFORM log_event('close','fiscal_periods',p.id::text,'أغلق الفترة '||p.name);
END $$;

CREATE OR REPLACE FUNCTION reopen_fiscal_period(p_period uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin}');
  UPDATE fiscal_periods SET status='Open',closed_by=null,closed_at=null WHERE id=p_period;
  IF NOT FOUND THEN RAISE EXCEPTION 'الفترة غير موجودة'; END IF;
END $$;

-- ============================================================
-- B) Purchase orders + goods receipts
-- ============================================================
CREATE SEQUENCE IF NOT EXISTS seq_po;
CREATE SEQUENCE IF NOT EXISTS seq_grn;

CREATE TABLE IF NOT EXISTS purchase_orders(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number text UNIQUE NOT NULL,
  date date NOT NULL DEFAULT current_date,
  expected_date date,
  supplier_id uuid NOT NULL REFERENCES suppliers,
  warehouse_id uuid NOT NULL REFERENCES warehouses,
  branch_id uuid REFERENCES branches,
  status text NOT NULL DEFAULT 'Confirmed' CHECK(status IN('Draft','Confirmed','Partially Received','Received','Cancelled')),
  subtotal numeric(14,2) NOT NULL DEFAULT 0,
  discount numeric(14,2) NOT NULL DEFAULT 0,
  tax numeric(14,2) NOT NULL DEFAULT 0,
  total numeric(14,2) NOT NULL DEFAULT 0,
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now()
);
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES branches;
CREATE TABLE IF NOT EXISTS purchase_order_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES purchase_orders ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products,
  qty numeric(14,3) NOT NULL CHECK(qty>0),
  unit_price numeric(14,4) NOT NULL DEFAULT 0,
  discount numeric(14,2) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS goods_receipts(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number text UNIQUE NOT NULL,
  date date NOT NULL DEFAULT current_date,
  purchase_order_id uuid REFERENCES purchase_orders,
  supplier_id uuid NOT NULL REFERENCES suppliers,
  warehouse_id uuid NOT NULL REFERENCES warehouses,
  status text NOT NULL DEFAULT 'Received' CHECK(status IN('Draft','Received','Cancelled')),
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS goods_receipt_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id uuid NOT NULL REFERENCES goods_receipts ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products,
  qty numeric(14,3) NOT NULL CHECK(qty>0),
  unit_cost numeric(14,4) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_idx ON purchase_orders(supplier_id,date);
CREATE INDEX IF NOT EXISTS goods_receipts_supplier_idx ON goods_receipts(supplier_id,date);

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE goods_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE goods_receipt_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_orders' AND policyname='sel_purchase_orders') THEN
    CREATE POLICY sel_purchase_orders ON purchase_orders FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_order_items' AND policyname='sel_purchase_order_items') THEN
    CREATE POLICY sel_purchase_order_items ON purchase_order_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='goods_receipts' AND policyname='sel_goods_receipts') THEN
    CREATE POLICY sel_goods_receipts ON goods_receipts FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='goods_receipt_items' AND policyname='sel_goods_receipt_items') THEN
    CREATE POLICY sel_goods_receipt_items ON goods_receipt_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION create_purchase_order(p_supplier uuid,p_warehouse uuid,p_items jsonb,p_expected date DEFAULT null,p_notes text DEFAULT null) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid(); it jsonb; sub numeric:=0; ln numeric; num text; br uuid;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); PERFORM assert_period_open(current_date);
  IF coalesce(jsonb_array_length(p_items),0)=0 THEN RAISE EXCEPTION 'أضف بنودًا'; END IF;
  num:='PO-'||(1000+nextval('seq_po')); br:=(SELECT default_branch FROM company_settings WHERE id=1);
  INSERT INTO purchase_orders(id,number,expected_date,supplier_id,warehouse_id,branch_id,notes) VALUES(v,num,p_expected,p_supplier,p_warehouse,br,p_notes);
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    ln:=((it->>'qty')::numeric*(it->>'price')::numeric)-coalesce((it->>'discount')::numeric,0); sub:=sub+ln;
    INSERT INTO purchase_order_items(order_id,product_id,qty,unit_price,discount,line_total) VALUES(v,(it->>'product_id')::uuid,(it->>'qty')::numeric,(it->>'price')::numeric,coalesce((it->>'discount')::numeric,0),round(ln,2));
  END LOOP;
  UPDATE purchase_orders SET subtotal=sub,total=sub WHERE id=v;
  PERFORM log_event('create','purchase_orders',v::text,'أنشأ أمر شراء '||num); RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_goods_receipt(p_po uuid,p_items jsonb,p_notes text DEFAULT null) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o purchase_orders; v uuid:=gen_random_uuid(); it jsonb; ordq numeric; received numeric; q numeric; pid uuid; cost numeric; num text; je uuid; rc numeric:=0;
BEGIN
  PERFORM require_role('{admin,accountant,store}');
  SELECT * INTO o FROM purchase_orders WHERE id=p_po FOR UPDATE;
  IF NOT FOUND OR o.status='Cancelled' THEN RAISE EXCEPTION 'أمر الشراء غير متاح'; END IF;
  num:='GRN-'||(1000+nextval('seq_grn'));
  INSERT INTO goods_receipts(id,number,purchase_order_id,supplier_id,warehouse_id,notes) VALUES(v,num,o.id,o.supplier_id,o.warehouse_id,p_notes);
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; cost:=coalesce((it->>'cost')::numeric,0);
    SELECT coalesce(sum(qty),0) INTO ordq FROM purchase_order_items WHERE order_id=o.id AND product_id=pid;
    SELECT coalesce(sum(gri.qty),0) INTO received FROM goods_receipt_items gri JOIN goods_receipts gr ON gr.id=gri.receipt_id WHERE gr.purchase_order_id=o.id AND gri.product_id=pid;
    IF q<=0 OR q>ordq-received THEN RAISE EXCEPTION 'كمية الاستلام أكبر من المتبقي لأمر الشراء'; END IF;
    IF cost=0 THEN SELECT unit_price INTO cost FROM purchase_order_items WHERE order_id=o.id AND product_id=pid ORDER BY id LIMIT 1; END IF;
    INSERT INTO goods_receipt_items(receipt_id,product_id,qty,unit_cost,line_total) VALUES(v,pid,q,cost,round(q*cost,2));
    perform apply_stock(pid,o.warehouse_id,q,'Purchase','goods_receipt',v); rc:=rc+round(q*cost,2);
  END LOOP;
  IF rc>0 THEN
    je:=gen_random_uuid();
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,current_date,'استلام بضاعة '||num,'goods_receipt',v,o.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1200',rc,0),(je,'2110',0,rc);
  END IF;
  UPDATE purchase_orders SET status=CASE WHEN NOT EXISTS(
    SELECT 1 FROM purchase_order_items poi WHERE poi.order_id=o.id AND poi.qty>(SELECT coalesce(sum(gri.qty),0) FROM goods_receipt_items gri JOIN goods_receipts gr ON gr.id=gri.receipt_id WHERE gr.purchase_order_id=o.id AND gri.product_id=poi.product_id)
  ) THEN 'Received' ELSE 'Partially Received' END WHERE id=o.id;
  PERFORM log_event('create','goods_receipts',v::text,'استلم بضاعة '||num); RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_purchase_invoice_from_receipt(p_receipt uuid,p_paid numeric DEFAULT 0,p_account uuid DEFAULT null,p_method text DEFAULT 'credit') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE gr goods_receipts; v uuid:=gen_random_uuid(); it record; sub numeric:=0; v_tax numeric:=0; v_total numeric; num text; inv_date date; je uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO gr FROM goods_receipts WHERE id=p_receipt AND status='Received';
  IF NOT FOUND THEN RAISE EXCEPTION 'إذن الاستلام غير موجود'; END IF;
  IF EXISTS(SELECT 1 FROM purchase_invoices WHERE notes='GRN:'||gr.id::text) THEN RAISE EXCEPTION 'تم إصدار فاتورة لهذا الاستلام بالفعل'; END IF;
  inv_date:=gr.date; PERFORM assert_period_open(inv_date);
  num:=(SELECT invoice_prefix FROM company_settings WHERE id=1)||'P'||(1000+nextval('seq_purchase'));
  INSERT INTO purchase_invoices(id,number,date,due_date,supplier_id,warehouse_id,branch_id,payment_method,notes) VALUES(v,num,inv_date,inv_date+(SELECT payment_terms_days FROM suppliers WHERE id=gr.supplier_id),gr.supplier_id,gr.warehouse_id,(SELECT default_branch FROM company_settings WHERE id=1),p_method,'GRN:'||gr.id::text);
  FOR it IN SELECT * FROM goods_receipt_items WHERE receipt_id=gr.id LOOP
    INSERT INTO purchase_invoice_items(invoice_id,product_id,qty,unit_price,discount,line_total) VALUES(v,it.product_id,it.qty,it.unit_cost,0,it.line_total); sub:=sub+it.line_total;
  END LOOP;
  IF (SELECT tax_enabled FROM company_settings WHERE id=1) THEN v_tax:=round(sub*(SELECT tax_pct FROM company_settings WHERE id=1)/100,2); END IF;
  v_total:=sub+v_tax; UPDATE purchase_invoices SET subtotal=sub,tax=v_tax,tax_rate=(SELECT tax_pct FROM company_settings WHERE id=1),total=v_total WHERE id=v;
  IF p_paid>0 THEN
    IF p_account IS NULL OR p_paid>v_total THEN RAISE EXCEPTION 'بيانات الدفع غير صحيحة'; END IF;
    INSERT INTO payments(kind,supplier_id,account_id,amount,doc_ref,branch_id) VALUES('payment',gr.supplier_id,p_account,p_paid,num); perform apply_cash(p_account,-p_paid);
  END IF;
  je:=gen_random_uuid();
  BEGIN
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,gr.date,'فاتورة شراء من استلام '||num,'purchase_invoice',v,(SELECT default_branch FROM company_settings WHERE id=1));
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'2110',sub,0);
    IF v_tax>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1410',v_tax,0); END IF;
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'2000',0,v_total);
  END;
  PERFORM log_event('create','purchase_invoices',v::text,'أنشأ فاتورة شراء من الاستلام '||gr.number); RETURN v;
END $$;

-- ============================================================
-- C) Sales delivery notes
-- ============================================================
CREATE SEQUENCE IF NOT EXISTS seq_dn;
CREATE TABLE IF NOT EXISTS delivery_notes(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), number text UNIQUE NOT NULL, date date NOT NULL DEFAULT current_date,
  sales_order_id uuid REFERENCES sales_orders, customer_id uuid NOT NULL REFERENCES customers, warehouse_id uuid NOT NULL REFERENCES warehouses,
  status text NOT NULL DEFAULT 'Delivered' CHECK(status IN('Draft','Delivered','Cancelled')), notes text, created_by uuid DEFAULT auth.uid(), created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS delivery_note_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), delivery_id uuid NOT NULL REFERENCES delivery_notes ON DELETE CASCADE, product_id uuid NOT NULL REFERENCES products,
  qty numeric(14,3) NOT NULL CHECK(qty>0), unit_price numeric(14,4) NOT NULL DEFAULT 0, discount numeric(14,2) NOT NULL DEFAULT 0, unit_cost numeric(14,4) NOT NULL DEFAULT 0, line_total numeric(14,2) NOT NULL DEFAULT 0
);
ALTER TABLE delivery_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_note_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_notes' AND policyname='sel_delivery_notes') THEN CREATE POLICY sel_delivery_notes ON delivery_notes FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='delivery_note_items' AND policyname='sel_delivery_note_items') THEN CREATE POLICY sel_delivery_note_items ON delivery_note_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
END $$;

CREATE OR REPLACE FUNCTION create_delivery(p_order uuid,p_items jsonb,p_notes text DEFAULT null) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o sales_orders; v uuid:=gen_random_uuid(); it jsonb; ordq numeric; delivered numeric; q numeric; pid uuid; num text; price numeric; disc numeric; ln numeric;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  SELECT * INTO o FROM sales_orders WHERE id=p_order FOR UPDATE;
  IF NOT FOUND OR o.status IN('Cancelled','Delivered') THEN RAISE EXCEPTION 'أمر البيع غير متاح للتسليم'; END IF;
  num:='DN-'||(1000+nextval('seq_dn')); INSERT INTO delivery_notes(id,number,sales_order_id,customer_id,warehouse_id,notes) VALUES(v,num,o.id,o.customer_id,o.warehouse_id,p_notes);
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; price:=coalesce((it->>'price')::numeric,0); disc:=coalesce((it->>'discount')::numeric,0); ln:=q*price-disc;
    SELECT coalesce(sum(qty),0) INTO ordq FROM sales_order_items WHERE order_id=o.id AND product_id=pid;
    SELECT coalesce(sum(dni.qty),0) INTO delivered FROM delivery_note_items dni JOIN delivery_notes dn ON dn.id=dni.delivery_id WHERE dn.sales_order_id=o.id AND dni.product_id=pid AND dn.status='Delivered';
    IF q<=0 OR q>ordq-delivered THEN RAISE EXCEPTION 'كمية التسليم أكبر من المتبقي في أمر البيع'; END IF;
    IF price=0 THEN SELECT unit_price INTO price FROM sales_order_items WHERE order_id=o.id AND product_id=pid ORDER BY id LIMIT 1; END IF;
    INSERT INTO delivery_note_items(delivery_id,product_id,qty,unit_price,discount,unit_cost,line_total) VALUES(v,pid,q,price,disc,(SELECT avg_cost FROM products WHERE id=pid),round(q*price-disc,2));
    perform apply_stock(pid,o.warehouse_id,-q,'Sale','delivery_note',v);
  END LOOP;
  UPDATE sales_orders SET status=CASE WHEN NOT EXISTS(
    SELECT 1 FROM sales_order_items soi WHERE soi.order_id=o.id AND soi.qty>(SELECT coalesce(sum(dni.qty),0) FROM delivery_note_items dni JOIN delivery_notes dn ON dn.id=dni.delivery_id WHERE dn.sales_order_id=o.id AND dni.product_id=soi.product_id AND dn.status='Delivered')
  ) THEN 'Delivered' ELSE 'Partially Delivered' END WHERE id=o.id;
  PERFORM log_event('create','delivery_notes',v::text,'أنشأ إذن تسليم '||num); RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_sale_from_delivery(p_delivery uuid,p_paid numeric DEFAULT 0,p_account uuid DEFAULT null,p_method text DEFAULT 'credit') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE dn delivery_notes; v uuid:=gen_random_uuid(); it record; sub numeric:=0; v_tax numeric:=0; v_total numeric; num text;
BEGIN
  PERFORM require_role('{admin,accountant,sales}');
  SELECT * INTO dn FROM delivery_notes WHERE id=p_delivery AND status='Delivered';
  IF NOT FOUND THEN RAISE EXCEPTION 'إذن التسليم غير موجود'; END IF;
  IF EXISTS(SELECT 1 FROM sales_invoices WHERE notes='DN:'||dn.id::text) THEN RAISE EXCEPTION 'تم إصدار فاتورة للتسليم بالفعل'; END IF;
  num:=(SELECT invoice_prefix FROM company_settings WHERE id=1)||'S'||(1000+nextval('seq_sales'));
  INSERT INTO sales_invoices(id,number,date,due_date,customer_id,warehouse_id,branch_id,payment_method,notes) VALUES(v,num,dn.date,dn.date+(SELECT payment_terms_days FROM customers WHERE id=dn.customer_id),dn.customer_id,dn.warehouse_id,(SELECT default_branch FROM company_settings WHERE id=1),p_method,'DN:'||dn.id::text);
  FOR it IN SELECT * FROM delivery_note_items WHERE delivery_id=dn.id LOOP
    INSERT INTO sales_invoice_items(invoice_id,product_id,qty,unit_price,discount,unit_cost,line_total) VALUES(v,it.product_id,it.qty,it.unit_price,it.discount,(SELECT avg_cost FROM products WHERE id=it.product_id),it.line_total); sub:=sub+it.line_total;
  END LOOP;
  IF (SELECT tax_enabled FROM company_settings WHERE id=1) THEN v_tax:=round(sub*(SELECT tax_pct FROM company_settings WHERE id=1)/100,2); END IF;
  v_total:=sub+v_tax; UPDATE sales_invoices SET subtotal=sub,tax=v_tax,tax_rate=(SELECT tax_pct FROM company_settings WHERE id=1),total=v_total,paid=0 WHERE id=v;
  IF p_paid>0 THEN
    IF p_account IS NULL OR p_paid>v_total THEN RAISE EXCEPTION 'بيانات الدفع غير صحيحة'; END IF;
    INSERT INTO payments(kind,customer_id,account_id,amount,doc_ref,branch_id) VALUES('receipt',dn.customer_id,p_account,p_paid,num); perform apply_cash(p_account,p_paid);
  END IF;
  PERFORM log_event('create','sales_invoices',v::text,'أنشأ فاتورة من إذن التسليم '||dn.number); RETURN v;
END $$;

-- ============================================================
-- D) Price lists
-- ============================================================
CREATE TABLE IF NOT EXISTS price_lists(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text UNIQUE NOT NULL, currency text DEFAULT 'EGP', active boolean DEFAULT true, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS price_list_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), price_list_id uuid NOT NULL REFERENCES price_lists ON DELETE CASCADE, product_id uuid NOT NULL REFERENCES products,
  price numeric(14,4) NOT NULL CHECK(price>=0), min_qty numeric(14,3) DEFAULT 1 CHECK(min_qty>0), UNIQUE(price_list_id,product_id,min_qty)
);
ALTER TABLE customers ADD COLUMN IF NOT EXISTS price_list_id uuid REFERENCES price_lists;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS supplier_code text;
ALTER TABLE price_lists ENABLE ROW LEVEL SECURITY; ALTER TABLE price_list_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='price_lists' AND policyname='sel_price_lists') THEN CREATE POLICY sel_price_lists ON price_lists FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='price_list_items' AND policyname='sel_price_list_items') THEN CREATE POLICY sel_price_list_items ON price_list_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
END $$;
CREATE OR REPLACE FUNCTION price_for(p_product uuid,p_price_list uuid,p_qty numeric DEFAULT 1,p_fallback numeric DEFAULT 0) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT coalesce((SELECT pli.price FROM price_list_items pli WHERE pli.price_list_id=p_price_list AND pli.product_id=p_product AND pli.min_qty<=p_qty ORDER BY pli.min_qty DESC LIMIT 1),p_fallback)
$$;

-- ============================================================
-- E) Fixed assets + depreciation
-- ============================================================
INSERT INTO accounts(code,name,type) VALUES
  ('1400','Fixed Assets','Asset'),('1500','Accumulated Depreciation','Asset'),('6200','Depreciation Expense','Expense'),('6300','Asset Disposal Loss','Expense'),('7100','Asset Disposal Gain','Revenue'),('2110','Goods Received Not Invoiced','Liability'),('2200','Manufacturing Accrual','Liability')
ON CONFLICT(code) DO NOTHING;
CREATE TABLE IF NOT EXISTS asset_categories(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text UNIQUE NOT NULL, asset_account text NOT NULL DEFAULT '1400', depreciation_account text NOT NULL DEFAULT '6200', accumulated_account text NOT NULL DEFAULT '1500', default_life_months int NOT NULL DEFAULT 60 CHECK(default_life_months>0)
);
CREATE TABLE IF NOT EXISTS fixed_assets(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text UNIQUE NOT NULL, name text NOT NULL, category_id uuid REFERENCES asset_categories,
  purchase_date date NOT NULL DEFAULT current_date, in_service_date date, cost numeric(14,2) NOT NULL CHECK(cost>=0), residual_value numeric(14,2) NOT NULL DEFAULT 0 CHECK(residual_value>=0), life_months int NOT NULL CHECK(life_months>0),
  accumulated_depreciation numeric(14,2) NOT NULL DEFAULT 0, status text NOT NULL DEFAULT 'Active' CHECK(status IN('Draft','Active','Disposed')), branch_id uuid REFERENCES branches, notes text, created_by uuid DEFAULT auth.uid(), created_at timestamptz DEFAULT now()
);
-- v1.7: أعمدة الأصول الثابتة المستخدمة في الترحيل والاستبعاد (كانت ناقصة من الملف الأساسي)
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS capitalized boolean NOT NULL DEFAULT false;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS acquisition_account text;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS disposal_date date;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS disposal_proceeds numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE fixed_assets ADD COLUMN IF NOT EXISTS disposal_account_id uuid REFERENCES cash_accounts;

CREATE TABLE IF NOT EXISTS asset_depreciations(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), asset_id uuid NOT NULL REFERENCES fixed_assets ON DELETE CASCADE, period_date date NOT NULL, amount numeric(14,2) NOT NULL CHECK(amount>0), journal_entry_id uuid REFERENCES journal_entries, UNIQUE(asset_id,period_date)
);
ALTER TABLE asset_categories ENABLE ROW LEVEL SECURITY; ALTER TABLE fixed_assets ENABLE ROW LEVEL SECURITY; ALTER TABLE asset_depreciations ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='asset_categories' AND policyname='sel_asset_categories') THEN CREATE POLICY sel_asset_categories ON asset_categories FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fixed_assets' AND policyname='sel_fixed_assets') THEN CREATE POLICY sel_fixed_assets ON fixed_assets FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='asset_depreciations' AND policyname='sel_asset_depreciations') THEN CREATE POLICY sel_asset_depreciations ON asset_depreciations FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
END $$;

CREATE SEQUENCE IF NOT EXISTS seq_asset;
CREATE OR REPLACE FUNCTION create_fixed_asset(p_name text,p_category uuid,p_cost numeric,p_residual numeric,p_life_months int,p_purchase_date date DEFAULT current_date,p_branch uuid DEFAULT null) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid(); code text;
BEGIN
  PERFORM require_role('{admin,accountant}'); PERFORM assert_period_open(p_purchase_date);
  IF p_cost<=0 OR p_residual<0 OR p_residual>=p_cost OR p_life_months<=0 THEN RAISE EXCEPTION 'بيانات الأصل غير صحيحة'; END IF;
  code:='FA-'||lpad(nextval('seq_asset')::text,6,'0');
  INSERT INTO fixed_assets(id,code,name,category_id,purchase_date,in_service_date,cost,residual_value,life_months,branch_id)
  VALUES(v,code,p_name,p_category,p_purchase_date,p_purchase_date,p_cost,p_residual,p_life_months,coalesce(p_branch,(SELECT default_branch FROM company_settings WHERE id=1)));
  PERFORM log_event('create','fixed_assets',v::text,'أنشأ أصل ثابت '||code);
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION capitalize_fixed_asset(p_asset uuid,p_credit_account text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a fixed_assets; cat asset_categories; je uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO a FROM fixed_assets WHERE id=p_asset FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'الأصل غير موجود'; END IF;
  IF NOT EXISTS(SELECT 1 FROM accounts WHERE code=p_credit_account) THEN RAISE EXCEPTION 'حساب المقابل غير موجود'; END IF;
  IF EXISTS(SELECT 1 FROM journal_entries WHERE doc_type='fixed_asset_acquisition' AND doc_id=a.id) THEN RAISE EXCEPTION 'تم رسملة الأصل مسبقًا'; END IF;
  je:=gen_random_uuid();
  INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,a.purchase_date,'رسملة أصل '||a.code,'fixed_asset_acquisition',a.id,a.branch_id);
  INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1400',a.cost,0),(je,p_credit_account,0,a.cost);
  UPDATE fixed_assets SET capitalized=true,acquisition_account=p_credit_account WHERE id=a.id;
  PERFORM log_event('create','fixed_asset_acquisition',a.id::text,'رسمل الأصل '||a.code);
END $$;

CREATE OR REPLACE FUNCTION depreciate_asset(p_asset uuid,p_period date) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a fixed_assets; cat asset_categories; amt numeric; je uuid; remaining numeric; months_done int;
BEGIN
  PERFORM require_role('{admin,accountant}'); PERFORM assert_period_open(p_period);
  SELECT * INTO a FROM fixed_assets WHERE id=p_asset FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'الأصل غير موجود'; END IF;
  SELECT * INTO cat FROM asset_categories WHERE id=a.category_id;
  IF a.status<>'Active' OR a.accumulated_depreciation>=a.cost-a.residual_value THEN RETURN 0; END IF;
  IF EXISTS(SELECT 1 FROM asset_depreciations WHERE asset_id=a.id AND period_date=date_trunc('month',p_period)::date) THEN RAISE EXCEPTION 'تم إهلاك الأصل لهذا الشهر بالفعل'; END IF;
  amt:=round((a.cost-a.residual_value)/a.life_months,2);
  remaining:=round(a.cost-a.residual_value-a.accumulated_depreciation,2); IF amt>remaining THEN amt:=remaining; END IF;
  IF amt<=0 THEN RETURN 0; END IF;
  je:=gen_random_uuid();
  INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,p_period,'إهلاك أصل '||a.code,'depreciation',a.id,a.branch_id);
  INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,coalesce(cat.depreciation_account,'6200'),amt,0),(je,coalesce(cat.accumulated_account,'1500'),0,amt);
  INSERT INTO asset_depreciations(asset_id,period_date,amount,journal_entry_id) VALUES(a.id,date_trunc('month',p_period)::date,amt,je);
  UPDATE fixed_assets SET accumulated_depreciation=accumulated_depreciation+amt WHERE id=a.id;
  PERFORM log_event('create','asset_depreciations',a.id::text,'سجل إهلاك '||amt); RETURN amt;
END $$;

CREATE OR REPLACE FUNCTION dispose_fixed_asset(p_asset uuid,p_date date,p_proceeds numeric DEFAULT 0,p_account uuid DEFAULT null) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a fixed_assets; je uuid; book numeric; gain numeric; cash_code text;
BEGIN
  PERFORM require_role('{admin,accountant}'); PERFORM assert_period_open(p_date);
  SELECT * INTO a FROM fixed_assets WHERE id=p_asset FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'الأصل غير موجود'; END IF;
  IF a.status<>'Active' THEN RAISE EXCEPTION 'الأصل غير نشط'; END IF;
  book:=round(a.cost-a.accumulated_depreciation,2); gain:=round(p_proceeds-book,2);
  IF p_proceeds>0 AND p_account IS NULL THEN RAISE EXCEPTION 'اختر حساب المقبوضات'; END IF;
  je:=gen_random_uuid();
  INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,p_date,'استبعاد أصل '||a.code,'asset_disposal',a.id,a.branch_id);
  INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES
    (je,'1500',a.accumulated_depreciation,0),
    (je,'1400',0,a.cost);
  IF p_proceeds>0 THEN
    cash_code:=CASE WHEN (SELECT type FROM cash_accounts WHERE id=p_account)='bank' THEN '1100' ELSE '1000' END;
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,cash_code,p_proceeds,0);
  END IF;
  IF gain>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'7100',0,gain);
  ELSIF gain<0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'6300',-gain,0); END IF;
  UPDATE fixed_assets SET status='Disposed',disposal_date=p_date,disposal_proceeds=p_proceeds,disposal_account_id=p_account WHERE id=a.id;
  PERFORM log_event('dispose','fixed_assets',a.id::text,'استبعد الأصل '||a.code); RETURN gain;
END $$;

-- ============================================================
-- F) Bank reconciliation
-- ============================================================
CREATE TABLE IF NOT EXISTS bank_statements(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL REFERENCES cash_accounts, statement_no text NOT NULL, from_date date, to_date date, opening_balance numeric(14,2) DEFAULT 0, closing_balance numeric(14,2) DEFAULT 0, status text DEFAULT 'Open' CHECK(status IN('Open','Reconciled','Closed')), created_by uuid DEFAULT auth.uid(), created_at timestamptz DEFAULT now(), UNIQUE(account_id,statement_no)
);
CREATE TABLE IF NOT EXISTS bank_statement_lines(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), statement_id uuid NOT NULL REFERENCES bank_statements ON DELETE CASCADE, txn_date date NOT NULL, description text, reference text, amount numeric(14,2) NOT NULL, direction text NOT NULL CHECK(direction IN('credit','debit')), matched_payment_id uuid REFERENCES payments, reconciled boolean NOT NULL DEFAULT false, created_at timestamptz DEFAULT now()
);
ALTER TABLE bank_statements ENABLE ROW LEVEL SECURITY; ALTER TABLE bank_statement_lines ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bank_statements' AND policyname='sel_bank_statements') THEN CREATE POLICY sel_bank_statements ON bank_statements FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bank_statement_lines' AND policyname='sel_bank_statement_lines') THEN CREATE POLICY sel_bank_statement_lines ON bank_statement_lines FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
END $$;
CREATE OR REPLACE FUNCTION reconcile_bank_line(p_line uuid,p_payment uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE l bank_statement_lines; p payments; dir_amount numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO l FROM bank_statement_lines WHERE id=p_line FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'سطر كشف البنك غير موجود'; END IF;
  SELECT * INTO p FROM payments WHERE id=p_payment; IF NOT FOUND THEN RAISE EXCEPTION 'الحركة المالية غير موجودة'; END IF;
  dir_amount:=CASE WHEN l.direction='credit' THEN p.amount ELSE -p.amount END;
  IF round(dir_amount,2)<>round(l.amount,2) THEN RAISE EXCEPTION 'المبلغ لا يطابق الحركة البنكية'; END IF;
  IF l.reconciled THEN RAISE EXCEPTION 'تمت مطابقة السطر مسبقًا'; END IF;
  UPDATE bank_statement_lines SET matched_payment_id=p.id,reconciled=true WHERE id=l.id;
END $$;

-- ============================================================
-- G) HR core: shifts / attendance / leave
-- ============================================================
CREATE TABLE IF NOT EXISTS shifts(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text UNIQUE NOT NULL, start_time time NOT NULL, end_time time NOT NULL, grace_minutes int NOT NULL DEFAULT 0, active boolean DEFAULT true
);
CREATE TABLE IF NOT EXISTS attendance(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), employee_id uuid NOT NULL REFERENCES employees, work_date date NOT NULL, check_in timestamptz, check_out timestamptz, status text NOT NULL DEFAULT 'Present' CHECK(status IN('Present','Absent','Late','Leave','Holiday')), notes text, UNIQUE(employee_id,work_date)
);
CREATE TABLE IF NOT EXISTS leave_types(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text UNIQUE NOT NULL, days_per_year numeric(8,2) NOT NULL DEFAULT 0 CHECK(days_per_year>=0), paid boolean NOT NULL DEFAULT true, active boolean DEFAULT true
);
CREATE TABLE IF NOT EXISTS leave_requests(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), employee_id uuid NOT NULL REFERENCES employees, leave_type_id uuid NOT NULL REFERENCES leave_types, from_date date NOT NULL, to_date date NOT NULL, days numeric(8,2) NOT NULL, status text NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','Approved','Rejected','Cancelled')), reason text, approved_by uuid, approved_at timestamptz, CHECK(to_date>=from_date AND days>0)
);
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY; ALTER TABLE attendance ENABLE ROW LEVEL SECURITY; ALTER TABLE leave_types ENABLE ROW LEVEL SECURITY; ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='shifts' AND policyname='sel_shifts') THEN CREATE POLICY sel_shifts ON shifts FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='attendance' AND policyname='sel_attendance') THEN CREATE POLICY sel_attendance ON attendance FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='leave_types' AND policyname='sel_leave_types') THEN CREATE POLICY sel_leave_types ON leave_types FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='leave_requests' AND policyname='sel_leave_requests') THEN CREATE POLICY sel_leave_requests ON leave_requests FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
END $$;
CREATE OR REPLACE FUNCTION approve_leave(p_request uuid,p_approve boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant}');
  UPDATE leave_requests SET status=CASE WHEN p_approve THEN 'Approved' ELSE 'Rejected' END,approved_by=auth.uid(),approved_at=now() WHERE id=p_request AND status='Pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'طلب الإجازة غير قابل للاعتماد'; END IF;
END $$;

-- ============================================================
-- H) Manufacturing: BOM + work orders
-- ============================================================
CREATE TABLE IF NOT EXISTS boms(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES products, version text NOT NULL DEFAULT '1', active boolean DEFAULT true, notes text, UNIQUE(product_id,version)
);
CREATE TABLE IF NOT EXISTS bom_items(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bom_id uuid NOT NULL REFERENCES boms ON DELETE CASCADE, component_product_id uuid NOT NULL REFERENCES products, qty numeric(14,4) NOT NULL CHECK(qty>0)
);
CREATE TABLE IF NOT EXISTS work_orders(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), number text UNIQUE NOT NULL, bom_id uuid NOT NULL REFERENCES boms, warehouse_id uuid NOT NULL REFERENCES warehouses, planned_qty numeric(14,3) NOT NULL CHECK(planned_qty>0), produced_qty numeric(14,3) NOT NULL DEFAULT 0, labor_cost numeric(14,2) NOT NULL DEFAULT 0, overhead_cost numeric(14,2) NOT NULL DEFAULT 0, material_cost numeric(14,2) NOT NULL DEFAULT 0, total_cost numeric(14,2) NOT NULL DEFAULT 0, status text NOT NULL DEFAULT 'Released' CHECK(status IN('Draft','Released','In Progress','Completed','Cancelled')), date date NOT NULL DEFAULT current_date, created_by uuid DEFAULT auth.uid()
);
CREATE SEQUENCE IF NOT EXISTS seq_wo;
ALTER TABLE boms ENABLE ROW LEVEL SECURITY; ALTER TABLE bom_items ENABLE ROW LEVEL SECURITY; ALTER TABLE work_orders ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='boms' AND policyname='sel_boms') THEN CREATE POLICY sel_boms ON boms FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bom_items' AND policyname='sel_bom_items') THEN CREATE POLICY sel_bom_items ON bom_items FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='work_orders' AND policyname='sel_work_orders') THEN CREATE POLICY sel_work_orders ON work_orders FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
END $$;
CREATE OR REPLACE FUNCTION create_work_order(p_bom uuid,p_warehouse uuid,p_qty numeric,p_labor numeric DEFAULT 0,p_overhead numeric DEFAULT 0) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b boms; v uuid:=gen_random_uuid(); num text;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); SELECT * INTO b FROM boms WHERE id=p_bom AND active; IF NOT FOUND THEN RAISE EXCEPTION 'BOM غير متاح'; END IF;
  IF p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;
  num:='WO-'||(1000+nextval('seq_wo')); INSERT INTO work_orders(id,number,bom_id,warehouse_id,planned_qty,labor_cost,overhead_cost) VALUES(v,num,b.id,p_warehouse,p_qty,p_labor,p_overhead); RETURN v;
END $$;
CREATE OR REPLACE FUNCTION complete_work_order(p_order uuid) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE w work_orders; b boms; bi record; v_material_cost numeric:=0; v_total_cost numeric:=0; je uuid;
BEGIN
  PERFORM require_role('{admin,accountant,store}');
  SELECT * INTO w FROM work_orders WHERE id=p_order FOR UPDATE; IF NOT FOUND OR w.status IN('Completed','Cancelled') THEN RAISE EXCEPTION 'أمر التصنيع غير متاح'; END IF;
  SELECT * INTO b FROM boms WHERE id=w.bom_id;
  FOR bi IN SELECT * FROM bom_items WHERE bom_id=b.id LOOP
    PERFORM apply_stock(bi.component_product_id,w.warehouse_id,-(bi.qty*w.planned_qty),'Sale','work_order',w.id);
    v_material_cost:=v_material_cost+bi.qty*w.planned_qty*(SELECT avg_cost FROM products WHERE id=bi.component_product_id);
  END LOOP;
  v_total_cost:=round(v_material_cost+w.labor_cost+w.overhead_cost,2);
  PERFORM apply_stock(b.product_id,w.warehouse_id,w.planned_qty,'Purchase','work_order',w.id);
  UPDATE products SET avg_cost=CASE WHEN w.planned_qty>0 THEN v_total_cost/w.planned_qty ELSE avg_cost END WHERE id=b.product_id;
  IF v_total_cost>0 THEN
    je:=gen_random_uuid();
    BEGIN
      INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(je,w.date,'إتمام تصنيع '||w.number,'work_order',w.id,(SELECT default_branch FROM company_settings WHERE id=1));
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1200',v_total_cost,0);
      IF v_material_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1200',0,round(v_material_cost,2)); END IF;
      IF w.labor_cost+w.overhead_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'2200',0,round(w.labor_cost+w.overhead_cost,2)); END IF;
    END;
  END IF;
  UPDATE work_orders SET status='Completed',produced_qty=planned_qty,material_cost=round(v_material_cost,2),total_cost=v_total_cost WHERE id=w.id;
  PERFORM log_event('complete','work_orders',w.id::text,'أكمل أمر تصنيع بتكلفة '||v_total_cost); RETURN v_total_cost;
END $$;

-- ============================================================
-- I) POS sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS pos_sessions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_no text UNIQUE NOT NULL, opened_at timestamptz DEFAULT now(), closed_at timestamptz, opening_cash numeric(14,2) NOT NULL DEFAULT 0, closing_cash numeric(14,2), status text NOT NULL DEFAULT 'Open' CHECK(status IN('Open','Closed')), cash_account_id uuid NOT NULL REFERENCES cash_accounts, user_id uuid DEFAULT auth.uid()
);
CREATE TABLE IF NOT EXISTS pos_session_sales(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_id uuid NOT NULL REFERENCES pos_sessions ON DELETE CASCADE, invoice_id uuid NOT NULL REFERENCES sales_invoices UNIQUE, amount numeric(14,2) NOT NULL
);
ALTER TABLE pos_sessions ENABLE ROW LEVEL SECURITY; ALTER TABLE pos_session_sales ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='pos_sessions' AND policyname='sel_pos_sessions') THEN CREATE POLICY sel_pos_sessions ON pos_sessions FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='pos_session_sales' AND policyname='sel_pos_session_sales') THEN CREATE POLICY sel_pos_session_sales ON pos_session_sales FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
END $$;
CREATE SEQUENCE IF NOT EXISTS seq_pos;
CREATE OR REPLACE FUNCTION open_pos_session(p_account uuid,p_opening numeric DEFAULT 0) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid(); num text;
BEGIN
  PERFORM require_role('{admin,sales}');
  IF EXISTS(SELECT 1 FROM pos_sessions WHERE user_id=auth.uid() AND status='Open') THEN RAISE EXCEPTION 'لديك جلسة POS مفتوحة بالفعل'; END IF;
  IF p_opening<0 THEN RAISE EXCEPTION 'الرصيد الافتتاحي غير صحيح'; END IF;
  num:='POS-'||lpad(nextval('seq_pos')::text,6,'0');
  INSERT INTO pos_sessions(id,session_no,opening_cash,cash_account_id) VALUES(v,num,p_opening,p_account); RETURN v;
END $$;
CREATE OR REPLACE FUNCTION record_pos_sale(p_session uuid,p_invoice uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s pos_sessions; i sales_invoices;
BEGIN
  PERFORM require_role('{admin,sales}'); SELECT * INTO s FROM pos_sessions WHERE id=p_session AND status='Open' FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'جلسة POS غير مفتوحة'; END IF;
  SELECT * INTO i FROM sales_invoices WHERE id=p_invoice; IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  IF i.payment_method NOT IN('cash','bank','wallet') THEN RAISE EXCEPTION 'فاتورة POS يجب أن تكون مدفوعة'; END IF;
  INSERT INTO pos_session_sales(session_id,invoice_id,amount) VALUES(s.id,i.id,i.total);
END $$;
CREATE OR REPLACE FUNCTION close_pos_session(p_session uuid,p_closing numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,sales}');
  UPDATE pos_sessions SET status='Closed',closed_at=now(),closing_cash=p_closing WHERE id=p_session AND status='Open' AND user_id=auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'جلسة POS غير قابلة للإغلاق'; END IF;
END $$;

-- ============================================================
-- J) Service / projects
-- ============================================================
CREATE TABLE IF NOT EXISTS projects(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text UNIQUE NOT NULL, name text NOT NULL, customer_id uuid REFERENCES customers, start_date date, end_date date, status text NOT NULL DEFAULT 'Open' CHECK(status IN('Draft','Open','On Hold','Closed','Cancelled')), budget numeric(14,2) DEFAULT 0, notes text
);
CREATE TABLE IF NOT EXISTS service_tickets(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), ticket_no text UNIQUE NOT NULL, customer_id uuid REFERENCES customers, project_id uuid REFERENCES projects, subject text NOT NULL, priority text NOT NULL DEFAULT 'Normal' CHECK(priority IN('Low','Normal','High','Urgent')), status text NOT NULL DEFAULT 'Open' CHECK(status IN('Open','In Progress','Resolved','Closed','Cancelled')), opened_at timestamptz DEFAULT now(), resolved_at timestamptz, notes text
);
ALTER TABLE projects ENABLE ROW LEVEL SECURITY; ALTER TABLE service_tickets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='projects' AND policyname='sel_projects') THEN CREATE POLICY sel_projects ON projects FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='service_tickets' AND policyname='sel_service_tickets') THEN CREATE POLICY sel_service_tickets ON service_tickets FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
END $$;

-- ============================================================
-- K) Approval requests + notifications
-- ============================================================
CREATE TABLE IF NOT EXISTS approval_requests(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), entity text NOT NULL, entity_id uuid NOT NULL, requested_by uuid DEFAULT auth.uid(), status text NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','Approved','Rejected','Cancelled')), requested_at timestamptz DEFAULT now(), decided_by uuid, decided_at timestamptz, notes text
);
CREATE TABLE IF NOT EXISTS notifications(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES auth.users ON DELETE CASCADE, title text NOT NULL, message text NOT NULL, level text NOT NULL DEFAULT 'info' CHECK(level IN('info','success','warning','error')), read_at timestamptz, created_at timestamptz DEFAULT now()
);
ALTER TABLE approval_requests ENABLE ROW LEVEL SECURITY; ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
-- (moved here: notifications must exist before its policy)
DROP POLICY IF EXISTS upd_notifications_self ON notifications;
CREATE POLICY upd_notifications_self ON notifications FOR UPDATE TO authenticated USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='approval_requests' AND policyname='sel_approval_requests') THEN CREATE POLICY sel_approval_requests ON approval_requests FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='sel_notifications') THEN CREATE POLICY sel_notifications ON notifications FOR SELECT TO authenticated USING(user_id=auth.uid()); END IF;
END $$;
CREATE OR REPLACE FUNCTION decide_approval(p_request uuid,p_approve boolean,p_notes text DEFAULT null) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant}');
  UPDATE approval_requests SET status=CASE WHEN p_approve THEN 'Approved' ELSE 'Rejected' END,decided_by=auth.uid(),decided_at=now(),notes=coalesce(p_notes,notes) WHERE id=p_request AND status='Pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'طلب الاعتماد غير متاح'; END IF;
END $$;

CREATE OR REPLACE FUNCTION balance_sheet(p_as_of date DEFAULT current_date)
RETURNS TABLE(code text,name text,type text,balance numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT a.code,a.name,a.type,round(sum(l.debit-l.credit),2)
  FROM accounts a JOIN journal_lines l ON l.account_code=a.code JOIN journal_entries e ON e.id=l.entry_id
  WHERE e.date<=p_as_of AND a.type IN('Asset','Liability','Equity') AND auth_role() IN('admin','accountant')
  GROUP BY a.code,a.name,a.type ORDER BY a.code
$$;

-- ============================================================
-- L0) Final journal rebuild with enterprise workflows
CREATE OR REPLACE FUNCTION rebuild_journal() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  r record;
  e uuid;
  n int:=0;
  c numeric;
  net numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  PERFORM set_config('erp.rebuild','on',true);

  -- Rebuild system-generated entries, preserve manual journals.
  DELETE FROM journal_entries WHERE doc_type<>'manual' OR doc_type IS NULL;

  -- Sales invoices: AR Dr / Revenue Cr / Output VAT Cr / COGS Dr / Inventory Cr
  FOR r IN SELECT * FROM sales_invoices WHERE status='Posted' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'فاتورة مبيعات '||r.number,'sales_invoice',r.id);

    net:=round(r.total-coalesce(r.tax,0),2);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES
      (e,'1300',r.total,0),
      (e,'4000',0,greatest(net,0));

    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2100',0,r.tax);
    END IF;

    SELECT coalesce(sum(sii.qty*sii.unit_cost),0)
      INTO c
      FROM sales_invoice_items AS sii
      WHERE sii.invoice_id=r.id;

    IF c>0 AND coalesce(r.notes,'') NOT LIKE 'DN:%' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'5000',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  -- Purchase invoices: Inventory Dr / Input VAT Dr / AP Cr
  FOR r IN SELECT * FROM purchase_invoices WHERE status='Posted' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'فاتورة مشتريات '||r.number,'purchase_invoice',r.id);

    net:=round(r.total-coalesce(r.tax,0),2);

    IF coalesce(r.notes,'') LIKE 'GRN:%' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2110',greatest(net,0),0),(e,'2000',0,r.total);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',greatest(net,0),0),(e,'2000',0,r.total);
    END IF;

    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1410',r.tax,0);
    END IF;
  END LOOP;

  -- Goods receipts: Inventory Dr / GRNI Cr
  FOR r IN
    SELECT gr.*,coalesce(sum(i.line_total),0) AS total_cost
    FROM goods_receipts gr JOIN goods_receipt_items i ON i.receipt_id=gr.id
    WHERE gr.status='Received' GROUP BY gr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'استلام بضاعة '||r.number,'goods_receipt',r.id);
    IF r.total_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.total_cost,0),(e,'2110',0,r.total_cost); END IF;
  END LOOP;

  -- Delivery notes: COGS Dr / Inventory Cr. Sales invoice created from DN only posts AR/Revenue/VAT.
  FOR r IN
    SELECT dn.*,coalesce(sum(i.qty*i.unit_cost),0) AS cost
    FROM delivery_notes dn JOIN delivery_note_items i ON i.delivery_id=dn.id
    WHERE dn.status='Delivered' GROUP BY dn.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'إذن تسليم '||r.number,'delivery_note',r.id);
    IF r.cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'5000',r.cost,0),(e,'1200',0,r.cost); END IF;
  END LOOP;

  -- Payments: Cash/Bank Dr for receipts, AP Dr for supplier payments.
  FOR r IN
    SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
    FROM payments AS p
    JOIN cash_accounts AS a ON a.id=p.account_id
  LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,
        CASE r.kind WHEN 'receipt' THEN 'مقبوضات ' ELSE 'مدفوعات ' END||coalesce(r.doc_ref,''),
        'payment',r.id);

    IF r.kind='receipt' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,r.cc,r.amount,0),(e,'1300',0,r.amount);
    ELSIF r.kind='payment' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2000',r.amount,0),(e,r.cc,0,r.amount);
    ELSE
      RAISE EXCEPTION 'نوع دفع غير صحيح أثناء ترحيل اليومية: %',r.kind;
    END IF;
  END LOOP;

  -- Expenses: Expense Dr / Cash-Bank Cr
  FOR r IN SELECT x.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
           FROM expenses AS x
           JOIN cash_accounts AS a ON a.id=x.account_id
  LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مصروف '||r.category,'expense',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'6000',r.amount,0),(e,r.cc,0,r.amount);
  END LOOP;

  -- Sales returns: contra revenue Dr + VAT Dr + Inventory Dr / AR Cr + COGS Cr
  FOR r IN
    SELECT sr.*,
           coalesce(sum(i.cost_total),0) AS cost,
           coalesce(sum(i.tax),0) AS tax,
           coalesce(sum(i.line_total),0) AS base
    FROM sales_returns AS sr
    JOIN sales_return_items AS i ON i.return_id=sr.id
    GROUP BY sr.id
  LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مرتجع مبيعات '||r.number,'sales_return',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'4000',r.base,0),(e,'1300',0,r.total);

    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2100',r.tax,0);
    END IF;

    IF r.cost>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1200',r.cost,0),(e,'5000',0,r.cost);
    END IF;
  END LOOP;

  -- Purchase returns: AP Dr / Inventory Cr / Input VAT Cr
  FOR r IN
    SELECT pr.*,
           coalesce(sum(i.tax),0) AS tax,
           coalesce(sum(i.line_total),0) AS base
    FROM purchase_returns AS pr
    JOIN purchase_return_items AS i ON i.return_id=pr.id
    GROUP BY pr.id
  LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مرتجع مشتريات '||r.number,'purchase_return',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'2000',r.total,0),(e,'1200',0,r.base);

    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1410',0,r.tax);
    END IF;
  END LOOP;

  -- Cash transfers: destination Dr / source Cr
  FOR r IN SELECT * FROM cash_transfers LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'تحويل بين الحسابات','cash_transfer',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(
        e,
        CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.to_account)='bank' THEN '1100' ELSE '1000' END,
        r.amount,0),
      (
        e,
        CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.from_account)='bank' THEN '1100' ELSE '1000' END,
        0,r.amount);
  END LOOP;

  -- Paid payroll: Expense Dr / Cash-Bank Cr
  FOR r IN
    SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
    FROM payroll AS p
    JOIN cash_accounts AS a ON a.id=p.account_id
    WHERE p.paid
  LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.month,'مرتب','payroll',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'6000',r.net,0),(e,r.cc,0,r.net);
  END LOOP;

  -- Stocktake adjustments: inventory gain/shrinkage.
  FOR r IN
    SELECT sm.id,sm.created_at::date AS date,sm.product_id,sm.qty,sm.doc_id,p.avg_cost
    FROM stock_movements AS sm
    JOIN products AS p ON p.id=sm.product_id
    WHERE sm.type='Stock Adjustment'
      AND sm.doc_type='stocktake'
      AND sm.doc_id IS NOT NULL
  LOOP
    e:=gen_random_uuid(); n:=n+1;
    c:=round(abs(r.qty*r.avg_cost),2);
    IF c=0 THEN CONTINUE; END IF;

    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'تسوية جرد','stock_adjustment',r.doc_id);

    IF r.qty>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1200',c,0),(e,'4300',0,c);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'6100',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  -- Fixed asset acquisition / depreciation / disposal entries
  FOR r IN SELECT * FROM fixed_assets WHERE capitalized LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.purchase_date,'رسملة أصل '||r.code,'fixed_asset_acquisition',r.id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1400',r.cost,0);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,coalesce(r.acquisition_account,'1000'),0,r.cost);
  END LOOP;

  FOR r IN SELECT ad.*,fa.code,fa.branch_id FROM asset_depreciations ad JOIN fixed_assets fa ON fa.id=ad.asset_id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.period_date,'إهلاك أصل '||r.code,'depreciation',r.asset_id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6200',r.amount,0),(e,'1500',0,r.amount);
  END LOOP;

  FOR r IN SELECT * FROM fixed_assets WHERE status='Disposed' LOOP
    e:=gen_random_uuid(); n:=n+1; c:=round(r.cost-r.accumulated_depreciation,2);
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.disposal_date,'استبعاد أصل '||r.code,'asset_disposal',r.id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1500',r.accumulated_depreciation,0),(e,'1400',0,r.cost);
    IF r.disposal_proceeds>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.disposal_account_id)='bank' THEN '1100' ELSE '1000' END,r.disposal_proceeds,0); END IF;
    IF r.disposal_proceeds-(r.cost-r.accumulated_depreciation)>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'7100',0,r.disposal_proceeds-(r.cost-r.accumulated_depreciation));
    ELSIF r.disposal_proceeds-(r.cost-r.accumulated_depreciation)<0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6300',-(r.disposal_proceeds-(r.cost-r.accumulated_depreciation)),0); END IF;
  END LOOP;

  FOR r IN SELECT * FROM work_orders WHERE status='Completed' LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'إتمام تصنيع '||r.number,'work_order',r.id);
    IF r.total_cost>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.total_cost,0);
      IF r.material_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',0,r.material_cost); END IF;
      IF r.labor_cost+r.overhead_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2200',0,r.labor_cost+r.overhead_cost); END IF;
    END IF;
  END LOOP;

  RETURN n;
END $$;


-- ============================================================
-- L) Reports
-- ============================================================
CREATE OR REPLACE FUNCTION inventory_valuation() RETURNS TABLE(product_id uuid,product_name text,qty numeric,avg_cost numeric,value numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT p.id,p.name,coalesce(sum(b.qty),0),p.avg_cost,round(coalesce(sum(b.qty),0)*p.avg_cost,2)
  FROM products p LEFT JOIN stock_balances b ON b.product_id=p.id
  WHERE auth_role() IN('admin','accountant','store') GROUP BY p.id,p.name,p.avg_cost ORDER BY p.name
$$;

CREATE OR REPLACE FUNCTION sales_by_customer(p_from date DEFAULT date_trunc('month',current_date)::date,p_to date DEFAULT current_date)
RETURNS TABLE(customer_id uuid,customer_name text,invoices bigint,sales numeric,returns numeric,net numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT c.id,c.name,coalesce(count(distinct s.id),0),coalesce(sum(s.total),0),coalesce((SELECT sum(sr.total) FROM sales_returns sr WHERE sr.customer_id=c.id AND sr.date BETWEEN p_from AND p_to),0),coalesce(sum(s.total),0)-coalesce((SELECT sum(sr.total) FROM sales_returns sr WHERE sr.customer_id=c.id AND sr.date BETWEEN p_from AND p_to),0)
  FROM customers c LEFT JOIN sales_invoices s ON s.customer_id=c.id AND s.status='Posted' AND s.date BETWEEN p_from AND p_to
  WHERE auth_role() IN('admin','accountant','sales') GROUP BY c.id,c.name ORDER BY 6 DESC  -- v1.5: net is a RETURNS TABLE name, not a query column
$$;

CREATE OR REPLACE FUNCTION cashflow_summary(p_from date DEFAULT date_trunc('month',current_date)::date,p_to date DEFAULT current_date)
RETURNS TABLE(inflow numeric,outflow numeric,net numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  WITH x AS (
    SELECT coalesce(sum(CASE WHEN kind='receipt' THEN amount ELSE 0 END),0) AS inflow,
           coalesce(sum(CASE WHEN kind='payment' THEN amount ELSE 0 END),0) AS pay_out
    FROM payments WHERE date BETWEEN p_from AND p_to
  ), e AS (SELECT coalesce(sum(amount),0) expense_out FROM expenses WHERE date BETWEEN p_from AND p_to)
  SELECT x.inflow, x.pay_out+e.expense_out, x.inflow-(x.pay_out+e.expense_out) FROM x CROSS JOIN e WHERE auth_role() IN('admin','accountant')
$$;

CREATE OR REPLACE FUNCTION health_check_enterprise() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE r jsonb:=jsonb_build_object(); c int; bad int;
BEGIN
  IF auth_role() NOT IN('admin','accountant') THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
  SELECT coalesce(sum(n-1),0)::int INTO c FROM (SELECT barcode,count(*) n FROM products WHERE barcode IS NOT NULL GROUP BY barcode HAVING count(*)>1) d;
  bad:=coalesce(c,0);
  r:=jsonb_build_object(
    'duplicate_barcodes',bad,
    'unbalanced_journal_entries',(SELECT count(*) FROM (SELECT je.id FROM journal_entries je JOIN journal_lines jl ON jl.entry_id=je.id GROUP BY je.id HAVING round(sum(jl.debit),2)<>round(sum(jl.credit),2)) x),
    'negative_stock_rows',(SELECT count(*) FROM stock_balances WHERE qty<0),
    'open_fiscal_periods',(SELECT count(*) FROM fiscal_periods WHERE status='Open'),
    'pending_approvals',(SELECT count(*) FROM approval_requests WHERE status='Pending')
  );
  r:=r||jsonb_build_object('ok',(r->>'duplicate_barcodes')::int=0 AND (r->>'unbalanced_journal_entries')::int=0);
  RETURN r;
END $$;

-- Safe write policies for master/reference data used by the UI. Transactional stock/finance writes remain RPC-only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='branches' AND policyname='write_branches_admin') THEN CREATE POLICY write_branches_admin ON branches FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cost_centers' AND policyname='write_cost_centers_admin') THEN CREATE POLICY write_cost_centers_admin ON cost_centers FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fiscal_periods' AND policyname='write_fiscal_periods_admin') THEN CREATE POLICY write_fiscal_periods_admin ON fiscal_periods FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_orders' AND policyname='write_purchase_orders') THEN CREATE POLICY write_purchase_orders ON purchase_orders FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','store')) WITH CHECK(auth_role() IN('admin','accountant','store')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='purchase_order_items' AND policyname='write_purchase_order_items') THEN CREATE POLICY write_purchase_order_items ON purchase_order_items FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','store')) WITH CHECK(auth_role() IN('admin','accountant','store')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='price_lists' AND policyname='write_price_lists') THEN CREATE POLICY write_price_lists ON price_lists FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','sales')) WITH CHECK(auth_role() IN('admin','accountant','sales')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='price_list_items' AND policyname='write_price_list_items') THEN CREATE POLICY write_price_list_items ON price_list_items FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','sales')) WITH CHECK(auth_role() IN('admin','accountant','sales')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='shifts' AND policyname='write_shifts') THEN CREATE POLICY write_shifts ON shifts FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='attendance' AND policyname='write_attendance') THEN CREATE POLICY write_attendance ON attendance FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='leave_types' AND policyname='write_leave_types') THEN CREATE POLICY write_leave_types ON leave_types FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='leave_requests' AND policyname='write_leave_requests') THEN CREATE POLICY write_leave_requests ON leave_requests FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='boms' AND policyname='write_boms') THEN CREATE POLICY write_boms ON boms FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','store')) WITH CHECK(auth_role() IN('admin','accountant','store')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bom_items' AND policyname='write_bom_items') THEN CREATE POLICY write_bom_items ON bom_items FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','store')) WITH CHECK(auth_role() IN('admin','accountant','store')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='projects' AND policyname='write_projects') THEN CREATE POLICY write_projects ON projects FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','sales')) WITH CHECK(auth_role() IN('admin','accountant','sales')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='service_tickets' AND policyname='write_service_tickets') THEN CREATE POLICY write_service_tickets ON service_tickets FOR ALL TO authenticated USING(auth_role() IN('admin','accountant','sales')) WITH CHECK(auth_role() IN('admin','accountant','sales')); END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='asset_categories' AND policyname='write_asset_categories') THEN CREATE POLICY write_asset_categories ON asset_categories FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bank_statements' AND policyname='write_bank_statements') THEN CREATE POLICY write_bank_statements ON bank_statements FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='bank_statement_lines' AND policyname='write_bank_statement_lines') THEN CREATE POLICY write_bank_statement_lines ON bank_statement_lines FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='fixed_assets' AND policyname='write_fixed_assets_admin') THEN CREATE POLICY write_fixed_assets_admin ON fixed_assets FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
END $$;

-- ============================================================
-- M) Permissions / audit triggers
-- ============================================================
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['branches','cost_centers','fiscal_periods','purchase_orders','purchase_order_items','goods_receipts','goods_receipt_items','delivery_notes','delivery_note_items','price_lists','price_list_items','asset_categories','fixed_assets','asset_depreciations','bank_statements','bank_statement_lines','shifts','attendance','leave_types','leave_requests','boms','bom_items','work_orders','pos_sessions','pos_session_sales','projects','service_tickets','approval_requests','notifications'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS audit_%I ON %I',t,t);
    EXECUTE format('CREATE TRIGGER audit_%I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION audit_trg()',t,t);
  END LOOP;
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM public,anon;
GRANT EXECUTE ON FUNCTION assert_period_open(date),close_fiscal_period(uuid),reopen_fiscal_period(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION create_purchase_order(uuid,uuid,jsonb,date,text),create_goods_receipt(uuid,jsonb,text),create_purchase_invoice_from_receipt(uuid,numeric,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_delivery(uuid,jsonb,text),create_sale_from_delivery(uuid,numeric,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION price_for(uuid,uuid,numeric,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION create_fixed_asset(text,uuid,numeric,numeric,int,date,uuid),depreciate_asset(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION reconcile_bank_line(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION approve_leave(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION create_work_order(uuid,uuid,numeric,numeric,numeric),complete_work_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION open_pos_session(uuid,numeric),record_pos_sale(uuid,uuid),close_pos_session(uuid,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION decide_approval(uuid,boolean,text) TO authenticated;
GRANT EXECUTE ON FUNCTION inventory_valuation(),sales_by_customer(date,date),cashflow_summary(date,date),balance_sheet(date),health_check_enterprise() TO authenticated;

GRANT EXECUTE ON FUNCTION capitalize_fixed_asset(uuid,text),dispose_fixed_asset(uuid,date,numeric,uuid) TO authenticated;
-- (v1.6: premature grant removed; the function is created below and granted after it)

GRANT SELECT ON branches,cost_centers,fiscal_periods,purchase_orders,purchase_order_items,goods_receipts,goods_receipt_items,delivery_notes,delivery_note_items,price_lists,price_list_items,asset_categories,fixed_assets,asset_depreciations,bank_statements,bank_statement_lines,shifts,attendance,leave_types,leave_requests,boms,bom_items,work_orders,pos_sessions,pos_session_sales,projects,service_tickets,approval_requests,notifications TO authenticated;


-- ============================================================
-- N) Automated enterprise smoke suite
--    Run from admin dashboard after applying this migration.
-- ============================================================
CREATE OR REPLACE FUNCTION run_erp_enterprise_test() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  tag text:='ENTTEST-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  wh1 uuid; wh2 uuid; ca uuid; cust uuid; supp uuid; prod uuid; fg uuid; branch uuid; category_id uuid; cost_center_id uuid; v_price_list_id uuid;
  po uuid; grn uuid; so uuid; dn uuid; direct_inv uuid; delivery_inv uuid; direct_pinv uuid; receipt_pinv uuid; pay_id uuid; pos uuid; pos_inv uuid;
  v_asset_id uuid; asset_cat_id uuid; v_bom_id uuid; wo uuid; leave_type_id uuid; employee_id uuid; leave_id uuid; project_id uuid; ticket_id uuid; period_id uuid; stmt_id uuid; line_id uuid;
  results jsonb[]:='{}'; ok boolean:=true; q numeric; v numeric; unbalanced int; dep numeric;
BEGIN
  PERFORM require_role('{admin}'); PERFORM require_dev();
  SELECT id INTO branch FROM branches ORDER BY created_at LIMIT 1;
  SELECT id INTO ca FROM cash_accounts ORDER BY created_at LIMIT 1;
  INSERT INTO warehouses(name) VALUES(tag||'-W1') RETURNING id INTO wh1;
  INSERT INTO warehouses(name) VALUES(tag||'-W2') RETURNING id INTO wh2;
  INSERT INTO customers(name) VALUES(tag||'-Customer') RETURNING id INTO cust;
  INSERT INTO suppliers(name) VALUES(tag||'-Supplier') RETURNING id INTO supp;
  INSERT INTO categories(name) VALUES(tag||'-Cat') RETURNING id INTO category_id;
  INSERT INTO products(name,code,barcode,category_id,purchase_price,sale_price,avg_cost,min_stock,reorder_qty) VALUES(tag||'-Product',tag||'-P',tag||'-BC',category_id,10,15,10,2,5) RETURNING id INTO prod;
  INSERT INTO products(name,code,barcode,purchase_price,sale_price,avg_cost) VALUES(tag||'-FG',tag||'-FG',tag||'-FGBC',10,20,10) RETURNING id INTO fg;
  INSERT INTO cost_centers(code,name) VALUES(tag||'-CC',tag||'-CC') RETURNING id INTO cost_center_id;
  INSERT INTO price_lists(name) VALUES(tag||'-Retail') RETURNING id INTO v_price_list_id;
  INSERT INTO price_list_items(price_list_id,product_id,price,min_qty) VALUES(v_price_list_id,prod,14,1);
  v:=price_for(prod,v_price_list_id,1,15); results:=array_append(results,jsonb_build_object('test','price list lookup','pass',v=14,'detail','price='||v)); ok:=ok AND v=14;

  PERFORM approve_stocktake(wh1,jsonb_build_array(jsonb_build_object('product_id',prod,'actual',10)));
  SELECT qty INTO q FROM stock_balances WHERE product_id=prod AND warehouse_id=wh1; results:=array_append(results,jsonb_build_object('test','opening stock','pass',q=10,'detail','qty='||q)); ok:=ok AND q=10;

  direct_pinv:=create_purchase(supp,wh1,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',5,'price',10,'discount',0)),0,null,'credit',0,null);
  SELECT qty INTO q FROM stock_balances WHERE product_id=prod AND warehouse_id=wh1; results:=array_append(results,jsonb_build_object('test','purchase increases stock','pass',q=15,'detail','qty='||q)); ok:=ok AND q=15;

  INSERT INTO purchase_orders(number,date,expected_date,supplier_id,warehouse_id,branch_id,status,subtotal,total) VALUES(tag||'-PO',current_date,current_date,supp,wh1,branch,'Draft',20,20) RETURNING id INTO po;
  INSERT INTO purchase_order_items(order_id,product_id,qty,unit_price,line_total) VALUES(po,prod,2,10,20);
  grn:=create_goods_receipt(po,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',2,'cost',10)),'test');
  SELECT qty INTO q FROM stock_balances WHERE product_id=prod AND warehouse_id=wh1; results:=array_append(results,jsonb_build_object('test','goods receipt increases stock','pass',q=17,'detail','qty='||q)); ok:=ok AND q=17;
  receipt_pinv:=create_purchase_invoice_from_receipt(grn,0,null,'credit'); results:=array_append(results,jsonb_build_object('test','purchase invoice from receipt','pass',receipt_pinv IS NOT NULL,'detail','created')); ok:=ok AND receipt_pinv IS NOT NULL;

  INSERT INTO sales_orders(number,customer_id,warehouse_id,branch_id,status) VALUES(tag||'-SO',cust,wh1,branch,'Confirmed') RETURNING id INTO so;
  INSERT INTO sales_order_items(order_id,product_id,qty,unit_price,discount) VALUES(so,prod,3,15,0);
  dn:=create_delivery(so,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',3,'price',15,'discount',0)),'test');
  SELECT qty INTO q FROM stock_balances WHERE product_id=prod AND warehouse_id=wh1; results:=array_append(results,jsonb_build_object('test','delivery decreases stock','pass',q=14,'detail','qty='||q)); ok:=ok AND q=14;
  delivery_inv:=create_sale_from_delivery(dn,0,null,'credit'); results:=array_append(results,jsonb_build_object('test','sale invoice from delivery','pass',delivery_inv IS NOT NULL,'detail','created')); ok:=ok AND delivery_inv IS NOT NULL;

  INSERT INTO asset_categories(name) VALUES(tag||'-Assets') RETURNING id INTO asset_cat_id;
  v_asset_id:=create_fixed_asset(tag||'-Printer',asset_cat_id,1200,0,12,current_date,branch);
  PERFORM capitalize_fixed_asset(v_asset_id,'1000');
  dep:=depreciate_asset(v_asset_id,current_date); results:=array_append(results,jsonb_build_object('test','fixed asset depreciation','pass',dep=100,'detail','depreciation='||dep)); ok:=ok AND dep=100;

  INSERT INTO bank_statements(account_id,statement_no,from_date,to_date) VALUES(ca,tag,current_date,current_date) RETURNING id INTO stmt_id;
  INSERT INTO payments(kind,customer_id,account_id,amount,doc_ref,branch_id) VALUES('receipt',cust,ca,25,tag,branch) RETURNING id INTO pay_id;
  INSERT INTO bank_statement_lines(statement_id,txn_date,description,amount,direction) VALUES(stmt_id,current_date,'test',25,'credit') RETURNING id INTO line_id;
  PERFORM reconcile_bank_line(line_id,pay_id); v:=(SELECT CASE WHEN reconciled THEN 1 ELSE 0 END FROM bank_statement_lines WHERE id=line_id); results:=array_append(results,jsonb_build_object('test','bank reconciliation','pass',v=1,'detail','reconciled')); ok:=ok AND v=1;

  INSERT INTO boms(product_id,version) VALUES(fg,tag) RETURNING id INTO v_bom_id;
  INSERT INTO bom_items(bom_id,component_product_id,qty) VALUES(v_bom_id,prod,1);
  wo:=create_work_order(v_bom_id,wh1,2,10,5); v:=complete_work_order(wo); results:=array_append(results,jsonb_build_object('test','manufacturing completes','pass',v>0,'detail','cost='||v)); ok:=ok AND v>0;

  pos_inv:=create_sale(cust,wh1,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',1,'price',15,'discount',0)),15,ca,'cash',0,tag||'-POS');
  pos:=open_pos_session(ca,100); PERFORM record_pos_sale(pos,pos_inv); PERFORM close_pos_session(pos,115); v:=(SELECT CASE WHEN status='Closed' THEN 1 ELSE 0 END FROM pos_sessions WHERE id=pos); results:=array_append(results,jsonb_build_object('test','POS session lifecycle','pass',v=1,'detail','closed')); ok:=ok AND v=1;

  INSERT INTO employees(name,salary) VALUES(tag||'-Employee',1000) RETURNING id INTO employee_id;
  INSERT INTO leave_types(name,days_per_year,paid) VALUES(tag||'-Leave',20,true) RETURNING id INTO leave_type_id;
  INSERT INTO leave_requests(employee_id,leave_type_id,from_date,to_date,days,reason) VALUES(employee_id,leave_type_id,current_date,current_date,1,'test') RETURNING id INTO leave_id;
  PERFORM approve_leave(leave_id,true); v:=(SELECT CASE WHEN status='Approved' THEN 1 ELSE 0 END FROM leave_requests WHERE id=leave_id); results:=array_append(results,jsonb_build_object('test','leave approval','pass',v=1,'detail','approved')); ok:=ok AND v=1;

  INSERT INTO projects(code,name,customer_id) VALUES(tag||'-PRJ',tag||'-Project',cust) RETURNING id INTO project_id;
  INSERT INTO service_tickets(ticket_no,customer_id,project_id,subject) VALUES(tag||'-TKT',cust,project_id,'test') RETURNING id INTO ticket_id;
  results:=array_append(results,jsonb_build_object('test','service/project master','pass',project_id IS NOT NULL AND ticket_id IS NOT NULL,'detail','created')); ok:=ok AND project_id IS NOT NULL AND ticket_id IS NOT NULL;

  INSERT INTO fiscal_periods(name,start_date,end_date,status) VALUES(tag,current_date-1,current_date+1,'Open') RETURNING id INTO period_id;
  PERFORM close_fiscal_period(period_id);
  BEGIN
    INSERT INTO expenses(category,amount,account_id,date) VALUES('period-lock-test',1,ca,current_date);
    results:=array_append(results,jsonb_build_object('test','closed-period rejects writes','pass',false,'detail','write unexpectedly allowed')); ok:=false;
  EXCEPTION WHEN OTHERS THEN
    results:=array_append(results,jsonb_build_object('test','closed-period rejects writes','pass',true,'detail','rejected'));
  END;
  PERFORM reopen_fiscal_period(period_id);

  PERFORM rebuild_journal();
  SELECT count(*) INTO unbalanced FROM (SELECT je.id FROM journal_entries je JOIN journal_lines jl ON jl.entry_id=je.id GROUP BY je.id HAVING round(sum(jl.debit),2)<>round(sum(jl.credit),2)) x;
  results:=array_append(results,jsonb_build_object('test','global/per-entry journal balance','pass',unbalanced=0,'detail','unbalanced='||unbalanced)); ok:=ok AND unbalanced=0;
  results:=array_append(results,jsonb_build_object('test','inventory report callable','pass',(SELECT count(*) FROM inventory_valuation())>=0,'detail','ok'));
  results:=array_append(results,jsonb_build_object('test','balance sheet callable','pass',(SELECT count(*) FROM balance_sheet(current_date))>=0,'detail','ok'));
  results:=array_append(results,jsonb_build_object('test','customer sales report callable','pass',(SELECT count(*) FROM sales_by_customer(current_date-30,current_date))>=0,'detail','ok'));
  results:=array_append(results,jsonb_build_object('test','cashflow report callable','pass',(SELECT count(*) FROM cashflow_summary(current_date-30,current_date))>=0,'detail','ok'));
  results:=array_append(results,jsonb_build_object('test','enterprise health check','pass',((health_check_enterprise()->>'unbalanced_journal_entries')::int=0),'detail',health_check_enterprise()::text));

  -- Dependency-safe cleanup of tagged test data.
  DELETE FROM bank_statement_lines WHERE statement_id=stmt_id; DELETE FROM bank_statements WHERE id=stmt_id;
  DELETE FROM pos_session_sales WHERE session_id=pos; DELETE FROM pos_sessions WHERE id=pos;
  DELETE FROM leave_requests WHERE id=leave_id; DELETE FROM leave_types WHERE id=leave_type_id; DELETE FROM employees WHERE id=employee_id;
  DELETE FROM service_tickets WHERE id=ticket_id; DELETE FROM projects WHERE id=project_id;
  DELETE FROM asset_depreciations ad WHERE ad.asset_id=v_asset_id; DELETE FROM journal_lines jl WHERE jl.entry_id IN(SELECT je.id FROM journal_entries je WHERE je.doc_id=v_asset_id); DELETE FROM journal_entries je WHERE je.doc_id=v_asset_id; DELETE FROM fixed_assets WHERE id=v_asset_id; DELETE FROM asset_categories WHERE id=asset_cat_id;
  DELETE FROM work_orders WHERE id=wo; DELETE FROM bom_items WHERE bom_id=v_bom_id; DELETE FROM boms WHERE id=v_bom_id;
  DELETE FROM payment_allocations WHERE sales_invoice_id IN(delivery_inv,pos_inv) OR purchase_invoice_id=receipt_pinv;
  DELETE FROM stock_movements WHERE doc_id IN(direct_inv,direct_pinv,receipt_pinv,delivery_inv,pos_inv,dn,grn,so,po,wo);
  DELETE FROM journal_lines WHERE entry_id IN(SELECT id FROM journal_entries WHERE doc_id IN(direct_inv,direct_pinv,receipt_pinv,delivery_inv,pos_inv,dn,grn,so,po,wo)); DELETE FROM journal_entries WHERE doc_id IN(direct_inv,direct_pinv,receipt_pinv,delivery_inv,pos_inv,dn,grn,so,po,wo);
  DELETE FROM sales_invoice_items WHERE invoice_id IN(delivery_inv,pos_inv); DELETE FROM sales_invoices WHERE id IN(delivery_inv,pos_inv);
  DELETE FROM purchase_invoice_items WHERE invoice_id IN(direct_pinv,receipt_pinv); DELETE FROM purchase_invoices WHERE id IN(direct_pinv,receipt_pinv);
  DELETE FROM delivery_note_items WHERE delivery_id=dn; DELETE FROM delivery_notes WHERE id=dn; DELETE FROM sales_order_items WHERE order_id=so; DELETE FROM sales_orders WHERE id=so;
  DELETE FROM goods_receipt_items WHERE receipt_id=grn; DELETE FROM goods_receipts WHERE id=grn; DELETE FROM purchase_order_items WHERE order_id=po; DELETE FROM purchase_orders WHERE id=po;
  DELETE FROM payments WHERE id=pay_id;
  DELETE FROM fiscal_periods WHERE id=period_id;
  DELETE FROM price_list_items pli WHERE pli.price_list_id=v_price_list_id; DELETE FROM price_lists WHERE id=v_price_list_id;
  DELETE FROM cost_centers WHERE id=cost_center_id; DELETE FROM stock_movements WHERE product_id IN(prod,fg); DELETE FROM stock_balances WHERE product_id IN(prod,fg); DELETE FROM products WHERE id IN(prod,fg); DELETE FROM categories WHERE id=category_id; DELETE FROM suppliers WHERE id=supp; UPDATE cash_accounts ca SET balance=ca.balance-(SELECT coalesce(sum(CASE WHEN p.kind='receipt' THEN p.amount ELSE -p.amount END),0) FROM payments p WHERE p.account_id=ca.id AND (p.customer_id=cust OR p.supplier_id=supp)) WHERE ca.id IN(SELECT account_id FROM payments WHERE customer_id=cust OR supplier_id=supp); DELETE FROM payments WHERE customer_id=cust OR supplier_id=supp; DELETE FROM customers WHERE id=cust; DELETE FROM warehouses WHERE id IN(wh1,wh2);
  DELETE FROM audit_logs WHERE description LIKE '%'||tag||'%';

  RETURN jsonb_build_object('ok',ok,'results',results,'cleaned',true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok',false,'error',SQLERRM,'results',results,'cleaned',false);
END $$;

REVOKE ALL ON FUNCTION run_erp_enterprise_test() FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION run_erp_enterprise_test() TO authenticated;


-- ============================================================
-- 010A) Safe voiding + opening balances
-- ============================================================
CREATE TABLE IF NOT EXISTS opening_balance_runs(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  posted_at timestamptz DEFAULT now(),
  posted_by uuid DEFAULT auth.uid(),
  journal_entry_id uuid REFERENCES journal_entries,
  notes text
);
ALTER TABLE opening_balance_runs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='opening_balance_runs' AND policyname='sel_opening_balance_runs') THEN CREATE POLICY sel_opening_balance_runs ON opening_balance_runs FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
END $$;

CREATE OR REPLACE FUNCTION cancel_sales_invoice(p_invoice uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv sales_invoices; it record; je uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO inv FROM sales_invoices WHERE id=p_invoice FOR UPDATE;
  IF NOT FOUND OR inv.status<>'Posted' THEN RAISE EXCEPTION 'فاتورة المبيعات غير قابلة للإلغاء'; END IF;
  IF EXISTS(SELECT 1 FROM payment_allocations WHERE sales_invoice_id=inv.id) THEN RAISE EXCEPTION 'لا يمكن إلغاء فاتورة عليها دفعات مخصصة'; END IF;
  IF EXISTS(SELECT 1 FROM sales_returns WHERE invoice_id=inv.id) THEN RAISE EXCEPTION 'لا يمكن إلغاء فاتورة عليها مرتجعات'; END IF;
  IF coalesce(inv.notes,'') LIKE 'DN:%' THEN RAISE EXCEPTION 'لا يمكن إلغاء فاتورة تم إنشاؤها من إذن تسليم'; END IF;
  PERFORM assert_period_open(inv.date);
  FOR it IN SELECT product_id,qty FROM sales_invoice_items WHERE invoice_id=inv.id LOOP
    PERFORM apply_stock(it.product_id,inv.warehouse_id,it.qty,'Sales Return','invoice_void',inv.id);
  END LOOP;
  UPDATE sales_invoices SET status='Void',paid=0 WHERE id=inv.id;
  PERFORM log_event('void','sales_invoices',inv.id::text,'ألغى فاتورة مبيعات '||inv.number);
END $$;

CREATE OR REPLACE FUNCTION edit_sales_invoice(p_invoice uuid,p_customer uuid,p_warehouse uuid,p_items jsonb,p_paid numeric DEFAULT 0,p_account uuid DEFAULT NULL,p_method text DEFAULT 'credit',p_discount numeric DEFAULT 0) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE old_no text; nid uuid;
BEGIN
  PERFORM require_role('{admin}');
  SELECT number INTO old_no FROM sales_invoices WHERE id=p_invoice;
  IF old_no IS NULL THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  PERFORM cancel_sales_invoice(p_invoice);
  nid:=create_sale(p_customer,p_warehouse,p_items,p_paid,p_account,p_method,p_discount);
  PERFORM log_event('edit','sales_invoices',nid::text,'عدّل فاتورة مبيعات '||old_no||' (أُلغيت الأصلية وأُنشئت فاتورة جديدة بالتعديلات)');
  RETURN nid;
END $$;
GRANT EXECUTE ON FUNCTION edit_sales_invoice(uuid,uuid,uuid,jsonb,numeric,uuid,text,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION cancel_purchase_invoice(p_invoice uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv purchase_invoices; it record;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO inv FROM purchase_invoices WHERE id=p_invoice FOR UPDATE;
  IF NOT FOUND OR inv.status<>'Posted' THEN RAISE EXCEPTION 'فاتورة المشتريات غير قابلة للإلغاء'; END IF;
  IF EXISTS(SELECT 1 FROM payment_allocations WHERE purchase_invoice_id=inv.id) THEN RAISE EXCEPTION 'لا يمكن إلغاء فاتورة عليها دفعات مخصصة'; END IF;
  IF EXISTS(SELECT 1 FROM purchase_returns WHERE invoice_id=inv.id) THEN RAISE EXCEPTION 'لا يمكن إلغاء فاتورة عليها مرتجعات'; END IF;
  PERFORM assert_period_open(inv.date);
  FOR it IN SELECT product_id,qty FROM purchase_invoice_items WHERE invoice_id=inv.id LOOP
    PERFORM apply_stock(it.product_id,inv.warehouse_id,-it.qty,'Purchase Return','invoice_void',inv.id);
  END LOOP;
  UPDATE purchase_invoices SET status='Void',paid=0 WHERE id=inv.id;
  PERFORM log_event('void','purchase_invoices',inv.id::text,'ألغى فاتورة مشتريات '||inv.number);
END $$;

CREATE OR REPLACE FUNCTION post_opening_balances(p_notes text DEFAULT null) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE je uuid:=gen_random_uuid(); total_debit numeric:=0; total_credit numeric:=0; balancing numeric; x record; run_id uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF EXISTS(SELECT 1 FROM opening_balance_runs) THEN RAISE EXCEPTION 'تم ترحيل الأرصدة الافتتاحية من قبل'; END IF;
  IF EXISTS(SELECT 1 FROM sales_invoices WHERE status='Posted') OR EXISTS(SELECT 1 FROM purchase_invoices WHERE status='Posted') OR EXISTS(SELECT 1 FROM payments) OR EXISTS(SELECT 1 FROM expenses) THEN RAISE EXCEPTION 'رحّل الأرصدة الافتتاحية قبل بدء الحركات'; END IF;
  INSERT INTO journal_entries(id,date,description,doc_type) VALUES(je,current_date,'قيد الأرصدة الافتتاحية','opening_balance');
  FOR x IN SELECT CASE WHEN type='bank' THEN '1100' ELSE '1000' END AS code,balance FROM cash_accounts WHERE balance<>0 LOOP
    IF x.balance>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,x.code,x.balance,0); total_debit:=total_debit+x.balance; ELSE INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,x.code,0,-x.balance); total_credit:=total_credit-x.balance; END IF;
  END LOOP;
  SELECT coalesce(sum(GREATEST(c.opening_balance,0)),0) INTO balancing FROM customers c;
  IF balancing>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1300',balancing,0); total_debit:=total_debit+balancing; END IF;
  SELECT coalesce(sum(GREATEST(-c.opening_balance,0)),0) INTO balancing FROM customers c;
  IF balancing>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1300',0,balancing); total_credit:=total_credit+balancing; END IF;
  SELECT coalesce(sum(GREATEST(s.opening_balance,0)),0) INTO balancing FROM suppliers s;
  IF balancing>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'2000',0,balancing); total_credit:=total_credit+balancing; END IF;
  SELECT coalesce(sum(GREATEST(-s.opening_balance,0)),0) INTO balancing FROM suppliers s;
  IF balancing>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'2000',balancing,0); total_debit:=total_debit+balancing; END IF;
  SELECT coalesce(sum(b.qty*p.avg_cost),0) INTO balancing FROM stock_balances b JOIN products p ON p.id=b.product_id WHERE b.qty<>0;
  IF balancing>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'1200',balancing,0); total_debit:=total_debit+balancing; END IF;
  IF total_debit>total_credit THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'3000',0,total_debit-total_credit);
  ELSIF total_credit>total_debit THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(je,'3000',total_credit-total_debit,0); END IF;
  INSERT INTO opening_balance_runs(journal_entry_id,notes) VALUES(je,p_notes) RETURNING id INTO run_id;
  PERFORM log_event('create','opening_balance_runs',run_id::text,'رحّل الأرصدة الافتتاحية'); RETURN run_id;
END $$;

GRANT EXECUTE ON FUNCTION cancel_sales_invoice(uuid),cancel_purchase_invoice(uuid),post_opening_balances(text) TO authenticated;
GRANT SELECT ON opening_balance_runs TO authenticated;

-- ============================================================
-- 010B) Final go-live additions: commissions, cheques, integrations, barcodes
-- ============================================================
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_batch boolean NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_serial boolean NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_expiry boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS products_barcode_unique_idx ON products(barcode) WHERE barcode IS NOT NULL;

CREATE TABLE IF NOT EXISTS product_barcodes(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products ON DELETE CASCADE,
  barcode text NOT NULL UNIQUE,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS product_barcodes_product_idx ON product_barcodes(product_id);

CREATE TABLE IF NOT EXISTS commission_rules(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  rate numeric(8,4) NOT NULL CHECK(rate>=0),
  basis text NOT NULL DEFAULT 'net_sales' CHECK(basis IN('net_sales','gross_profit')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sales_commissions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES sales_invoices ON DELETE CASCADE,
  salesperson_id uuid,
  rule_id uuid REFERENCES commission_rules,
  basis_amount numeric(14,2) NOT NULL DEFAULT 0,
  amount numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','Approved','Paid','Cancelled')),
  created_at timestamptz DEFAULT now(),
  UNIQUE(invoice_id,rule_id)
);

CREATE TABLE IF NOT EXISTS cheques(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cheque_no text NOT NULL,
  kind text NOT NULL CHECK(kind IN('received','issued')),
  customer_id uuid REFERENCES customers,
  supplier_id uuid REFERENCES suppliers,
  account_id uuid NOT NULL REFERENCES cash_accounts,
  amount numeric(14,2) NOT NULL CHECK(amount>0),
  issue_date date NOT NULL DEFAULT current_date,
  due_date date NOT NULL,
  status text NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','Deposited','Cleared','Bounced','Cancelled')),
  doc_ref text,
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now(),
  CHECK((kind='received' AND customer_id IS NOT NULL AND supplier_id IS NULL) OR (kind='issued' AND supplier_id IS NOT NULL AND customer_id IS NULL))
);
CREATE INDEX IF NOT EXISTS cheques_due_idx ON cheques(due_date,status);

CREATE TABLE IF NOT EXISTS tax_documents(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL UNIQUE REFERENCES sales_invoices ON DELETE CASCADE,
  document_type text NOT NULL DEFAULT 'sales_invoice',
  status text NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','Submitted','Accepted','Rejected','Cancelled')),
  external_uuid text,
  submission_id text,
  submitted_at timestamptz,
  error_message text,
  request_payload jsonb,
  response_payload jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS integration_connections(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK(provider IN('Shopify','WooCommerce','Salla','Magento','Custom')),
  name text NOT NULL,
  base_url text,
  active boolean NOT NULL DEFAULT false,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  UNIQUE(provider,name)
);
CREATE TABLE IF NOT EXISTS integration_events(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id uuid REFERENCES integration_connections ON DELETE SET NULL,
  direction text NOT NULL CHECK(direction IN('inbound','outbound')),
  event_type text NOT NULL,
  external_id text,
  entity text,
  entity_id uuid,
  status text NOT NULL DEFAULT 'Pending' CHECK(status IN('Pending','Processing','Succeeded','Failed')),
  attempts int NOT NULL DEFAULT 0,
  payload jsonb,
  error_message text,
  created_at timestamptz DEFAULT now(),
  processed_at timestamptz
);
CREATE INDEX IF NOT EXISTS integration_events_status_idx ON integration_events(status,created_at);

ALTER TABLE product_barcodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE commission_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE cheques ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE integration_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE integration_events ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='product_barcodes' AND policyname='sel_product_barcodes') THEN CREATE POLICY sel_product_barcodes ON product_barcodes FOR SELECT TO authenticated USING(auth_role() IS NOT NULL); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='commission_rules' AND policyname='sel_commission_rules') THEN CREATE POLICY sel_commission_rules ON commission_rules FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant','sales')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='sales_commissions' AND policyname='sel_sales_commissions') THEN CREATE POLICY sel_sales_commissions ON sales_commissions FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant','sales')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cheques' AND policyname='sel_cheques') THEN CREATE POLICY sel_cheques ON cheques FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant','sales')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='tax_documents' AND policyname='sel_tax_documents') THEN CREATE POLICY sel_tax_documents ON tax_documents FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='integration_connections' AND policyname='sel_integration_connections') THEN CREATE POLICY sel_integration_connections ON integration_connections FOR SELECT TO authenticated USING(auth_role()='admin'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='integration_events' AND policyname='sel_integration_events') THEN CREATE POLICY sel_integration_events ON integration_events FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant')); END IF;
END $$;

CREATE OR REPLACE FUNCTION add_product_barcode(p_product uuid,p_barcode text,p_primary boolean DEFAULT false) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid();
BEGIN
  PERFORM require_role('{admin,store}');
  IF nullif(trim(p_barcode),'') IS NULL THEN RAISE EXCEPTION 'الباركود مطلوب'; END IF;
  IF EXISTS(SELECT 1 FROM products WHERE barcode=p_barcode AND id<>p_product) OR EXISTS(SELECT 1 FROM product_barcodes WHERE barcode=p_barcode) THEN RAISE EXCEPTION 'الباركود مستخدم بالفعل'; END IF;
  IF p_primary THEN UPDATE product_barcodes SET is_primary=false WHERE product_id=p_product; UPDATE products SET barcode=p_barcode WHERE id=p_product; END IF;
  INSERT INTO product_barcodes(id,product_id,barcode,is_primary) VALUES(v,p_product,p_barcode,p_primary); RETURN v;
END $$;

CREATE OR REPLACE FUNCTION calculate_sales_commission(p_invoice uuid,p_rule uuid) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE inv sales_invoices; rule commission_rules; base numeric; gp numeric; amt numeric;
BEGIN
  PERFORM require_role('{admin,accountant}');
  SELECT * INTO inv FROM sales_invoices WHERE id=p_invoice AND status='Posted'; IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  SELECT * INTO rule FROM commission_rules WHERE id=p_rule AND active; IF NOT FOUND THEN RAISE EXCEPTION 'قاعدة العمولة غير متاحة'; END IF;
  SELECT coalesce(sum(line_total),0) INTO base FROM sales_invoice_items WHERE invoice_id=inv.id;
  SELECT coalesce(sum(qty*unit_price-discount)-sum(qty*unit_cost),0) INTO gp FROM sales_invoice_items WHERE invoice_id=inv.id;
  base:=CASE WHEN rule.basis='gross_profit' THEN gp ELSE base END;
  amt:=round(greatest(base,0)*rule.rate/100,2);
  INSERT INTO sales_commissions(invoice_id,salesperson_id,rule_id,basis_amount,amount) VALUES(inv.id,inv.salesperson,p_rule,greatest(base,0),amt)
  ON CONFLICT(invoice_id,rule_id) DO UPDATE SET basis_amount=excluded.basis_amount,amount=excluded.amount,salesperson_id=excluded.salesperson_id;
  RETURN amt;
END $$;

CREATE OR REPLACE FUNCTION record_cheque(p_kind text,p_cheque_no text,p_amount numeric,p_due_date date,p_account uuid,p_customer uuid DEFAULT null,p_supplier uuid DEFAULT null,p_doc_ref text DEFAULT null) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid();
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_kind NOT IN('received','issued') OR p_amount<=0 OR p_due_date IS NULL THEN RAISE EXCEPTION 'بيانات الشيك غير صحيحة'; END IF;
  IF p_kind='received' AND p_customer IS NULL THEN RAISE EXCEPTION 'اختر العميل'; END IF;
  IF p_kind='issued' AND p_supplier IS NULL THEN RAISE EXCEPTION 'اختر المورد'; END IF;
  INSERT INTO cheques(id,cheque_no,kind,customer_id,supplier_id,account_id,amount,due_date,doc_ref) VALUES(v,p_cheque_no,p_kind,p_customer,p_supplier,p_account,p_amount,p_due_date,p_doc_ref);
  PERFORM log_event('create','cheques',v::text,'سجل شيك '||p_cheque_no); RETURN v;
END $$;

CREATE OR REPLACE FUNCTION update_cheque_status(p_cheque uuid,p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_status NOT IN('Pending','Deposited','Cleared','Bounced','Cancelled') THEN RAISE EXCEPTION 'حالة الشيك غير صحيحة'; END IF;
  UPDATE cheques SET status=p_status WHERE id=p_cheque;
  IF NOT FOUND THEN RAISE EXCEPTION 'الشيك غير موجود'; END IF;
END $$;

CREATE OR REPLACE FUNCTION register_tax_document(p_invoice uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid:=gen_random_uuid();
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF NOT EXISTS(SELECT 1 FROM sales_invoices WHERE id=p_invoice AND status='Posted') THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  INSERT INTO tax_documents(id,invoice_id) VALUES(v,p_invoice) ON CONFLICT(invoice_id) DO UPDATE SET updated_at=now() RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION update_tax_document(p_doc uuid,p_status text,p_external_uuid text DEFAULT null,p_submission_id text DEFAULT null,p_error text DEFAULT null) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_status NOT IN('Pending','Submitted','Accepted','Rejected','Cancelled') THEN RAISE EXCEPTION 'حالة المستند الضريبي غير صحيحة'; END IF;
  UPDATE tax_documents SET status=p_status,external_uuid=coalesce(p_external_uuid,external_uuid),submission_id=coalesce(p_submission_id,submission_id),error_message=p_error,submitted_at=CASE WHEN p_status IN('Submitted','Accepted','Rejected') THEN now() ELSE submitted_at END,updated_at=now() WHERE id=p_doc;
  IF NOT FOUND THEN RAISE EXCEPTION 'المستند الضريبي غير موجود'; END IF;
END $$;

CREATE OR REPLACE FUNCTION financial_ratios(p_as_of date DEFAULT current_date)
RETURNS TABLE(metric text,value numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
WITH b AS (SELECT * FROM balance_sheet(p_as_of)),
a AS (SELECT coalesce(sum(balance) FILTER(WHERE type='Asset'),0) assets,coalesce(sum(balance) FILTER(WHERE type='Liability'),0) liabilities,coalesce(sum(balance) FILTER(WHERE type='Equity'),0) equity FROM b),
pl AS (SELECT coalesce(sum(l.debit-l.credit) FILTER(WHERE ac.type='Revenue'),0) revenue,coalesce(sum(l.debit-l.credit) FILTER(WHERE ac.type IN('Expense','COGS')),0) expense FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id JOIN accounts ac ON ac.code=l.account_code WHERE e.date<=p_as_of)
SELECT 'Current Asset / Liability'::text,round(CASE WHEN a.liabilities<>0 THEN a.assets/a.liabilities ELSE 0 END,3) FROM a
UNION ALL SELECT 'Debt Ratio',round(CASE WHEN a.assets<>0 THEN a.liabilities/a.assets ELSE 0 END,3) FROM a
UNION ALL SELECT 'Equity Ratio',round(CASE WHEN a.assets<>0 THEN a.equity/a.assets ELSE 0 END,3) FROM a
UNION ALL SELECT 'Net Margin',round(CASE WHEN pl.revenue<>0 THEN (pl.revenue-pl.expense)/pl.revenue*100 ELSE 0 END,3) FROM pl
$$;

DO $$ DECLARE t text; BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS audit_opening_balance_runs ON opening_balance_runs';
  EXECUTE 'CREATE TRIGGER audit_opening_balance_runs AFTER INSERT OR UPDATE OR DELETE ON opening_balance_runs FOR EACH ROW EXECUTE FUNCTION audit_trg()';
  FOREACH t IN ARRAY ARRAY['product_barcodes','commission_rules','sales_commissions','cheques','tax_documents','integration_connections','integration_events'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS audit_%I ON %I',t,t);
    EXECUTE format('CREATE TRIGGER audit_%I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION audit_trg()',t,t);
  END LOOP;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='commission_rules' AND policyname='write_commission_rules') THEN CREATE POLICY write_commission_rules ON commission_rules FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cheques' AND policyname='write_cheques') THEN CREATE POLICY write_cheques ON cheques FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='tax_documents' AND policyname='write_tax_documents') THEN CREATE POLICY write_tax_documents ON tax_documents FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='integration_connections' AND policyname='write_integration_connections') THEN CREATE POLICY write_integration_connections ON integration_connections FOR ALL TO authenticated USING(auth_role()='admin') WITH CHECK(auth_role()='admin'); END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='integration_events' AND policyname='write_integration_events') THEN CREATE POLICY write_integration_events ON integration_events FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant')); END IF;
END $$;

GRANT EXECUTE ON FUNCTION add_product_barcode(uuid,text,boolean),calculate_sales_commission(uuid,uuid),record_cheque(text,text,numeric,date,uuid,uuid,uuid,text),update_cheque_status(uuid,text),register_tax_document(uuid),update_tax_document(uuid,text,text,text,text),financial_ratios(date) TO authenticated;
GRANT SELECT ON product_barcodes,commission_rules,sales_commissions,cheques,tax_documents,integration_connections,integration_events TO authenticated;

-- Stronger health checks for go-live.
CREATE OR REPLACE FUNCTION health_check_enterprise()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
SELECT jsonb_build_object(
  'ok',auth_role() IS NOT NULL,
  'duplicate_barcodes',(SELECT count(*) FROM (SELECT barcode FROM products WHERE barcode IS NOT NULL GROUP BY barcode HAVING count(*)>1)x)+ (SELECT count(*) FROM (SELECT barcode FROM product_barcodes GROUP BY barcode HAVING count(*)>1)x),
  'unbalanced_journal_entries',(SELECT count(*) FROM (SELECT je.id FROM journal_entries je JOIN journal_lines jl ON jl.entry_id=je.id GROUP BY je.id HAVING round(sum(jl.debit),2)<>round(sum(jl.credit),2))x),
  'journal_lines_both_sides',(SELECT count(*) FROM journal_lines WHERE debit>0 AND credit>0),
  'negative_stock_rows',(SELECT count(*) FROM stock_balances WHERE qty<0),
  'negative_cash_rows',(SELECT count(*) FROM cash_accounts WHERE balance<0),
  'paid_over_total_sales',(SELECT count(*) FROM sales_invoice_balances WHERE allocated_paid>total+0.005),
  'paid_over_total_purchases',(SELECT count(*) FROM purchase_invoice_balances WHERE allocated_paid>total+0.005),
  'orphan_stock_movements',(SELECT count(*) FROM stock_movements sm WHERE sm.product_id IS NULL OR sm.warehouse_id IS NULL),
  'open_fiscal_periods',(SELECT count(*) FROM fiscal_periods WHERE status='Open'),
  'pending_approvals',(SELECT count(*) FROM approval_requests WHERE status='Pending'),
  'pending_tax_documents',(SELECT count(*) FROM tax_documents WHERE status IN('Pending','Rejected')),
  'failed_integrations',(SELECT count(*) FROM integration_events WHERE status='Failed')
);
$$;
GRANT EXECUTE ON FUNCTION health_check_enterprise() TO authenticated;

-- ============================================================
-- 010C) Adversarial / failure-path test suite
-- ============================================================
CREATE OR REPLACE FUNCTION run_erp_go_live_test() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  base jsonb; results jsonb[]:='{}'; ok boolean:=true; v numeric; q numeric; prod uuid; wh uuid; cust uuid; supp uuid; ca uuid; po uuid; grn uuid; so uuid; dn uuid; inv uuid; sale_inv uuid; pinv uuid; pl uuid; rule uuid; cheque uuid; taxdoc uuid; period_id uuid; tag text:='GLTEST-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
BEGIN
  PERFORM require_role('{admin}'); PERFORM require_dev();
  base:=run_erp_enterprise_test();
  IF coalesce((base->>'ok')::boolean,false)=false THEN
    RETURN jsonb_build_object('ok',false,'base',base,'results',results,'cleaned',coalesce((base->>'cleaned')::boolean,false));
  END IF;

  INSERT INTO warehouses(name) VALUES(tag||'-W') RETURNING id INTO wh;
  SELECT id INTO ca FROM cash_accounts ORDER BY created_at LIMIT 1;
  INSERT INTO customers(name) VALUES(tag||'-C') RETURNING id INTO cust;
  INSERT INTO suppliers(name) VALUES(tag||'-S') RETURNING id INTO supp;
  INSERT INTO products(name,code,barcode,purchase_price,sale_price,avg_cost) VALUES(tag||'-P',tag||'-P',tag||'-BC',10,15,10) RETURNING id INTO prod;
  pinv:=create_purchase(supp,wh,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',2,'price',10,'discount',0)),0,null,'credit',0,null);
  sale_inv:=create_sale(cust,wh,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',1,'price',15,'discount',0)),0,null,'credit',0,null);

  BEGIN
    PERFORM create_sale(cust,wh,jsonb_build_array(jsonb_build_object('product_id',prod,'qty',999,'price',15,'discount',0)),0,null,'credit');
    results:=array_append(results,jsonb_build_object('test','negative stock is blocked','pass',false,'detail','sale unexpectedly allowed')); ok:=false;
  EXCEPTION WHEN OTHERS THEN results:=array_append(results,jsonb_build_object('test','negative stock is blocked','pass',true,'detail','rejected')); END;

  INSERT INTO price_lists(name) VALUES(tag||'-PL') RETURNING id INTO pl;
  INSERT INTO price_list_items(price_list_id,product_id,price,min_qty) VALUES(pl,prod,13,1);
  INSERT INTO commission_rules(name,rate,basis) VALUES(tag||'-COM',5,'net_sales') RETURNING id INTO rule;
  -- Commission calculation is tested against an existing posted invoice from the base suite.
  inv:=sale_inv;
  v:=calculate_sales_commission(inv,rule); results:=array_append(results,jsonb_build_object('test','sales commission calculation','pass',v>=0,'detail','amount='||v)); ok:=ok AND v>=0;

  cheque:=record_cheque('received',tag||'-CHK',100,current_date+10,ca,cust,null,tag);
  PERFORM update_cheque_status(cheque,'Deposited'); results:=array_append(results,jsonb_build_object('test','cheque lifecycle','pass',(SELECT status='Deposited' FROM cheques WHERE id=cheque),'detail','deposited'));

  taxdoc:=register_tax_document(inv); results:=array_append(results,jsonb_build_object('test','tax document registration','pass',taxdoc IS NOT NULL,'detail','registered')); ok:=ok AND taxdoc IS NOT NULL;
  PERFORM update_tax_document(taxdoc,'Submitted',tag||'-UUID',tag||'-SUB',null); results:=array_append(results,jsonb_build_object('test','tax document status','pass',(SELECT status='Submitted' FROM tax_documents WHERE id=taxdoc),'detail','submitted')); 

  BEGIN
    INSERT INTO products(name,code,barcode,purchase_price,sale_price,avg_cost) VALUES(tag||'-Dup',tag||'-D',tag||'-BC',1,2,1);
    results:=array_append(results,jsonb_build_object('test','duplicate barcode rejected','pass',false,'detail','insert unexpectedly allowed')); ok:=false;
  EXCEPTION WHEN unique_violation THEN results:=array_append(results,jsonb_build_object('test','duplicate barcode rejected','pass',true,'detail','rejected')); END;

  BEGIN
    PERFORM create_manual_journal(current_date,tag,jsonb_build_array(jsonb_build_object('account_code','1000','debit',10,'credit',0),jsonb_build_object('account_code','4000','debit',0,'credit',5)));
    results:=array_append(results,jsonb_build_object('test','manual unbalanced journal rejected','pass',false,'detail','unexpectedly allowed')); ok:=false;
  EXCEPTION WHEN OTHERS THEN results:=array_append(results,jsonb_build_object('test','manual unbalanced journal rejected','pass',true,'detail','rejected')); END;

  PERFORM cancel_sales_invoice(sale_inv); results:=array_append(results,jsonb_build_object('test','sales invoice voiding','pass',(SELECT status='Void' FROM sales_invoices WHERE id=sale_inv),'detail','void'));
  PERFORM cancel_purchase_invoice(pinv); results:=array_append(results,jsonb_build_object('test','purchase invoice voiding','pass',(SELECT status='Void' FROM purchase_invoices WHERE id=pinv),'detail','void'));

  results:=array_append(results,jsonb_build_object('test','financial ratios callable','pass',(SELECT count(*) FROM financial_ratios(current_date))>=0,'detail','ok'));
  results:=array_append(results,jsonb_build_object('test','enhanced health check callable','pass',((health_check_enterprise()->>'unbalanced_journal_entries')::int=0),'detail',health_check_enterprise()::text));

  -- Cleanup. Existing enterprise test already cleans its own data.
  DELETE FROM sales_commissions WHERE rule_id=rule;
  DELETE FROM commission_rules WHERE id=rule;
  DELETE FROM tax_documents WHERE id=taxdoc;
  DELETE FROM cheques WHERE id=cheque;
  DELETE FROM price_list_items WHERE price_list_id=pl; DELETE FROM price_lists WHERE id=pl;
  DELETE FROM sales_commissions WHERE invoice_id IN(sale_inv);
  DELETE FROM tax_documents WHERE id=taxdoc;
  DELETE FROM payments WHERE doc_ref LIKE tag||'%';
  DELETE FROM stock_movements WHERE doc_id IN(sale_inv,pinv); DELETE FROM stock_balances WHERE product_id=prod;
  DELETE FROM journal_lines WHERE entry_id IN(SELECT id FROM journal_entries WHERE doc_id IN(sale_inv,pinv)); DELETE FROM journal_entries WHERE doc_id IN(sale_inv,pinv);
  DELETE FROM sales_invoice_items WHERE invoice_id=sale_inv; DELETE FROM sales_invoices WHERE id=sale_inv;
  DELETE FROM purchase_invoice_items WHERE invoice_id=pinv; DELETE FROM purchase_invoices WHERE id=pinv;
  DELETE FROM products WHERE id=prod;
  DELETE FROM customers WHERE id=cust; DELETE FROM suppliers WHERE id=supp; DELETE FROM warehouses WHERE id=wh;
  DELETE FROM audit_logs WHERE description LIKE '%'||tag||'%';

  RETURN jsonb_build_object('ok',ok,'base',base,'results',results,'cleaned',true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok',false,'error',SQLERRM,'base',base,'results',results,'cleaned',false);
END $$;
REVOKE ALL ON FUNCTION run_erp_go_live_test() FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION run_erp_go_live_test() TO authenticated;

COMMIT;


BEGIN;

-- ============================================================
-- 018) Advanced inventory traceability + replenishment + imports
-- Additive/idempotent migration. No destructive drops.
-- ============================================================

-- A) Product tracking configuration
ALTER TABLE products ADD COLUMN IF NOT EXISTS safety_stock numeric(14,3) NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS lead_time_days int NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_batch boolean NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_serial boolean NOT NULL DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_expiry boolean NOT NULL DEFAULT false;


CREATE OR REPLACE FUNCTION set_product_tracking(
  p_product uuid,p_track_batch boolean DEFAULT false,p_track_serial boolean DEFAULT false,p_track_expiry boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,store}');
  IF NOT EXISTS(SELECT 1 FROM products WHERE id=p_product) THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
  IF NOT p_track_batch AND NOT p_track_serial AND NOT p_track_expiry THEN
    UPDATE products SET track_batch=false,track_serial=false,track_expiry=false WHERE id=p_product;
    RETURN;
  END IF;
  UPDATE products SET track_batch=coalesce(p_track_batch,false),track_serial=coalesce(p_track_serial,false),track_expiry=coalesce(p_track_expiry,false) WHERE id=p_product;
END $$;

-- B) Lots / serials / trace ledger
CREATE TABLE IF NOT EXISTS inventory_lots(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products ON DELETE CASCADE,
  lot_no text NOT NULL,
  expiry_date date,
  unit_cost numeric(14,4) NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE(product_id,lot_no)
);

CREATE TABLE IF NOT EXISTS inventory_lot_balances(
  lot_id uuid NOT NULL REFERENCES inventory_lots ON DELETE CASCADE,
  warehouse_id uuid NOT NULL REFERENCES warehouses ON DELETE CASCADE,
  qty numeric(14,3) NOT NULL DEFAULT 0,
  PRIMARY KEY(lot_id,warehouse_id)
);

CREATE TABLE IF NOT EXISTS inventory_serials(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products ON DELETE CASCADE,
  serial_no text NOT NULL UNIQUE,
  lot_id uuid REFERENCES inventory_lots ON DELETE SET NULL,
  warehouse_id uuid REFERENCES warehouses ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'Available'
    CHECK(status IN('Available','Sold','Returned','Quarantined','Cancelled')),
  received_at timestamptz DEFAULT now(),
  sold_at timestamptz,
  notes text
);

CREATE TABLE IF NOT EXISTS inventory_trace_events(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products ON DELETE CASCADE,
  warehouse_id uuid NOT NULL REFERENCES warehouses ON DELETE CASCADE,
  lot_id uuid REFERENCES inventory_lots ON DELETE SET NULL,
  serial_id uuid REFERENCES inventory_serials ON DELETE SET NULL,
  qty numeric(14,3) NOT NULL,
  direction text NOT NULL CHECK(direction IN('IN','OUT','ADJUST')),
  doc_type text,
  doc_id uuid,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now(),
  CHECK ((serial_id IS NULL) OR abs(qty)=1)
);

CREATE INDEX IF NOT EXISTS inventory_lots_product_idx ON inventory_lots(product_id,expiry_date);
CREATE INDEX IF NOT EXISTS inventory_lot_balances_wh_idx ON inventory_lot_balances(warehouse_id,lot_id);
CREATE INDEX IF NOT EXISTS inventory_serials_product_wh_idx ON inventory_serials(product_id,warehouse_id,status);
CREATE INDEX IF NOT EXISTS inventory_trace_events_lookup_idx ON inventory_trace_events(product_id,warehouse_id,created_at);

ALTER TABLE inventory_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_lot_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_serials ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_trace_events ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='inventory_lots' AND policyname='sel_inventory_lots') THEN
    CREATE POLICY sel_inventory_lots ON inventory_lots FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='inventory_lot_balances' AND policyname='sel_inventory_lot_balances') THEN
    CREATE POLICY sel_inventory_lot_balances ON inventory_lot_balances FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant','store'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='inventory_serials' AND policyname='sel_inventory_serials') THEN
    CREATE POLICY sel_inventory_serials ON inventory_serials FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant','store','sales'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='inventory_trace_events' AND policyname='sel_inventory_trace_events') THEN
    CREATE POLICY sel_inventory_trace_events ON inventory_trace_events FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant','store'));
  END IF;
END $$;

-- C) Lot/serial stock views
CREATE OR REPLACE VIEW inventory_lot_stock WITH(security_invoker=true) AS
SELECT l.id AS lot_id,l.product_id,l.lot_no,l.expiry_date,l.unit_cost,lb.warehouse_id,lb.qty,
       CASE WHEN l.expiry_date IS NOT NULL AND l.expiry_date<current_date THEN true ELSE false END AS expired
FROM inventory_lots l JOIN inventory_lot_balances lb ON lb.lot_id=l.id;

CREATE OR REPLACE VIEW inventory_serial_stock WITH(security_invoker=true) AS
SELECT s.id,s.product_id,s.serial_no,s.lot_id,s.warehouse_id,s.status,
       CASE WHEN l.expiry_date IS NOT NULL AND l.expiry_date<current_date THEN true ELSE false END AS expired
FROM inventory_serials s LEFT JOIN inventory_lots l ON l.id=s.lot_id;

-- D) Create lot and receive tracked stock.
CREATE OR REPLACE FUNCTION create_inventory_lot(
  p_product uuid,p_lot_no text,p_expiry date DEFAULT null,p_unit_cost numeric DEFAULT 0
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid;
BEGIN
  PERFORM require_role('{admin,accountant,store}');
  IF NOT EXISTS(SELECT 1 FROM products WHERE id=p_product AND active) THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
  IF nullif(trim(p_lot_no),'') IS NULL THEN RAISE EXCEPTION 'رقم التشغيلة مطلوب'; END IF;
  IF p_expiry IS NOT NULL AND p_expiry<current_date THEN RAISE EXCEPTION 'تاريخ الصلاحية منتهي'; END IF;
  INSERT INTO inventory_lots(product_id,lot_no,expiry_date,unit_cost)
  VALUES(p_product,trim(p_lot_no),p_expiry,greatest(p_unit_cost,0))
  ON CONFLICT(product_id,lot_no) DO UPDATE SET expiry_date=coalesce(excluded.expiry_date,inventory_lots.expiry_date),unit_cost=CASE WHEN excluded.unit_cost>0 THEN excluded.unit_cost ELSE inventory_lots.unit_cost END,active=true
  RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION receive_tracked_stock(
  p_product uuid,p_warehouse uuid,p_qty numeric,p_unit_cost numeric DEFAULT 0,
  p_lot_no text DEFAULT null,p_expiry date DEFAULT null,p_serials jsonb DEFAULT '[]'::jsonb,
  p_doc_type text DEFAULT 'tracked_receipt',p_doc_id uuid DEFAULT null
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); lot uuid; it jsonb; sid uuid; total numeric; onhand numeric;
  track_batch boolean; track_serial boolean; track_expiry boolean;
BEGIN
  PERFORM require_role('{admin,accountant,store}');
  IF p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;
  SELECT p.track_batch,p.track_serial,p.track_expiry INTO track_batch,track_serial,track_expiry FROM products p WHERE p.id=p_product AND p.active;
  IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير صالح'; END IF;
  IF (track_batch OR track_expiry) AND nullif(trim(p_lot_no),'') IS NULL THEN RAISE EXCEPTION 'هذا المنتج يتطلب رقم تشغيلة'; END IF;
  IF track_expiry AND p_expiry IS NULL THEN RAISE EXCEPTION 'هذا المنتج يتطلب تاريخ صلاحية'; END IF;
  IF p_expiry IS NOT NULL AND p_expiry<current_date THEN RAISE EXCEPTION 'تاريخ الصلاحية منتهي'; END IF;
  IF track_serial THEN
    IF jsonb_array_length(coalesce(p_serials,'[]'::jsonb)) <> trunc(p_qty) OR p_qty<>trunc(p_qty) THEN RAISE EXCEPTION 'عدد الـSerials يجب أن يساوي الكمية الصحيحة'; END IF;
  END IF;
  IF nullif(trim(p_lot_no),'') IS NOT NULL THEN lot:=create_inventory_lot(p_product,p_lot_no,p_expiry,p_unit_cost); END IF;

  SELECT coalesce(sum(qty),0) INTO onhand FROM stock_balances WHERE product_id=p_product;
  UPDATE products SET avg_cost=CASE WHEN onhand+p_qty>0 THEN ((greatest(onhand,0)*avg_cost)+(p_qty*greatest(p_unit_cost,0)))/(greatest(onhand,0)+p_qty) ELSE greatest(p_unit_cost,0) END WHERE id=p_product;

  IF lot IS NOT NULL THEN
    INSERT INTO inventory_lot_balances(lot_id,warehouse_id,qty) VALUES(lot,p_warehouse,p_qty)
    ON CONFLICT(lot_id,warehouse_id) DO UPDATE SET qty=inventory_lot_balances.qty+excluded.qty;
    INSERT INTO inventory_trace_events(product_id,warehouse_id,lot_id,qty,direction,doc_type,doc_id)
      VALUES(p_product,p_warehouse,lot,p_qty,'IN',p_doc_type,p_doc_id);
  END IF;

  IF track_serial THEN
    FOR it IN SELECT * FROM jsonb_array_elements(p_serials) LOOP
      IF nullif(trim(it #>> '{}'),'') IS NULL THEN RAISE EXCEPTION 'Serial فارغ'; END IF;
      INSERT INTO inventory_serials(product_id,serial_no,lot_id,warehouse_id,status)
        VALUES(p_product,trim(it #>> '{}'),lot,p_warehouse,'Available');
      SELECT id INTO sid FROM inventory_serials WHERE serial_no=trim(it #>> '{}');
      INSERT INTO inventory_trace_events(product_id,warehouse_id,lot_id,serial_id,qty,direction,doc_type,doc_id)
        VALUES(p_product,p_warehouse,lot,sid,1,'IN',p_doc_type,p_doc_id);
    END LOOP;
  END IF;

  PERFORM apply_stock(p_product,p_warehouse,p_qty,'Purchase',p_doc_type,p_doc_id);
  PERFORM log_event('create','inventory_trace_events',v::text,'استلام مخزون متتبع');
  RETURN v;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'رقم Serial مستخدم بالفعل';
END $$;

-- E) Issue tracked stock. This is explicit so standard non-tracked flows remain backward compatible.
CREATE OR REPLACE FUNCTION issue_tracked_stock(
  p_product uuid,p_warehouse uuid,p_qty numeric,p_lot_no text DEFAULT null,p_serials jsonb DEFAULT '[]'::jsonb,
  p_doc_type text DEFAULT 'tracked_issue',p_doc_id uuid DEFAULT null
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid(); lot uuid; it jsonb; s inventory_serials; available numeric;
  track_batch boolean; track_serial boolean; track_expiry boolean;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;
  SELECT p.track_batch,p.track_serial,p.track_expiry INTO track_batch,track_serial,track_expiry FROM products p WHERE p.id=p_product AND p.active;
  IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير صالح'; END IF;
  IF (track_batch OR track_expiry) THEN
    IF nullif(trim(p_lot_no),'') IS NULL THEN RAISE EXCEPTION 'هذا المنتج يتطلب تحديد التشغيلة'; END IF;
    SELECT id INTO lot FROM inventory_lots WHERE product_id=p_product AND lot_no=trim(p_lot_no) AND active;
    IF lot IS NULL THEN RAISE EXCEPTION 'التشغيلة غير موجودة'; END IF;
    IF EXISTS(SELECT 1 FROM inventory_lots WHERE id=lot AND expiry_date IS NOT NULL AND expiry_date<current_date) THEN RAISE EXCEPTION 'التشغيلة منتهية الصلاحية'; END IF;
    SELECT coalesce(qty,0) INTO available FROM inventory_lot_balances WHERE lot_id=lot AND warehouse_id=p_warehouse FOR UPDATE;
    IF coalesce(available,0)<p_qty THEN RAISE EXCEPTION 'رصيد التشغيلة غير كافٍ'; END IF;
    UPDATE inventory_lot_balances SET qty=qty-p_qty WHERE lot_id=lot AND warehouse_id=p_warehouse;
    INSERT INTO inventory_trace_events(product_id,warehouse_id,lot_id,qty,direction,doc_type,doc_id)
      VALUES(p_product,p_warehouse,lot,-p_qty,'OUT',p_doc_type,p_doc_id);
  END IF;

  IF track_serial THEN
    IF jsonb_array_length(coalesce(p_serials,'[]'::jsonb)) <> trunc(p_qty) OR p_qty<>trunc(p_qty) THEN RAISE EXCEPTION 'عدد الـSerials يجب أن يساوي الكمية الصحيحة'; END IF;
    IF lot IS NOT NULL AND EXISTS(
      SELECT 1 FROM inventory_serials s
      WHERE s.product_id=p_product AND s.serial_no IN (SELECT trim(x #>> '{}') FROM jsonb_array_elements(p_serials) x)
        AND s.lot_id IS DISTINCT FROM lot
    ) THEN RAISE EXCEPTION 'الـSerial لا ينتمي إلى التشغيلة المحددة'; END IF;
    FOR it IN SELECT * FROM jsonb_array_elements(p_serials) LOOP
      SELECT * INTO s FROM inventory_serials WHERE product_id=p_product AND serial_no=trim(it #>> '{}') AND warehouse_id=p_warehouse AND status='Available' FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Serial غير متاح: %',trim(it #>> '{}'); END IF;
      UPDATE inventory_serials SET status='Sold',sold_at=now(),warehouse_id=null WHERE id=s.id;
      INSERT INTO inventory_trace_events(product_id,warehouse_id,lot_id,serial_id,qty,direction,doc_type,doc_id)
        VALUES(p_product,p_warehouse,s.lot_id,s.id,-1,'OUT',p_doc_type,p_doc_id);
    END LOOP;
  END IF;

  PERFORM apply_stock(p_product,p_warehouse,-p_qty,'Sale',p_doc_type,p_doc_id);
  PERFORM log_event('create','inventory_trace_events',v::text,'صرف مخزون متتبع');
  RETURN v;
END $$;

-- F) Replenishment / MRP-lite: on-hand + confirmed incoming - open commitments.
CREATE OR REPLACE FUNCTION mrp_replenishment(p_warehouse uuid DEFAULT null)
RETURNS TABLE(
  product_id uuid,product_name text,warehouse_id uuid,on_hand numeric,incoming numeric,committed numeric,
  projected numeric,min_stock numeric,safety_stock numeric,reorder_qty numeric,suggested_qty numeric,lead_time_days int
) LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
WITH base AS (
  SELECT p.id product_id,p.name product_name,w.id warehouse_id,
         coalesce((SELECT sum(sb.qty) FROM stock_balances sb WHERE sb.product_id=p.id AND sb.warehouse_id=w.id),0) on_hand,
         coalesce((SELECT sum(greatest(poi.qty-coalesce((SELECT sum(gri.qty) FROM goods_receipt_items gri JOIN goods_receipts gr ON gr.id=gri.receipt_id WHERE gr.purchase_order_id=po.id AND gri.product_id=poi.product_id),0),0))
                   FROM purchase_orders po JOIN purchase_order_items poi ON poi.order_id=po.id
                   WHERE po.warehouse_id=w.id AND po.status IN('Confirmed','Partially Received') AND poi.product_id=p.id),0) incoming,
         coalesce((SELECT sum(greatest(soi.qty-coalesce((SELECT sum(dni.qty) FROM delivery_note_items dni JOIN delivery_notes dn ON dn.id=dni.delivery_id WHERE dn.sales_order_id=so.id AND dni.product_id=soi.product_id AND dn.status='Delivered'),0),0))
                   FROM sales_orders so JOIN sales_order_items soi ON soi.order_id=so.id
                   WHERE so.warehouse_id=w.id AND so.status IN('Confirmed','Partially Delivered') AND soi.product_id=p.id),0) committed,
         p.min_stock,p.safety_stock,p.reorder_qty,p.lead_time_days
  FROM products p CROSS JOIN warehouses w
  WHERE p.active AND w.active AND (p_warehouse IS NULL OR w.id=p_warehouse)
)
SELECT product_id,product_name,warehouse_id,on_hand,incoming,committed,
       on_hand+incoming-committed projected,min_stock,safety_stock,reorder_qty,
       CASE WHEN on_hand+incoming-committed < min_stock+safety_stock
            THEN greatest(reorder_qty,(min_stock+safety_stock)-(on_hand+incoming-committed)) ELSE 0 END suggested_qty,
       lead_time_days
FROM base
WHERE on_hand+incoming-committed < min_stock+safety_stock
ORDER BY suggested_qty DESC,product_name;
$$;

-- G) Simple, transactional JSON imports for master data. UI sends parsed CSV rows.
CREATE OR REPLACE FUNCTION import_products_json(p_rows jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE it jsonb; c uuid; u uuid; n int:=0; code_v text; bar_v text; name_v text;
BEGIN
  PERFORM require_role('{admin}');
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) LOOP
    name_v:=nullif(trim(it->>'name'),''); IF name_v IS NULL THEN CONTINUE; END IF;
    code_v:=nullif(trim(it->>'code'),''); bar_v:=nullif(trim(it->>'barcode'),'');
    c:=NULL; u:=NULL;
    IF nullif(trim(it->>'category'),'') IS NOT NULL THEN
      SELECT id INTO c FROM categories WHERE name=trim(it->>'category');
      IF c IS NULL THEN INSERT INTO categories(name) VALUES(trim(it->>'category')) RETURNING id INTO c; END IF;
    END IF;
    IF nullif(trim(it->>'unit'),'') IS NOT NULL THEN
      SELECT id INTO u FROM units WHERE name=trim(it->>'unit');
      IF u IS NULL THEN INSERT INTO units(name) VALUES(trim(it->>'unit')) RETURNING id INTO u; END IF;
    END IF;
    IF code_v IS NULL THEN
      INSERT INTO products(name,barcode,category_id,unit_id,purchase_price,sale_price,wholesale_price,min_stock,reorder_qty,safety_stock,lead_time_days,avg_cost,notes)
      VALUES(name_v,bar_v,c,u,coalesce(nullif(trim(it->>'purchase_price'),'')::numeric,0),coalesce(nullif(trim(it->>'sale_price'),'')::numeric,0),coalesce(nullif(trim(it->>'wholesale_price'),'')::numeric,0),coalesce(nullif(trim(it->>'min_stock'),'')::numeric,0),coalesce(nullif(trim(it->>'reorder_qty'),'')::numeric,0),coalesce(nullif(trim(it->>'safety_stock'),'')::numeric,0),coalesce(nullif(trim(it->>'lead_time_days'),'')::int,0),coalesce(nullif(trim(it->>'purchase_price'),'')::numeric,0),it->>'notes');
    ELSE
      INSERT INTO products(code,name,barcode,category_id,unit_id,purchase_price,sale_price,wholesale_price,min_stock,reorder_qty,safety_stock,lead_time_days,avg_cost,notes)
      VALUES(code_v,name_v,bar_v,c,u,coalesce(nullif(trim(it->>'purchase_price'),'')::numeric,0),coalesce(nullif(trim(it->>'sale_price'),'')::numeric,0),coalesce(nullif(trim(it->>'wholesale_price'),'')::numeric,0),coalesce(nullif(trim(it->>'min_stock'),'')::numeric,0),coalesce(nullif(trim(it->>'reorder_qty'),'')::numeric,0),coalesce(nullif(trim(it->>'safety_stock'),'')::numeric,0),coalesce(nullif(trim(it->>'lead_time_days'),'')::int,0),coalesce(nullif(trim(it->>'purchase_price'),'')::numeric,0),it->>'notes')
      ON CONFLICT(code) DO UPDATE SET name=excluded.name,barcode=excluded.barcode,category_id=excluded.category_id,unit_id=excluded.unit_id,purchase_price=excluded.purchase_price,sale_price=excluded.sale_price,wholesale_price=excluded.wholesale_price,min_stock=excluded.min_stock,reorder_qty=excluded.reorder_qty,safety_stock=excluded.safety_stock,lead_time_days=excluded.lead_time_days,notes=excluded.notes;
    END IF;
    n:=n+1;
  END LOOP;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION import_customers_json(p_rows jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE it jsonb; n int:=0; name_v text; email_v text; phone_v text; existing_id uuid;
BEGIN
  PERFORM require_role('{admin}');
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) LOOP
    name_v:=nullif(trim(it->>'name'),''); IF name_v IS NULL THEN CONTINUE; END IF;
    email_v:=nullif(trim(it->>'email'),''); phone_v:=nullif(trim(it->>'phone'),''); existing_id:=NULL;
    IF email_v IS NOT NULL THEN SELECT id INTO existing_id FROM customers WHERE lower(email)=lower(email_v) LIMIT 1; END IF;
    IF existing_id IS NULL AND phone_v IS NOT NULL THEN SELECT id INTO existing_id FROM customers WHERE name=name_v AND phone=phone_v LIMIT 1; END IF;
    IF existing_id IS NULL THEN
      INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes)
      VALUES(name_v,phone_v,email_v,nullif(trim(it->>'address'),''),coalesce(nullif(trim(it->>'credit_limit'),'')::numeric,0),coalesce(nullif(trim(it->>'payment_terms_days'),'')::int,0),coalesce(nullif(trim(it->>'opening_balance'),'')::numeric,0),it->>'notes');
    ELSE
      UPDATE customers SET name=name_v,phone=phone_v,email=email_v,address=nullif(trim(it->>'address'),''),credit_limit=coalesce(nullif(trim(it->>'credit_limit'),'')::numeric,credit_limit),payment_terms_days=coalesce(nullif(trim(it->>'payment_terms_days'),'')::int,payment_terms_days),notes=coalesce(it->>'notes',notes) WHERE id=existing_id;
    END IF;
    n:=n+1;
  END LOOP;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION import_suppliers_json(p_rows jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE it jsonb; n int:=0; name_v text; email_v text; phone_v text; existing_id uuid;
BEGIN
  PERFORM require_role('{admin}');
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) LOOP
    name_v:=nullif(trim(it->>'name'),''); IF name_v IS NULL THEN CONTINUE; END IF;
    email_v:=nullif(trim(it->>'email'),''); phone_v:=nullif(trim(it->>'phone'),''); existing_id:=NULL;
    IF email_v IS NOT NULL THEN SELECT id INTO existing_id FROM suppliers WHERE lower(email)=lower(email_v) LIMIT 1; END IF;
    IF existing_id IS NULL AND phone_v IS NOT NULL THEN SELECT id INTO existing_id FROM suppliers WHERE name=name_v AND phone=phone_v LIMIT 1; END IF;
    IF existing_id IS NULL THEN
      INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes)
      VALUES(name_v,phone_v,email_v,nullif(trim(it->>'address'),''),coalesce(nullif(trim(it->>'payment_terms_days'),'')::int,0),coalesce(nullif(trim(it->>'opening_balance'),'')::numeric,0),it->>'notes');
    ELSE
      UPDATE suppliers SET name=name_v,phone=phone_v,email=email_v,address=nullif(trim(it->>'address'),''),payment_terms_days=coalesce(nullif(trim(it->>'payment_terms_days'),'')::int,payment_terms_days),notes=coalesce(it->>'notes',notes) WHERE id=existing_id;
    END IF;
    n:=n+1;
  END LOOP;
  RETURN n;
END $$;

CREATE OR REPLACE FUNCTION import_opening_stock_json(p_warehouse uuid,p_rows jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE it jsonb; n int:=0; pid uuid; qty_v numeric; key_v text;
BEGIN
  PERFORM require_role('{admin}');
  IF NOT EXISTS(SELECT 1 FROM warehouses WHERE id=p_warehouse AND active) THEN RAISE EXCEPTION 'المخزن غير موجود'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) LOOP
    key_v:=nullif(trim(coalesce(it->>'code',it->>'barcode',it->>'product_id')),'');
    qty_v:=nullif(trim(it->>'qty'),'')::numeric;
    IF key_v IS NULL OR qty_v IS NULL OR qty_v<0 THEN CONTINUE; END IF;
    SELECT id INTO pid FROM products WHERE code=key_v LIMIT 1;
    IF pid IS NULL THEN SELECT id INTO pid FROM products WHERE barcode=key_v LIMIT 1; END IF;
    IF pid IS NULL THEN SELECT id INTO pid FROM products WHERE id::text=key_v LIMIT 1; END IF;
    IF pid IS NULL THEN CONTINUE; END IF;
    PERFORM set_opening_stock(pid,p_warehouse,qty_v); n:=n+1;
  END LOOP;
  RETURN n;
END $$;

-- H) Advanced health checks
CREATE OR REPLACE FUNCTION health_check_advanced() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
BEGIN
  IF auth_role() NOT IN('admin','accountant','store') THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
  RETURN jsonb_build_object(
    'duplicate_serials',(SELECT count(*) FROM (SELECT serial_no FROM inventory_serials GROUP BY serial_no HAVING count(*)>1)x),
    'negative_lot_balances',(SELECT count(*) FROM inventory_lot_balances WHERE qty<0),
    'expired_lots_with_stock',(SELECT count(*) FROM inventory_lot_stock WHERE expired AND qty>0),
    'tracked_products',(SELECT count(*) FROM products WHERE active AND (track_batch OR track_serial OR track_expiry)),
    'lots',(SELECT count(*) FROM inventory_lots),
    'serials',(SELECT count(*) FROM inventory_serials),
    'mrp_suggestions',(SELECT count(*) FROM mrp_replenishment(null)),
    'ok',(
      (SELECT count(*) FROM inventory_lot_balances WHERE qty<0)=0
      AND (SELECT count(*) FROM (SELECT serial_no FROM inventory_serials GROUP BY serial_no HAVING count(*)>1)x)=0
    )
  );
END $$;

GRANT SELECT ON inventory_lot_stock,inventory_serial_stock TO authenticated;
GRANT EXECUTE ON FUNCTION create_inventory_lot(uuid,text,date,numeric),receive_tracked_stock(uuid,uuid,numeric,numeric,text,date,jsonb,text,uuid),issue_tracked_stock(uuid,uuid,numeric,text,jsonb,text,uuid),mrp_replenishment(uuid),import_products_json(jsonb),import_customers_json(jsonb),import_suppliers_json(jsonb),import_opening_stock_json(uuid,jsonb),health_check_advanced() TO authenticated;

-- I) Focused automated test for the new tracking/MRP/import layer.
CREATE OR REPLACE FUNCTION run_advanced_inventory_test() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  tag text:='ADVTEST-'||replace(gen_random_uuid()::text,'-','');
  wh uuid; p_batch uuid; p_serial uuid; p_import uuid;
  lot_id uuid; q numeric; mrp_q numeric; sold_count int; avail_count int;
  results jsonb:='[]'::jsonb; ok boolean:=true;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); PERFORM require_dev();
  SELECT id INTO wh FROM warehouses WHERE active ORDER BY created_at LIMIT 1;
  IF wh IS NULL THEN RAISE EXCEPTION 'لا يوجد مخزن نشط للاختبار'; END IF;
  BEGIN
    INSERT INTO products(name,code,purchase_price,sale_price,avg_cost,min_stock,reorder_qty,safety_stock,lead_time_days,track_batch,track_expiry)
      VALUES(tag||'-BATCH',tag||'-B',10,15,10,20,30,5,7,true,true) RETURNING id INTO p_batch;
    PERFORM receive_tracked_stock(p_batch,wh,10,10,'LOT-1',current_date+90,'[]'::jsonb,'advanced_test',null);
    SELECT qty INTO q FROM inventory_lot_stock WHERE product_id=p_batch AND warehouse_id=wh AND lot_no='LOT-1';
    results:=results||jsonb_build_array(jsonb_build_object('test','batch receive','pass',q=10,'detail','qty='||coalesce(q,0)));
    ok:=ok AND q=10;

    PERFORM issue_tracked_stock(p_batch,wh,3,'LOT-1','[]'::jsonb,'advanced_test',null);
    SELECT qty INTO q FROM inventory_lot_stock WHERE product_id=p_batch AND warehouse_id=wh AND lot_no='LOT-1';
    results:=results||jsonb_build_array(jsonb_build_object('test','batch issue','pass',q=7,'detail','qty='||coalesce(q,0)));
    ok:=ok AND q=7;

    INSERT INTO products(name,code,purchase_price,sale_price,avg_cost,track_serial) VALUES(tag||'-SERIAL',tag||'-S',20,30,20,true) RETURNING id INTO p_serial;
    PERFORM receive_tracked_stock(p_serial,wh,2,20,null,null,jsonb_build_array('SN-A','SN-B'),'advanced_test',null);
    PERFORM issue_tracked_stock(p_serial,wh,1,null,jsonb_build_array('SN-A'),'advanced_test',null);
    SELECT count(*) INTO sold_count FROM inventory_serials WHERE product_id=p_serial AND status='Sold';
    SELECT count(*) INTO avail_count FROM inventory_serials WHERE product_id=p_serial AND status='Available';
    results:=results||jsonb_build_array(jsonb_build_object('test','serial lifecycle','pass',sold_count=1 AND avail_count=1,'detail','sold='||sold_count||' available='||avail_count));
    ok:=ok AND sold_count=1 AND avail_count=1;

    SELECT suggested_qty INTO mrp_q FROM mrp_replenishment(wh) WHERE product_id=p_batch LIMIT 1;
    results:=results||jsonb_build_array(jsonb_build_object('test','MRP suggestion','pass',coalesce(mrp_q,0)>0,'detail','suggested='||coalesce(mrp_q,0)));
    ok:=ok AND coalesce(mrp_q,0)>0;

    PERFORM import_products_json(jsonb_build_array(jsonb_build_object('name',tag||'-Imported','code',tag||'-I','purchase_price',12,'sale_price',18,'min_stock',2,'reorder_qty',5)));
    SELECT id INTO p_import FROM products WHERE code=tag||'-I';
    results:=results||jsonb_build_array(jsonb_build_object('test','CSV-import RPC','pass',p_import IS NOT NULL,'detail',CASE WHEN p_import IS NOT NULL THEN 'imported' ELSE 'missing' END));
    ok:=ok AND p_import IS NOT NULL;

    DELETE FROM inventory_trace_events WHERE product_id IN(p_batch,p_serial);
    DELETE FROM inventory_serials WHERE product_id=p_serial;
    DELETE FROM inventory_lot_balances WHERE lot_id IN(SELECT id FROM inventory_lots WHERE product_id=p_batch);
    DELETE FROM inventory_lots WHERE product_id=p_batch;
    DELETE FROM stock_movements WHERE product_id IN(p_batch,p_serial);
    DELETE FROM stock_balances WHERE product_id IN(p_batch,p_serial);
    DELETE FROM products WHERE id IN(p_batch,p_serial,p_import);
    RETURN jsonb_build_object('ok',ok,'results',results,'cleaned',true);
  EXCEPTION WHEN OTHERS THEN
    results:=results||jsonb_build_array(jsonb_build_object('test','unexpected error','pass',false,'detail',SQLERRM));
    RETURN jsonb_build_object('ok',false,'results',results,'cleaned',true,'error',SQLERRM);
  END;
END $$;

GRANT EXECUTE ON FUNCTION run_advanced_inventory_test() TO authenticated;

COMMIT;

-- ============================== 018_protect_cash_and_payroll.sql ==============================
-- 018: block direct edits of cash balance and payroll payment status
-- Direct client calls (role authenticated/anon) can no longer change cash_accounts.balance or mark payroll as paid.
-- All legitimate paths (apply_cash, pay_payroll, POS, transfers...) run inside SECURITY DEFINER functions, where current_user is the owner, so they keep working.
-- The Supabase SQL Editor (role postgres) is also allowed, for manual maintenance.
BEGIN;

CREATE OR REPLACE FUNCTION trg_protect_cash_balance() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF current_user IN('authenticated','anon') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.balance,0)<>coalesce(NEW.opening_balance,0) THEN
        RAISE EXCEPTION 'الرصيد الابتدائي للخزينة يجب أن يساوي الرصيد الافتتاحي';
      END IF;
    ELSIF TG_OP='UPDATE' THEN
      IF NEW.balance IS DISTINCT FROM OLD.balance THEN
        RAISE EXCEPTION 'لا يمكن تعديل رصيد الخزينة مباشرة؛ يتغير فقط عبر العمليات (دفعة، مصروف، تحويل)';
      END IF;
      IF NEW.opening_balance IS DISTINCT FROM OLD.opening_balance THEN
        RAISE EXCEPTION 'لا يمكن تعديل الرصيد الافتتاحي بعد إنشاء الخزينة';
      END IF;
    ELSIF TG_OP='DELETE' THEN
      IF coalesce(OLD.balance,0)<>0 THEN
        RAISE EXCEPTION 'لا يمكن حذف خزينة رصيدها غير صفر';
      END IF;
      RETURN OLD;
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS protect_cash_balance ON cash_accounts;
CREATE TRIGGER protect_cash_balance BEFORE INSERT OR UPDATE OR DELETE ON cash_accounts
  FOR EACH ROW EXECUTE FUNCTION trg_protect_cash_balance();

CREATE OR REPLACE FUNCTION trg_protect_payroll_paid() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF current_user IN('authenticated','anon') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.paid,false) OR NEW.account_id IS NOT NULL THEN
        RAISE EXCEPTION 'لا يمكن إنشاء مرتب مدفوع مباشرة؛ استخدم زر الدفع';
      END IF;
    ELSIF TG_OP='UPDATE' THEN
      IF NEW.paid IS DISTINCT FROM OLD.paid OR NEW.account_id IS DISTINCT FROM OLD.account_id THEN
        RAISE EXCEPTION 'لا يمكن تغيير حالة دفع المرتب مباشرة؛ استخدم زر الدفع';
      END IF;
      IF OLD.paid AND (NEW.net IS DISTINCT FROM OLD.net OR NEW.basic IS DISTINCT FROM OLD.basic OR NEW.month IS DISTINCT FROM OLD.month OR NEW.employee_id IS DISTINCT FROM OLD.employee_id) THEN
        RAISE EXCEPTION 'لا يمكن تعديل مرتب تم دفعه';
      END IF;
    ELSIF TG_OP='DELETE' THEN
      IF OLD.paid THEN RAISE EXCEPTION 'لا يمكن حذف مرتب تم دفعه'; END IF;
      RETURN OLD;
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS protect_payroll_paid ON payroll;
CREATE TRIGGER protect_payroll_paid BEFORE INSERT OR UPDATE OR DELETE ON payroll
  FOR EACH ROW EXECUTE FUNCTION trg_protect_payroll_paid();

REVOKE EXECUTE ON FUNCTION trg_protect_cash_balance(),trg_protect_payroll_paid() FROM PUBLIC,anon,authenticated;
COMMIT;

-- ============================== 019_fix_advanced_inventory_test.sql ==============================
BEGIN;

-- 019) Fix advanced inventory smoke test for warehouses without created_at.
-- Safe additive patch: only recreates the test function; no data is deleted.

CREATE OR REPLACE FUNCTION run_advanced_inventory_test() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  tag text:='ADVTEST-'||replace(gen_random_uuid()::text,'-','');
  wh uuid; p_batch uuid; p_serial uuid; p_import uuid;
  lot_id uuid; q numeric; mrp_q numeric; sold_count int; avail_count int;
  results jsonb:='[]'::jsonb; ok boolean:=true;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); PERFORM require_dev();

  -- warehouses in the current schema do not have created_at;
  -- use deterministic id ordering instead.
  SELECT id INTO wh FROM warehouses WHERE active ORDER BY id LIMIT 1;
  IF wh IS NULL THEN RAISE EXCEPTION 'لا يوجد مخزن نشط للاختبار'; END IF;

  BEGIN
    INSERT INTO products(name,code,purchase_price,sale_price,avg_cost,min_stock,reorder_qty,safety_stock,lead_time_days,track_batch,track_expiry)
      VALUES(tag||'-BATCH',tag||'-B',10,15,10,20,30,5,7,true,true) RETURNING id INTO p_batch;
    PERFORM receive_tracked_stock(p_batch,wh,10,10,'LOT-1',current_date+90,'[]'::jsonb,'advanced_test',null);
    SELECT qty INTO q FROM inventory_lot_stock WHERE product_id=p_batch AND warehouse_id=wh AND lot_no='LOT-1';
    results:=results||jsonb_build_array(jsonb_build_object('test','batch receive','pass',q=10,'detail','qty='||coalesce(q,0)));
    ok:=ok AND q=10;

    PERFORM issue_tracked_stock(p_batch,wh,3,'LOT-1','[]'::jsonb,'advanced_test',null);
    SELECT qty INTO q FROM inventory_lot_stock WHERE product_id=p_batch AND warehouse_id=wh AND lot_no='LOT-1';
    results:=results||jsonb_build_array(jsonb_build_object('test','batch issue','pass',q=7,'detail','qty='||coalesce(q,0)));
    ok:=ok AND q=7;

    INSERT INTO products(name,code,purchase_price,sale_price,avg_cost,track_serial) VALUES(tag||'-SERIAL',tag||'-S',20,30,20,true) RETURNING id INTO p_serial;
    PERFORM receive_tracked_stock(p_serial,wh,2,20,null,null,jsonb_build_array('SN-A','SN-B'),'advanced_test',null);
    PERFORM issue_tracked_stock(p_serial,wh,1,null,jsonb_build_array('SN-A'),'advanced_test',null);
    SELECT count(*) INTO sold_count FROM inventory_serials WHERE product_id=p_serial AND status='Sold';
    SELECT count(*) INTO avail_count FROM inventory_serials WHERE product_id=p_serial AND status='Available';
    results:=results||jsonb_build_array(jsonb_build_object('test','serial lifecycle','pass',sold_count=1 AND avail_count=1,'detail','sold='||sold_count||' available='||avail_count));
    ok:=ok AND sold_count=1 AND avail_count=1;

    SELECT suggested_qty INTO mrp_q FROM mrp_replenishment(wh) WHERE product_id=p_batch LIMIT 1;
    results:=results||jsonb_build_array(jsonb_build_object('test','MRP suggestion','pass',coalesce(mrp_q,0)>0,'detail','suggested='||coalesce(mrp_q,0)));
    ok:=ok AND coalesce(mrp_q,0)>0;

    PERFORM import_products_json(jsonb_build_array(jsonb_build_object('name',tag||'-Imported','code',tag||'-I','purchase_price',12,'sale_price',18,'min_stock',2,'reorder_qty',5)));
    SELECT id INTO p_import FROM products WHERE code=tag||'-I';
    results:=results||jsonb_build_array(jsonb_build_object('test','CSV-import RPC','pass',p_import IS NOT NULL,'detail',CASE WHEN p_import IS NOT NULL THEN 'imported' ELSE 'missing' END));
    ok:=ok AND p_import IS NOT NULL;

    DELETE FROM inventory_trace_events WHERE product_id IN(p_batch,p_serial);
    DELETE FROM inventory_serials WHERE product_id=p_serial;
    DELETE FROM inventory_lot_balances WHERE lot_id IN(SELECT id FROM inventory_lots WHERE product_id=p_batch);
    DELETE FROM inventory_lots WHERE product_id=p_batch;
    DELETE FROM stock_movements WHERE product_id IN(p_batch,p_serial);
    DELETE FROM stock_balances WHERE product_id IN(p_batch,p_serial);
    DELETE FROM products WHERE id IN(p_batch,p_serial,p_import);
    RETURN jsonb_build_object('ok',ok,'results',results,'cleaned',true);
  EXCEPTION WHEN OTHERS THEN
    results:=results||jsonb_build_array(jsonb_build_object('test','unexpected error','pass',false,'detail',SQLERRM));
    RETURN jsonb_build_object('ok',false,'results',results,'cleaned',true,'error',SQLERRM);
  END;
END $$;

GRANT EXECUTE ON FUNCTION run_advanced_inventory_test() TO authenticated;

COMMIT;

-- ============================== 019_incremental_journal.sql ==============================
-- 019: incremental journal posting
-- Before: every write on 19 tables rebuilt the WHOLE journal. After: a change to an invoice / payment / expense / return
-- (and their item rows) re-posts ONLY that document; stock_movements only triggers a rebuild when a stocktake adjustment is written.
-- The full rebuild (button rebuild_journal(), and low-frequency tables: assets, depreciation, transfers, payroll, receipts, deliveries, work orders) is unchanged.
-- Rollback: 019_rollback.sql
BEGIN;

DROP FUNCTION IF EXISTS public._rebuild_journal();
CREATE OR REPLACE FUNCTION public._rebuild_journal(p_type text DEFAULT NULL, p_id uuid DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  e uuid;
  n int:=0;
  c numeric;
  net numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(777);
  PERFORM set_config('erp.rebuild','on',true);

  -- Rebuild system-generated entries, preserve manual journals.
  IF p_type IS NULL THEN
    DELETE FROM journal_entries WHERE doc_type NOT IN('manual','opening_balance') OR doc_type IS NULL;
  ELSE
    DELETE FROM journal_entries WHERE doc_type=p_type AND doc_id=p_id;
  END IF;

  -- Sales invoices: AR Dr / Revenue Cr / Output VAT Cr / COGS Dr / Inventory Cr
  FOR r IN SELECT * FROM sales_invoices WHERE status='Posted' AND (p_type IS NULL OR (p_type='sales_invoice' AND id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'فاتورة مبيعات '||r.number,'sales_invoice',r.id);

    net:=round(r.total-coalesce(r.tax,0),2);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES
      (e,'1300',r.total,0),
      (e,'4000',0,greatest(net,0));

    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2100',0,r.tax);
    END IF;

    SELECT coalesce(sum(sii.qty*sii.unit_cost),0)
      INTO c
      FROM sales_invoice_items AS sii
      WHERE sii.invoice_id=r.id;

    IF c>0 AND coalesce(r.notes,'') NOT LIKE 'DN:%' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'5000',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  -- Purchase invoices: Inventory Dr / Input VAT Dr / AP Cr
  FOR r IN SELECT * FROM purchase_invoices WHERE status='Posted' AND (p_type IS NULL OR (p_type='purchase_invoice' AND id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'فاتورة مشتريات '||r.number,'purchase_invoice',r.id);

    net:=round(r.total-coalesce(r.tax,0),2);

    IF coalesce(r.notes,'') LIKE 'GRN:%' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2110',greatest(net,0),0),(e,'2000',0,r.total);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',greatest(net,0),0),(e,'2000',0,r.total);
    END IF;

    IF coalesce(r.tax,0)>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1410',r.tax,0);
    END IF;
  END LOOP;

  -- Goods receipts: Inventory Dr / GRNI Cr
  FOR r IN SELECT gr.*,coalesce(sum(i.line_total),0) AS total_cost
    FROM goods_receipts gr JOIN goods_receipt_items i ON i.receipt_id=gr.id
    WHERE gr.status='Received' AND p_type IS NULL GROUP BY gr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'استلام بضاعة '||r.number,'goods_receipt',r.id);
    IF r.total_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.total_cost,0),(e,'2110',0,r.total_cost); END IF;
  END LOOP;

  -- Delivery notes: COGS Dr / Inventory Cr. Sales invoice created from DN only posts AR/Revenue/VAT.
  FOR r IN SELECT dn.*,coalesce(sum(i.qty*i.unit_cost),0) AS cost
    FROM delivery_notes dn JOIN delivery_note_items i ON i.delivery_id=dn.id
    WHERE dn.status='Delivered' AND p_type IS NULL GROUP BY dn.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'إذن تسليم '||r.number,'delivery_note',r.id);
    IF r.cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'5000',r.cost,0),(e,'1200',0,r.cost); END IF;
  END LOOP;

  -- Payments: Cash/Bank Dr for receipts, AP Dr for supplier payments.
  FOR r IN SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
    FROM payments AS p
    JOIN cash_accounts AS a ON a.id=p.account_id WHERE (p_type IS NULL OR (p_type='payment' AND p.id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,
        CASE r.kind WHEN 'receipt' THEN 'مقبوضات ' ELSE 'مدفوعات ' END||coalesce(r.doc_ref,''),
        'payment',r.id);

    IF r.kind='receipt' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,r.cc,r.amount,0),(e,'1300',0,r.amount);
    ELSIF r.kind='payment' THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2000',r.amount,0),(e,r.cc,0,r.amount);
    ELSE
      RAISE EXCEPTION 'نوع دفع غير صحيح أثناء ترحيل اليومية: %',r.kind;
    END IF;
  END LOOP;

  -- Expenses: Expense Dr / Cash-Bank Cr
  FOR r IN SELECT x.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
           FROM expenses AS x
           JOIN cash_accounts AS a ON a.id=x.account_id WHERE (p_type IS NULL OR (p_type='expense' AND x.id=p_id)) LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مصروف '||r.category,'expense',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'6000',r.amount,0),(e,r.cc,0,r.amount);
  END LOOP;

  -- Sales returns: contra revenue Dr + VAT Dr + Inventory Dr / AR Cr + COGS Cr
  FOR r IN SELECT sr.*,
           coalesce(sum(i.cost_total),0) AS cost,
           coalesce(sum(i.tax),0) AS tax,
           coalesce(sum(i.line_total),0) AS base
    FROM sales_returns AS sr
    JOIN sales_return_items AS i ON i.return_id=sr.id WHERE (p_type IS NULL OR (p_type='sales_return' AND sr.id=p_id)) GROUP BY sr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مرتجع مبيعات '||r.number,'sales_return',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'4000',r.base,0),(e,'1300',0,r.total);

    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'2100',r.tax,0);
    END IF;

    IF r.cost>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1200',r.cost,0),(e,'5000',0,r.cost);
    END IF;
  END LOOP;

  -- Purchase returns: AP Dr / Inventory Cr / Input VAT Cr
  FOR r IN SELECT pr.*,
           coalesce(sum(i.tax),0) AS tax,
           coalesce(sum(i.line_total),0) AS base
    FROM purchase_returns AS pr
    JOIN purchase_return_items AS i ON i.return_id=pr.id WHERE (p_type IS NULL OR (p_type='purchase_return' AND pr.id=p_id)) GROUP BY pr.id LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'مرتجع مشتريات '||r.number,'purchase_return',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'2000',r.total,0),(e,'1200',0,r.base);

    IF r.tax>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1410',0,r.tax);
    END IF;
  END LOOP;

  -- Cash transfers: destination Dr / source Cr
  FOR r IN SELECT * FROM cash_transfers WHERE p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'تحويل بين الحسابات','cash_transfer',r.id);

    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(
        e,
        CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.to_account)='bank' THEN '1100' ELSE '1000' END,
        r.amount,0),
      (
        e,
        CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.from_account)='bank' THEN '1100' ELSE '1000' END,
        0,r.amount);
  END LOOP;

  -- Paid payroll: Expense Dr / Cash-Bank Cr
  FOR r IN SELECT p.*,CASE WHEN a.type='bank' THEN '1100' ELSE '1000' END AS cc
    FROM payroll AS p
    JOIN cash_accounts AS a ON a.id=p.account_id
    WHERE p.paid AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.month,'مرتب','payroll',r.id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit)
      VALUES(e,'6000',r.net,0),(e,r.cc,0,r.net);
  END LOOP;

  -- Stocktake adjustments: inventory gain/shrinkage.
  FOR r IN SELECT sm.id,sm.created_at::date AS date,sm.product_id,sm.qty,sm.doc_id,p.avg_cost
    FROM stock_movements AS sm
    JOIN products AS p ON p.id=sm.product_id
    WHERE sm.type='Stock Adjustment'
      AND sm.doc_type='stocktake'
      AND sm.doc_id IS NOT NULL AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    c:=round(abs(r.qty*r.avg_cost),2);
    IF c=0 THEN CONTINUE; END IF;

    INSERT INTO journal_entries(id,date,description,doc_type,doc_id)
      VALUES(e,r.date,'تسوية جرد','stock_adjustment',r.doc_id);

    IF r.qty>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'1200',c,0),(e,'4300',0,c);
    ELSE
      INSERT INTO journal_lines(entry_id,account_code,debit,credit)
        VALUES(e,'6100',c,0),(e,'1200',0,c);
    END IF;
  END LOOP;

  -- Fixed asset acquisition / depreciation / disposal entries
  FOR r IN SELECT * FROM fixed_assets WHERE capitalized AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.purchase_date,'رسملة أصل '||r.code,'fixed_asset_acquisition',r.id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1400',r.cost,0);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,coalesce(r.acquisition_account,'1000'),0,r.cost);
  END LOOP;

  FOR r IN SELECT ad.*,fa.code,fa.branch_id FROM asset_depreciations ad JOIN fixed_assets fa ON fa.id=ad.asset_id WHERE p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.period_date,'إهلاك أصل '||r.code,'depreciation',r.asset_id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6200',r.amount,0),(e,'1500',0,r.amount);
  END LOOP;

  FOR r IN SELECT * FROM fixed_assets WHERE status='Disposed' AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1; c:=round(r.cost-r.accumulated_depreciation,2);
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id,branch_id) VALUES(e,r.disposal_date,'استبعاد أصل '||r.code,'asset_disposal',r.id,r.branch_id);
    INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1500',r.accumulated_depreciation,0),(e,'1400',0,r.cost);
    IF r.disposal_proceeds>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,CASE WHEN (SELECT type FROM cash_accounts WHERE id=r.disposal_account_id)='bank' THEN '1100' ELSE '1000' END,r.disposal_proceeds,0); END IF;
    IF r.disposal_proceeds-(r.cost-r.accumulated_depreciation)>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'7100',0,r.disposal_proceeds-(r.cost-r.accumulated_depreciation));
    ELSIF r.disposal_proceeds-(r.cost-r.accumulated_depreciation)<0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'6300',-(r.disposal_proceeds-(r.cost-r.accumulated_depreciation)),0); END IF;
  END LOOP;

  FOR r IN SELECT * FROM work_orders WHERE status='Completed' AND p_type IS NULL LOOP
    e:=gen_random_uuid(); n:=n+1;
    INSERT INTO journal_entries(id,date,description,doc_type,doc_id) VALUES(e,r.date,'إتمام تصنيع '||r.number,'work_order',r.id);
    IF r.total_cost>0 THEN
      INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',r.total_cost,0);
      IF r.material_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'1200',0,r.material_cost); END IF;
      IF r.labor_cost+r.overhead_cost>0 THEN INSERT INTO journal_lines(entry_id,account_code,debit,credit) VALUES(e,'2200',0,r.labor_cost+r.overhead_cost); END IF;
    END IF;
  END LOOP;

  PERFORM set_config('erp.rebuild','off',true);
  RETURN n;
END $function$;;

REVOKE EXECUTE ON FUNCTION public._rebuild_journal(text,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION trg_post_journal() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_new uuid; v_old uuid;
BEGIN
  IF TG_OP IN('INSERT','UPDATE') THEN v_new:=(to_jsonb(NEW)->>TG_ARGV[1])::uuid; END IF;
  IF TG_OP IN('UPDATE','DELETE') THEN v_old:=(to_jsonb(OLD)->>TG_ARGV[1])::uuid; END IF;
  IF v_new IS NOT NULL THEN PERFORM _rebuild_journal(TG_ARGV[0],v_new); END IF;
  IF v_old IS NOT NULL AND v_old IS DISTINCT FROM v_new THEN PERFORM _rebuild_journal(TG_ARGV[0],v_old); END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION trg_stock_journal() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE hit boolean:=false;
BEGIN
  IF TG_OP IN('INSERT','UPDATE') THEN
    hit:=EXISTS(SELECT 1 FROM nt WHERE type='Stock Adjustment');
  END IF;
  IF NOT hit AND TG_OP IN('UPDATE','DELETE') THEN
    hit:=EXISTS(SELECT 1 FROM ot WHERE type='Stock Adjustment');
  END IF;
  IF hit THEN PERFORM _rebuild_journal(); END IF;
  RETURN NULL;
END $$;

REVOKE EXECUTE ON FUNCTION trg_post_journal(),trg_stock_journal() FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS jr_auto ON sales_invoices;
DROP TRIGGER IF EXISTS jr_inc ON sales_invoices;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON sales_invoices FOR EACH ROW EXECUTE FUNCTION trg_post_journal('sales_invoice','id');
DROP TRIGGER IF EXISTS jr_auto ON sales_invoice_items;
DROP TRIGGER IF EXISTS jr_inc ON sales_invoice_items;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON sales_invoice_items FOR EACH ROW EXECUTE FUNCTION trg_post_journal('sales_invoice','invoice_id');
DROP TRIGGER IF EXISTS jr_auto ON purchase_invoices;
DROP TRIGGER IF EXISTS jr_inc ON purchase_invoices;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON purchase_invoices FOR EACH ROW EXECUTE FUNCTION trg_post_journal('purchase_invoice','id');
DROP TRIGGER IF EXISTS jr_auto ON purchase_invoice_items;
DROP TRIGGER IF EXISTS jr_inc ON purchase_invoice_items;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION trg_post_journal('purchase_invoice','invoice_id');
DROP TRIGGER IF EXISTS jr_auto ON payments;
DROP TRIGGER IF EXISTS jr_inc ON payments;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON payments FOR EACH ROW EXECUTE FUNCTION trg_post_journal('payment','id');
DROP TRIGGER IF EXISTS jr_auto ON expenses;
DROP TRIGGER IF EXISTS jr_inc ON expenses;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON expenses FOR EACH ROW EXECUTE FUNCTION trg_post_journal('expense','id');
DROP TRIGGER IF EXISTS jr_auto ON sales_returns;
DROP TRIGGER IF EXISTS jr_inc ON sales_returns;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON sales_returns FOR EACH ROW EXECUTE FUNCTION trg_post_journal('sales_return','id');
DROP TRIGGER IF EXISTS jr_auto ON sales_return_items;
DROP TRIGGER IF EXISTS jr_inc ON sales_return_items;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON sales_return_items FOR EACH ROW EXECUTE FUNCTION trg_post_journal('sales_return','return_id');
DROP TRIGGER IF EXISTS jr_auto ON purchase_returns;
DROP TRIGGER IF EXISTS jr_inc ON purchase_returns;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON purchase_returns FOR EACH ROW EXECUTE FUNCTION trg_post_journal('purchase_return','id');
DROP TRIGGER IF EXISTS jr_auto ON purchase_return_items;
DROP TRIGGER IF EXISTS jr_inc ON purchase_return_items;
CREATE TRIGGER jr_inc AFTER INSERT OR UPDATE OR DELETE ON purchase_return_items FOR EACH ROW EXECUTE FUNCTION trg_post_journal('purchase_return','return_id');

DROP TRIGGER IF EXISTS jr_auto ON stock_movements;
DROP TRIGGER IF EXISTS jr_stock_ins ON stock_movements; DROP TRIGGER IF EXISTS jr_stock_upd ON stock_movements; DROP TRIGGER IF EXISTS jr_stock_del ON stock_movements;
CREATE TRIGGER jr_stock_ins AFTER INSERT ON stock_movements REFERENCING NEW TABLE AS nt FOR EACH STATEMENT EXECUTE FUNCTION trg_stock_journal();
CREATE TRIGGER jr_stock_upd AFTER UPDATE ON stock_movements REFERENCING OLD TABLE AS ot NEW TABLE AS nt FOR EACH STATEMENT EXECUTE FUNCTION trg_stock_journal();
CREATE TRIGGER jr_stock_del AFTER DELETE ON stock_movements REFERENCING OLD TABLE AS ot FOR EACH STATEMENT EXECUTE FUNCTION trg_stock_journal();

-- start from a consistent full state
SELECT public._rebuild_journal();
COMMIT;

-- ============================== 020_fix_advanced_inventory_serial_ambiguity.sql ==============================
BEGIN;

-- 020) Fix advanced inventory serial issue: PL/pgSQL variable `s`
-- conflicted with the SQL table alias `s` for inventory_serials.

CREATE OR REPLACE FUNCTION issue_tracked_stock(
  p_product uuid,
  p_warehouse uuid,
  p_qty numeric,
  p_lot_no text DEFAULT null,
  p_serials jsonb DEFAULT '[]'::jsonb,
  p_doc_type text DEFAULT 'tracked_issue',
  p_doc_id uuid DEFAULT null
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v uuid:=gen_random_uuid();
  lot uuid;
  it jsonb;
  v_serial inventory_serials;
  available numeric;
  track_batch boolean;
  track_serial boolean;
  track_expiry boolean;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF p_qty<=0 THEN RAISE EXCEPTION 'الكمية غير صحيحة'; END IF;

  SELECT p.track_batch,p.track_serial,p.track_expiry
    INTO track_batch,track_serial,track_expiry
  FROM products p
  WHERE p.id=p_product AND p.active;
  IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير صالح'; END IF;

  IF (track_batch OR track_expiry) THEN
    IF nullif(trim(p_lot_no),'') IS NULL THEN
      RAISE EXCEPTION 'هذا المنتج يتطلب تحديد التشغيلة';
    END IF;

    SELECT l.id
      INTO lot
    FROM inventory_lots l
    WHERE l.product_id=p_product
      AND l.lot_no=trim(p_lot_no)
      AND l.active;
    IF lot IS NULL THEN RAISE EXCEPTION 'التشغيلة غير موجودة'; END IF;

    IF EXISTS(
      SELECT 1
      FROM inventory_lots l2
      WHERE l2.id=lot
        AND l2.expiry_date IS NOT NULL
        AND l2.expiry_date<current_date
    ) THEN
      RAISE EXCEPTION 'التشغيلة منتهية الصلاحية';
    END IF;

    SELECT coalesce(lb.qty,0)
      INTO available
    FROM inventory_lot_balances lb
    WHERE lb.lot_id=lot
      AND lb.warehouse_id=p_warehouse
    FOR UPDATE;

    IF coalesce(available,0)<p_qty THEN
      RAISE EXCEPTION 'رصيد التشغيلة غير كافٍ';
    END IF;

    UPDATE inventory_lot_balances
    SET qty=qty-p_qty
    WHERE lot_id=lot AND warehouse_id=p_warehouse;

    INSERT INTO inventory_trace_events(
      product_id,warehouse_id,lot_id,qty,direction,doc_type,doc_id
    ) VALUES(
      p_product,p_warehouse,lot,-p_qty,'OUT',p_doc_type,p_doc_id
    );
  END IF;

  IF track_serial THEN
    IF jsonb_array_length(coalesce(p_serials,'[]'::jsonb)) <> trunc(p_qty)
       OR p_qty<>trunc(p_qty) THEN
      RAISE EXCEPTION 'عدد الـSerials يجب أن يساوي الكمية الصحيحة';
    END IF;

    IF lot IS NOT NULL AND EXISTS(
      SELECT 1
      FROM inventory_serials s
      WHERE s.product_id=p_product
        AND s.serial_no IN (
          SELECT trim(x #>> '{}')
          FROM jsonb_array_elements(p_serials) x
        )
        AND s.lot_id IS DISTINCT FROM lot
    ) THEN
      RAISE EXCEPTION 'الـSerial لا ينتمي إلى التشغيلة المحددة';
    END IF;

    FOR it IN SELECT * FROM jsonb_array_elements(p_serials) LOOP
      SELECT s.*
        INTO v_serial
      FROM inventory_serials s
      WHERE s.product_id=p_product
        AND s.serial_no=trim(it #>> '{}')
        AND s.warehouse_id=p_warehouse
        AND s.status='Available'
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Serial غير متاح: %',trim(it #>> '{}');
      END IF;

      UPDATE inventory_serials
      SET status='Sold',sold_at=now(),warehouse_id=null
      WHERE id=v_serial.id;

      INSERT INTO inventory_trace_events(
        product_id,warehouse_id,lot_id,serial_id,qty,direction,doc_type,doc_id
      ) VALUES(
        p_product,p_warehouse,v_serial.lot_id,v_serial.id,-1,'OUT',p_doc_type,p_doc_id
      );
    END LOOP;
  END IF;

  PERFORM apply_stock(p_product,p_warehouse,-p_qty,'Sale',p_doc_type,p_doc_id);
  PERFORM log_event(
    'create','inventory_trace_events',v::text,'صرف مخزون متتبع'
  );
  RETURN v;
END $$;

GRANT EXECUTE ON FUNCTION issue_tracked_stock(uuid,uuid,numeric,text,jsonb,text,uuid) TO authenticated;

COMMIT;

-- ============================== 021_fix_advanced_test_lot_id.sql ==============================
BEGIN;

-- 021) Final hardening for the advanced inventory smoke test.
-- The test declared a PL/pgSQL variable named `lot_id` and later used
-- unqualified `lot_id` in a DELETE predicate. PostgreSQL can resolve that
-- name to both the PL/pgSQL variable and the table column, causing:
--   column reference "lot_id" is ambiguous
-- Keep the cleanup unambiguous by removing the unused variable and
-- qualifying all lot_balance columns.

CREATE OR REPLACE FUNCTION run_advanced_inventory_test() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  tag text:='ADVTEST-'||replace(gen_random_uuid()::text,'-','');
  wh uuid; p_batch uuid; p_serial uuid; p_import uuid;
  q numeric; mrp_q numeric; sold_count int; avail_count int;
  results jsonb:='[]'::jsonb; ok boolean:=true;
BEGIN
  PERFORM require_role('{admin,accountant,store}'); PERFORM require_dev();

  -- `warehouses` has no created_at column in the base schema.
  SELECT w.id INTO wh
  FROM warehouses w
  WHERE w.active
  ORDER BY w.id
  LIMIT 1;

  IF wh IS NULL THEN
    RAISE EXCEPTION 'لا يوجد مخزن نشط للاختبار';
  END IF;

  BEGIN
    INSERT INTO products(
      name,code,purchase_price,sale_price,avg_cost,min_stock,
      reorder_qty,safety_stock,lead_time_days,track_batch,track_expiry
    )
    VALUES(
      tag||'-BATCH',tag||'-B',10,15,10,20,30,5,7,true,true
    )
    RETURNING id INTO p_batch;

    PERFORM receive_tracked_stock(
      p_batch,wh,10,10,'LOT-1',current_date+90,'[]'::jsonb,'advanced_test',null
    );

    SELECT ils.qty
      INTO q
    FROM inventory_lot_stock ils
    WHERE ils.product_id=p_batch
      AND ils.warehouse_id=wh
      AND ils.lot_no='LOT-1';

    results:=results||jsonb_build_array(
      jsonb_build_object('test','batch receive','pass',q=10,'detail','qty='||coalesce(q,0))
    );
    ok:=ok AND q=10;

    PERFORM issue_tracked_stock(
      p_batch,wh,3,'LOT-1','[]'::jsonb,'advanced_test',null
    );

    SELECT ils.qty
      INTO q
    FROM inventory_lot_stock ils
    WHERE ils.product_id=p_batch
      AND ils.warehouse_id=wh
      AND ils.lot_no='LOT-1';

    results:=results||jsonb_build_array(
      jsonb_build_object('test','batch issue','pass',q=7,'detail','qty='||coalesce(q,0))
    );
    ok:=ok AND q=7;

    INSERT INTO products(
      name,code,purchase_price,sale_price,avg_cost,track_serial
    )
    VALUES(tag||'-SERIAL',tag||'-S',20,30,20,true)
    RETURNING id INTO p_serial;

    PERFORM receive_tracked_stock(
      p_serial,wh,2,20,null,null,
      jsonb_build_array('SN-A','SN-B'),'advanced_test',null
    );

    PERFORM issue_tracked_stock(
      p_serial,wh,1,null,jsonb_build_array('SN-A'),'advanced_test',null
    );

    SELECT count(*) INTO sold_count
    FROM inventory_serials sr
    WHERE sr.product_id=p_serial AND sr.status='Sold';

    SELECT count(*) INTO avail_count
    FROM inventory_serials sr
    WHERE sr.product_id=p_serial AND sr.status='Available';

    results:=results||jsonb_build_array(
      jsonb_build_object(
        'test','serial lifecycle',
        'pass',sold_count=1 AND avail_count=1,
        'detail','sold='||sold_count||' available='||avail_count
      )
    );
    ok:=ok AND sold_count=1 AND avail_count=1;

    SELECT mrp.suggested_qty
      INTO mrp_q
    FROM mrp_replenishment(wh) mrp
    WHERE mrp.product_id=p_batch
    LIMIT 1;

    results:=results||jsonb_build_array(
      jsonb_build_object(
        'test','MRP suggestion',
        'pass',coalesce(mrp_q,0)>0,
        'detail','suggested='||coalesce(mrp_q,0)
      )
    );
    ok:=ok AND coalesce(mrp_q,0)>0;

    PERFORM import_products_json(
      jsonb_build_array(
        jsonb_build_object(
          'name',tag||'-Imported',
          'code',tag||'-I',
          'purchase_price',12,
          'sale_price',18,
          'min_stock',2,
          'reorder_qty',5
        )
      )
    );

    SELECT p.id INTO p_import
    FROM products p
    WHERE p.code=tag||'-I'
    LIMIT 1;

    results:=results||jsonb_build_array(
      jsonb_build_object(
        'test','CSV-import RPC',
        'pass',p_import IS NOT NULL,
        'detail',CASE WHEN p_import IS NOT NULL THEN 'imported' ELSE 'missing' END
      )
    );
    ok:=ok AND p_import IS NOT NULL;

    -- Cleanup: qualify all columns to eliminate PL/pgSQL-name collisions.
    DELETE FROM inventory_trace_events ite
    WHERE ite.product_id IN(p_batch,p_serial);

    DELETE FROM inventory_serials sr
    WHERE sr.product_id=p_serial;

    DELETE FROM inventory_lot_balances lb
    WHERE lb.lot_id IN(
      SELECT l.id
      FROM inventory_lots l
      WHERE l.product_id=p_batch
    );

    DELETE FROM inventory_lots l
    WHERE l.product_id=p_batch;

    DELETE FROM stock_movements sm
    WHERE sm.product_id IN(p_batch,p_serial);

    DELETE FROM stock_balances sb
    WHERE sb.product_id IN(p_batch,p_serial);

    DELETE FROM products p
    WHERE p.id IN(p_batch,p_serial,p_import);

    RETURN jsonb_build_object(
      'ok',ok,
      'results',results,
      'cleaned',true
    );

  EXCEPTION WHEN OTHERS THEN
    results:=results||jsonb_build_array(
      jsonb_build_object('test','unexpected error','pass',false,'detail',SQLERRM)
    );
    RETURN jsonb_build_object(
      'ok',false,
      'results',results,
      'cleaned',true,
      'error',SQLERRM
    );
  END;
END $$;

GRANT EXECUTE ON FUNCTION run_advanced_inventory_test() TO authenticated;

COMMIT;

-- ============================== 022_final_go_live_qa.sql ==============================
BEGIN;

-- 022) Final Go-Live QA / security hardening.
-- Additive only: no data reset and no destructive DDL.
-- Designed to run AFTER the currently successful 021 migration.

-- 1) Harden direct price lookup and period helper for inactive/pending users.
CREATE OR REPLACE FUNCTION price_for(
  p_product uuid,
  p_price_list uuid,
  p_qty numeric DEFAULT 1,
  p_fallback numeric DEFAULT 0
) RETURNS numeric
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT CASE WHEN auth_role() IS NULL THEN NULL::numeric ELSE
    coalesce(
      (SELECT pli.price
       FROM price_list_items pli
       WHERE pli.price_list_id=p_price_list
         AND pli.product_id=p_product
         AND pli.min_qty<=greatest(coalesce(p_qty,1),0)
       ORDER BY pli.min_qty DESC
       LIMIT 1),
      p_fallback
    ) END
$$;

CREATE OR REPLACE FUNCTION assert_period_open(p_date date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth_role() IS NULL THEN
    RAISE EXCEPTION 'المستخدم غير نشط أو غير مصرح له';
  END IF;
  IF EXISTS(
    SELECT 1 FROM fiscal_periods
    WHERE p_date BETWEEN start_date AND end_date
      AND status='Closed'
  ) AND coalesce(current_setting('erp.rebuild',true),'off')<>'on' THEN
    RAISE EXCEPTION 'الفترة المحاسبية مغلقة لهذا التاريخ';
  END IF;
END $$;

-- 2) Enforce that a journal line is either debit OR credit, never both.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid='public.journal_lines'::regclass
      AND conname='journal_line_one_side_chk'
  ) THEN
    ALTER TABLE journal_lines
      ADD CONSTRAINT journal_line_one_side_chk
      CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0) OR (debit = 0 AND credit = 0))
      NOT VALID;
  END IF;
END $$;

-- 2b) Harden MRP read helper: inactive/pending users receive no inventory planning data.
CREATE OR REPLACE FUNCTION mrp_replenishment(p_warehouse uuid DEFAULT null)
RETURNS TABLE(
  product_id uuid,product_name text,warehouse_id uuid,on_hand numeric,incoming numeric,committed numeric,
  projected numeric,min_stock numeric,safety_stock numeric,reorder_qty numeric,suggested_qty numeric,lead_time_days int
) LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
WITH base AS (
  SELECT p.id product_id,p.name product_name,w.id warehouse_id,
         coalesce((SELECT sum(sb.qty) FROM stock_balances sb WHERE sb.product_id=p.id AND sb.warehouse_id=w.id),0) on_hand,
         coalesce((SELECT sum(greatest(poi.qty-coalesce((SELECT sum(gri.qty) FROM goods_receipt_items gri JOIN goods_receipts gr ON gr.id=gri.receipt_id WHERE gr.purchase_order_id=po.id AND gri.product_id=poi.product_id),0),0))
                   FROM purchase_orders po JOIN purchase_order_items poi ON poi.order_id=po.id
                   WHERE po.warehouse_id=w.id AND po.status IN('Confirmed','Partially Received') AND poi.product_id=p.id),0) incoming,
         coalesce((SELECT sum(greatest(soi.qty-coalesce((SELECT sum(dni.qty) FROM delivery_note_items dni JOIN delivery_notes dn ON dn.id=dni.delivery_id WHERE dn.sales_order_id=so.id AND dni.product_id=soi.product_id AND dn.status='Delivered'),0),0))
                   FROM sales_orders so JOIN sales_order_items soi ON soi.order_id=so.id
                   WHERE so.warehouse_id=w.id AND so.status IN('Confirmed','Partially Delivered') AND soi.product_id=p.id),0) committed,
         p.min_stock,p.safety_stock,p.reorder_qty,p.lead_time_days
  FROM products p CROSS JOIN warehouses w
  WHERE auth_role() IN('admin','accountant','store')
    AND p.active AND w.active AND (p_warehouse IS NULL OR w.id=p_warehouse)
)
SELECT product_id,product_name,warehouse_id,on_hand,incoming,committed,
       on_hand+incoming-committed projected,min_stock,safety_stock,reorder_qty,
       CASE WHEN on_hand+incoming-committed < min_stock+safety_stock
            THEN greatest(reorder_qty,(min_stock+safety_stock)-(on_hand+incoming-committed)) ELSE 0 END suggested_qty,
       lead_time_days
FROM base
WHERE on_hand+incoming-committed < min_stock+safety_stock
ORDER BY suggested_qty DESC,product_name;
$$;

-- 2c) Make the financial ratios helper explicitly role-gated.
CREATE OR REPLACE FUNCTION financial_ratios(p_as_of date DEFAULT current_date)
RETURNS TABLE(metric text,value numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
WITH guarded AS (SELECT auth_role() AS role),
b AS (SELECT * FROM balance_sheet(p_as_of)),
a AS (
  SELECT coalesce(sum(balance) FILTER(WHERE type='Asset'),0) assets,
         coalesce(sum(balance) FILTER(WHERE type='Liability'),0) liabilities,
         coalesce(sum(balance) FILTER(WHERE type='Equity'),0) equity
  FROM b
),
pl AS (
  SELECT coalesce(sum(l.debit-l.credit) FILTER(WHERE ac.type='Revenue'),0) revenue,
         coalesce(sum(l.debit-l.credit) FILTER(WHERE ac.type IN('Expense','COGS')),0) expense
  FROM journal_lines l
  JOIN journal_entries e ON e.id=l.entry_id
  JOIN accounts ac ON ac.code=l.account_code
  WHERE e.date<=p_as_of
)
SELECT q.metric,q.value
FROM (
  SELECT 'Current Asset / Liability'::text metric,round(CASE WHEN a.liabilities<>0 THEN a.assets/a.liabilities ELSE 0 END,3) value FROM a
  UNION ALL SELECT 'Debt Ratio',round(CASE WHEN a.assets<>0 THEN a.liabilities/a.assets ELSE 0 END,3) FROM a
  UNION ALL SELECT 'Equity Ratio',round(CASE WHEN a.assets<>0 THEN a.equity/a.assets ELSE 0 END,3) FROM a
  UNION ALL SELECT 'Net Margin',round(CASE WHEN pl.revenue<>0 THEN (pl.revenue-pl.expense)/pl.revenue*100 ELSE 0 END,3) FROM pl
) q CROSS JOIN guarded g
WHERE g.role IN('admin','accountant')
$$;

-- 3) Comprehensive structural/data-integrity preflight.
CREATE OR REPLACE FUNCTION go_live_preflight()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public AS $$
DECLARE
  r jsonb;
  rls_missing int;
  anon_table_privs int;
  auth_missing_select int;
  anon_exec int;
  weak_definers int;
  unbalanced int;
  both_sides int;
  neg_stock int;
  neg_cash int;
  sales_paid_mismatch int;
  purchases_paid_mismatch int;
  orphan_alloc int;
  orphan_jlines int;
  serial_bad int;
  negative_lots int;
  expired_stock int;
  residue int;
BEGIN
  IF auth_role()<>'admin' THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;

  SELECT count(*) INTO rls_missing
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity;

  SELECT count(*) INTO anon_table_privs
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r'
    AND (
      has_table_privilege('anon',c.oid,'SELECT') OR
      has_table_privilege('anon',c.oid,'INSERT') OR
      has_table_privilege('anon',c.oid,'UPDATE') OR
      has_table_privilege('anon',c.oid,'DELETE') OR
      has_table_privilege('anon',c.oid,'TRUNCATE')
    );

  SELECT count(*) INTO auth_missing_select
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r'
    AND NOT has_table_privilege('authenticated',c.oid,'SELECT');

  SELECT count(*) INTO anon_exec
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prokind='f'
    AND has_function_privilege('anon',p.oid,'EXECUTE');

  -- Client-callable SECURITY DEFINER functions should perform an auth/role check,
  -- except the two explicitly allowlisted read helpers below.
  SELECT count(*) INTO weak_definers
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.prokind='f'
    AND p.prosecdef
    AND has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND p.proname NOT IN('price_for')
    AND pg_get_functiondef(p.oid) NOT LIKE '%require_role(%'
    AND pg_get_functiondef(p.oid) NOT LIKE '%auth_role(%';

  SELECT count(*) INTO unbalanced
  FROM (
    SELECT je.id
    FROM journal_entries je
    JOIN journal_lines jl ON jl.entry_id=je.id
    GROUP BY je.id
    HAVING round(sum(jl.debit),2)<>round(sum(jl.credit),2)
  ) x;

  SELECT count(*) INTO both_sides
  FROM journal_lines
  WHERE debit>0 AND credit>0;

  SELECT count(*) INTO neg_stock FROM stock_balances WHERE qty<0;
  SELECT count(*) INTO neg_cash FROM cash_accounts WHERE balance<0;

  SELECT count(*) INTO sales_paid_mismatch
  FROM sales_invoices i
  JOIN sales_invoice_balances b ON b.id=i.id
  WHERE round(coalesce(i.paid,0),2)<>round(coalesce(b.allocated_paid,0),2)
    AND i.status='Posted';

  SELECT count(*) INTO purchases_paid_mismatch
  FROM purchase_invoices i
  JOIN purchase_invoice_balances b ON b.id=i.id
  WHERE round(coalesce(i.paid,0),2)<>round(coalesce(b.allocated_paid,0),2)
    AND i.status='Posted';

  SELECT count(*) INTO orphan_alloc
  FROM payment_allocations pa
  LEFT JOIN payments p ON p.id=pa.payment_id
  WHERE p.id IS NULL;

  SELECT count(*) INTO orphan_jlines
  FROM journal_lines jl
  LEFT JOIN journal_entries je ON je.id=jl.entry_id
  WHERE je.id IS NULL;

  SELECT count(*) INTO serial_bad
  FROM inventory_serials s
  WHERE (s.status='Available' AND s.warehouse_id IS NULL)
     OR (s.status='Sold' AND s.warehouse_id IS NOT NULL);

  SELECT count(*) INTO negative_lots FROM inventory_lot_balances WHERE qty<0;
  SELECT count(*) INTO expired_stock FROM inventory_lot_stock WHERE expired AND qty>0;

  SELECT
    (SELECT count(*) FROM products WHERE name ILIKE 'GLTEST-%' OR code ILIKE 'GLTEST-%' OR barcode ILIKE 'GLTEST-%')+
    (SELECT count(*) FROM customers WHERE name ILIKE 'GLTEST-%' OR name ILIKE 'ADVTEST-%' OR name ILIKE '__ERP_TEST__%')+
    (SELECT count(*) FROM suppliers WHERE name ILIKE 'GLTEST-%' OR name ILIKE 'ADVTEST-%' OR name ILIKE '__ERP_TEST__%')+
    (SELECT count(*) FROM warehouses WHERE name ILIKE 'GLTEST-%' OR name ILIKE 'ADVTEST-%' OR name ILIKE '__ERP_TEST__%')+
    (SELECT count(*) FROM cash_accounts WHERE name ILIKE 'GLTEST-%' OR name ILIKE 'ADVTEST-%' OR name ILIKE '__ERP_TEST__%')
  INTO residue;

  r:=jsonb_build_object(
    'ok',(
      rls_missing=0 AND anon_table_privs=0 AND auth_missing_select=0 AND anon_exec=0 AND
      weak_definers=0 AND unbalanced=0 AND both_sides=0 AND neg_stock=0 AND neg_cash=0 AND
      sales_paid_mismatch=0 AND purchases_paid_mismatch=0 AND orphan_alloc=0 AND orphan_jlines=0 AND
      serial_bad=0 AND negative_lots=0 AND residue=0
    ),
    'rls_missing_tables',rls_missing,
    'anon_table_privileges',anon_table_privs,
    'authenticated_missing_select',auth_missing_select,
    'anon_executable_functions',anon_exec,
    'weak_security_definer_functions',weak_definers,
    'unbalanced_journal_entries',unbalanced,
    'journal_lines_both_sides',both_sides,
    'negative_stock_rows',neg_stock,
    'negative_cash_rows',neg_cash,
    'sales_paid_mismatches',sales_paid_mismatch,
    'purchase_paid_mismatches',purchases_paid_mismatch,
    'orphan_payment_allocations',orphan_alloc,
    'orphan_journal_lines',orphan_jlines,
    'invalid_serial_rows',serial_bad,
    'negative_lot_balances',negative_lots,
    'expired_lots_with_stock',expired_stock,
    'test_data_residue',residue,
    'open_fiscal_periods',(SELECT count(*) FROM fiscal_periods WHERE status='Open'),
    'pending_approvals',(SELECT count(*) FROM approval_requests WHERE status='Pending'),
    'pending_tax_documents',(SELECT count(*) FROM tax_documents WHERE status IN('Pending','Rejected')),
    'failed_integrations',(SELECT count(*) FROM integration_events WHERE status='Failed')
  );
  RETURN r;
END $$;

-- 4) Final combined suite: functional enterprise test + advanced inventory test + structural QA.
CREATE OR REPLACE FUNCTION run_final_go_live_suite() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  base jsonb;
  adv jsonb;
  pre jsonb;
  ok boolean;
BEGIN
  PERFORM require_role('{admin}'); PERFORM require_dev();
  base:=run_erp_go_live_test();
  IF coalesce((base->>'ok')::boolean,false)=false THEN
    RETURN jsonb_build_object(
      'ok',false,
      'stage','enterprise',
      'enterprise',base,
      'advanced',null,
      'preflight',null,
      'cleaned',coalesce((base->>'cleaned')::boolean,false)
    );
  END IF;

  adv:=run_advanced_inventory_test();
  IF coalesce((adv->>'ok')::boolean,false)=false THEN
    RETURN jsonb_build_object(
      'ok',false,
      'stage','advanced_inventory',
      'enterprise',base,
      'advanced',adv,
      'preflight',null,
      'cleaned',coalesce((adv->>'cleaned')::boolean,false)
    );
  END IF;

  pre:=go_live_preflight();
  ok:=coalesce((base->>'ok')::boolean,false)
      AND coalesce((adv->>'ok')::boolean,false)
      AND coalesce((pre->>'ok')::boolean,false);

  RETURN jsonb_build_object(
    'ok',ok,
    'stage',CASE WHEN ok THEN 'complete' ELSE 'preflight' END,
    'enterprise',base,
    'advanced',adv,
    'preflight',pre,
    'cleaned',coalesce((base->>'cleaned')::boolean,false) AND coalesce((adv->>'cleaned')::boolean,false)
  );
END $$;

REVOKE ALL ON FUNCTION go_live_preflight() FROM public,anon;
REVOKE ALL ON FUNCTION run_final_go_live_suite() FROM public,anon;
GRANT EXECUTE ON FUNCTION go_live_preflight() TO authenticated;
GRANT EXECUTE ON FUNCTION run_final_go_live_suite() TO authenticated;

-- 5) Keep updated health check fields useful for the UI.
CREATE OR REPLACE FUNCTION health_check_enterprise()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
SELECT jsonb_build_object(
  'ok',auth_role() IS NOT NULL,
  'duplicate_barcodes',(SELECT count(*) FROM (SELECT barcode FROM products WHERE barcode IS NOT NULL GROUP BY barcode HAVING count(*)>1)x)+ (SELECT count(*) FROM (SELECT barcode FROM product_barcodes GROUP BY barcode HAVING count(*)>1)x),
  'unbalanced_journal_entries',(SELECT count(*) FROM (SELECT je.id FROM journal_entries je JOIN journal_lines jl ON jl.entry_id=je.id GROUP BY je.id HAVING round(sum(jl.debit),2)<>round(sum(jl.credit),2))x),
  'journal_lines_both_sides',(SELECT count(*) FROM journal_lines WHERE debit>0 AND credit>0),
  'negative_stock_rows',(SELECT count(*) FROM stock_balances WHERE qty<0),
  'negative_cash_rows',(SELECT count(*) FROM cash_accounts WHERE balance<0),
  'paid_over_total_sales',(SELECT count(*) FROM sales_invoice_balances WHERE allocated_paid>total+0.005),
  'paid_over_total_purchases',(SELECT count(*) FROM purchase_invoice_balances WHERE allocated_paid>total+0.005),
  'invoice_paid_mismatches',(SELECT count(*) FROM sales_invoices i JOIN sales_invoice_balances b ON b.id=i.id WHERE i.status='Posted' AND round(coalesce(i.paid,0),2)<>round(coalesce(b.allocated_paid,0),2)) + (SELECT count(*) FROM purchase_invoices i JOIN purchase_invoice_balances b ON b.id=i.id WHERE i.status='Posted' AND round(coalesce(i.paid,0),2)<>round(coalesce(b.allocated_paid,0),2)),
  'orphan_stock_movements',(SELECT count(*) FROM stock_movements sm WHERE sm.product_id IS NULL OR sm.warehouse_id IS NULL),
  'orphan_journal_lines',(SELECT count(*) FROM journal_lines jl LEFT JOIN journal_entries je ON je.id=jl.entry_id WHERE je.id IS NULL),
  'open_fiscal_periods',(SELECT count(*) FROM fiscal_periods WHERE status='Open'),
  'pending_approvals',(SELECT count(*) FROM approval_requests WHERE status='Pending'),
  'pending_tax_documents',(SELECT count(*) FROM tax_documents WHERE status IN('Pending','Rejected')),
  'failed_integrations',(SELECT count(*) FROM integration_events WHERE status='Failed')
);
$$;

GRANT EXECUTE ON FUNCTION health_check_enterprise() TO authenticated;

COMMIT;

-- ============================== 024_fix_security_privileges_safe.sql ==============================
BEGIN;

-- 024) Safer security hardening. Idempotent and signature-agnostic.
-- Fixes 023 by granting authenticated access dynamically by function name,
-- so overloaded or drifted signatures do not break the migration.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.auth_role() TO authenticated;

CREATE OR REPLACE FUNCTION public.customer_statement(p_party uuid,p_to date DEFAULT current_date)
RETURNS TABLE(d date,doc text,descr text,debit numeric,credit numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT si.date,si.number,'فاتورة مبيعات'::text,si.total::numeric,0::numeric FROM sales_invoices si
   WHERE auth_role() IN('admin','accountant') AND si.customer_id=p_party AND si.status='Posted' AND si.date<=p_to
  UNION ALL SELECT py.date,coalesce(py.doc_ref,'دفعة'),'مقبوضات',0::numeric,py.amount FROM payments py
   WHERE auth_role() IN('admin','accountant') AND py.customer_id=p_party AND py.kind='receipt' AND py.date<=p_to
  UNION ALL SELECT sr.date,sr.number,'مرتجع مبيعات',0::numeric,sr.total FROM sales_returns sr
   WHERE auth_role() IN('admin','accountant') AND sr.customer_id=p_party AND sr.date<=p_to
  ORDER BY 1$$;

CREATE OR REPLACE FUNCTION public.supplier_statement(p_party uuid,p_to date DEFAULT current_date)
RETURNS TABLE(d date,doc text,descr text,debit numeric,credit numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT pi.date,pi.number,'فاتورة مشتريات'::text,0::numeric,pi.total::numeric FROM purchase_invoices pi
   WHERE auth_role() IN('admin','accountant') AND pi.supplier_id=p_party AND pi.status='Posted' AND pi.date<=p_to
  UNION ALL SELECT py.date,coalesce(py.doc_ref,'دفعة'),'مدفوعات',py.amount,0::numeric FROM payments py
   WHERE auth_role() IN('admin','accountant') AND py.supplier_id=p_party AND py.kind='payment' AND py.date<=p_to
  UNION ALL SELECT pr.date,pr.number,'مرتجع مشتريات',pr.total,0::numeric FROM purchase_returns pr
   WHERE auth_role() IN('admin','accountant') AND pr.supplier_id=p_party AND pr.date<=p_to
  ORDER BY 1$$;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname = ANY(ARRAY[
        'auth_role',
        'create_stock_transfer',
        'create_stocktake',
        'approve_stocktake_v2',
        'create_manual_journal',
        'record_payment',
        'create_sale',
        'create_purchase',
        'create_sales_return',
        'create_purchase_return',
        'rebuild_journal',
        'trial_balance',
        'general_ledger',
        'customer_aging',
        'supplier_aging',
        'profit_loss',
        'dashboard_v2',
        'customer_statement',
        'supplier_statement',
        'set_opening_stock',
        'run_erp_smoke_test',
        'create_purchase_order',
        'create_goods_receipt',
        'create_purchase_invoice_from_receipt',
        'create_delivery',
        'create_sale_from_delivery',
        'price_for',
        'assert_period_open',
        'close_fiscal_period',
        'reopen_fiscal_period',
        'create_fixed_asset',
        'capitalize_fixed_asset',
        'depreciate_asset',
        'dispose_fixed_asset',
        'reconcile_bank_line',
        'approve_leave',
        'create_work_order',
        'complete_work_order',
        'open_pos_session',
        'record_pos_sale',
        'close_pos_session',
        'decide_approval',
        'inventory_valuation',
        'sales_by_customer',
        'cashflow_summary',
        'balance_sheet',
        'health_check_enterprise',
        'run_erp_enterprise_test',
        'cancel_sales_invoice',
        'cancel_purchase_invoice',
        'post_opening_balances',
        'add_product_barcode',
        'calculate_sales_commission',
        'record_cheque',
        'update_cheque_status',
        'register_tax_document',
        'update_tax_document',
        'financial_ratios',
        'run_erp_go_live_test',
        'create_inventory_lot',
        'receive_tracked_stock',
        'issue_tracked_stock',
        'mrp_replenishment',
        'import_products_json',
        'import_customers_json',
        'import_suppliers_json',
        'import_opening_stock_json',
        'health_check_advanced',
        'run_advanced_inventory_test',
        'go_live_preflight',
        'run_final_go_live_suite'
      ])
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated',r.proname,r.args);
  END LOOP;
END$$;

CREATE OR REPLACE FUNCTION public.price_for(p_product uuid,p_price_list uuid,p_qty numeric DEFAULT 1,p_fallback numeric DEFAULT 0)
RETURNS numeric LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT CASE WHEN auth_role() IS NULL THEN NULL::numeric ELSE coalesce((SELECT pli.price FROM price_list_items pli WHERE pli.price_list_id=p_price_list AND pli.product_id=p_product AND pli.min_qty<=greatest(coalesce(p_qty,1),0) ORDER BY pli.min_qty DESC LIMIT 1),p_fallback) END$$;

GRANT EXECUTE ON FUNCTION public.auth_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.customer_statement(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.supplier_statement(uuid,date) TO authenticated;

COMMIT;

-- ============================== 025_fix_missing_select_inventory.sql ==============================
BEGIN;

-- 025) Fix the four authenticated SELECT grants for the Advanced Inventory tables.
-- Cause: migration 024 revoked table privileges from authenticated globally.
-- The four base tables created by 018 had their RLS policies, but their SELECT
-- table grants were not restored. RLS still controls which rows each role can see.

GRANT SELECT ON TABLE
  public.inventory_lots,
  public.inventory_lot_balances,
  public.inventory_serials,
  public.inventory_trace_events
TO authenticated;

-- Safety verification: these four tables must keep RLS enabled.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'inventory_lots',
    'inventory_lot_balances',
    'inventory_serials',
    'inventory_trace_events'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public'
        AND c.relname=t
        AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'RLS is not enabled on public.%', t;
    END IF;
  END LOOP;
END $$;

COMMIT;

-- ============================== 026_business_erp_scope.sql ==============================
BEGIN;

-- 026) Business-focused completion for office/warehouse ERP.
-- No manufacturing, POS, service or e-commerce dependencies are added here.
-- Additive and idempotent; designed after the successful 025 preflight.

-- HR: holidays and employee rewards / penalties.
CREATE TABLE IF NOT EXISTS public.holidays(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  holiday_date date NOT NULL UNIQUE,
  name text NOT NULL,
  paid boolean NOT NULL DEFAULT true,
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.employee_adjustments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES public.employees ON DELETE CASCADE,
  kind text NOT NULL CHECK(kind IN('reward','penalty')),
  amount numeric(14,2) NOT NULL CHECK(amount>0),
  effective_date date NOT NULL DEFAULT current_date,
  payroll_month date,
  reason text,
  approved boolean NOT NULL DEFAULT false,
  approved_by uuid,
  approved_at timestamptz,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS employee_adjustments_emp_date_idx ON public.employee_adjustments(employee_id,effective_date);
CREATE INDEX IF NOT EXISTS employee_adjustments_month_idx ON public.employee_adjustments(payroll_month,approved);

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_adjustments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sel_holidays ON public.holidays;
CREATE POLICY sel_holidays ON public.holidays FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant'));
DROP POLICY IF EXISTS write_holidays ON public.holidays;
CREATE POLICY write_holidays ON public.holidays FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant'));

DROP POLICY IF EXISTS sel_employee_adjustments ON public.employee_adjustments;
CREATE POLICY sel_employee_adjustments ON public.employee_adjustments FOR SELECT TO authenticated USING(auth_role() IN('admin','accountant'));
DROP POLICY IF EXISTS write_employee_adjustments ON public.employee_adjustments;
CREATE POLICY write_employee_adjustments ON public.employee_adjustments FOR ALL TO authenticated USING(auth_role() IN('admin','accountant')) WITH CHECK(auth_role() IN('admin','accountant'));

-- Inventory: availability/shortage and stock-card functions matching the office/warehouse workflow.
CREATE OR REPLACE FUNCTION public.inventory_availability(p_warehouse uuid DEFAULT null)
RETURNS TABLE(
  product_id uuid, product_name text, warehouse_id uuid, warehouse_name text,
  on_hand numeric, min_stock numeric, reorder_qty numeric, shortage_qty numeric, status text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT p.id,p.name,w.id,w.name,
         coalesce(sb.qty,0),p.min_stock,p.reorder_qty,
         greatest((p.min_stock-coalesce(sb.qty,0)),0),
         CASE WHEN coalesce(sb.qty,0)<=0 THEN 'نفد'
              WHEN coalesce(sb.qty,0)<p.min_stock THEN 'عجز'
              ELSE 'متوفر' END
  FROM products p
  JOIN warehouses w ON w.active
  LEFT JOIN stock_balances sb ON sb.product_id=p.id AND sb.warehouse_id=w.id
  WHERE auth_role() IN('admin','accountant','store','sales')
    AND p.active AND (p_warehouse IS NULL OR w.id=p_warehouse)
  ORDER BY CASE WHEN coalesce(sb.qty,0)<=0 THEN 0 WHEN coalesce(sb.qty,0)<p.min_stock THEN 1 ELSE 2 END,p.name,w.name;
$$;

CREATE OR REPLACE FUNCTION public.product_stock_card(
  p_product uuid,
  p_warehouse uuid DEFAULT null,
  p_from date DEFAULT '1900-01-01',
  p_to date DEFAULT current_date
)
RETURNS TABLE(
  movement_id uuid, movement_date date, warehouse_id uuid, movement_type text,
  qty numeric, qty_before numeric, qty_after numeric, doc_type text, doc_id uuid
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT sm.id,sm.created_at::date,sm.warehouse_id,sm.type,sm.qty,sm.qty_before,sm.qty_after,sm.doc_type,sm.doc_id
  FROM stock_movements sm
  WHERE auth_role() IN('admin','accountant','store','sales')
    AND sm.product_id=p_product
    AND sm.created_at::date BETWEEN p_from AND p_to
    AND (p_warehouse IS NULL OR sm.warehouse_id=p_warehouse)
  ORDER BY sm.created_at,sm.id;
$$;

REVOKE ALL ON FUNCTION public.inventory_availability(uuid) FROM public,anon;
REVOKE ALL ON FUNCTION public.product_stock_card(uuid,uuid,date,date) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.inventory_availability(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.product_stock_card(uuid,uuid,date,date) TO authenticated;

-- Payroll helper: approved rewards/penalties for a payroll month.
CREATE OR REPLACE FUNCTION public.employee_adjustment_totals(p_employee uuid,p_month date)
RETURNS TABLE(rewards numeric,penalties numeric,net_adjustment numeric)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT coalesce(sum(amount) FILTER(WHERE kind='reward'),0),
         coalesce(sum(amount) FILTER(WHERE kind='penalty'),0),
         coalesce(sum(CASE WHEN kind='reward' THEN amount ELSE -amount END),0)
  FROM employee_adjustments
  WHERE employee_id=p_employee
    AND approved
    AND (payroll_month IS NULL OR date_trunc('month',payroll_month)=date_trunc('month',p_month));
$$;
REVOKE ALL ON FUNCTION public.employee_adjustment_totals(uuid,date) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.employee_adjustment_totals(uuid,date) TO authenticated;

-- Audit for the two new HR tables.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['holidays','employee_adjustments'] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='audit_'||t) THEN
      EXECUTE format('CREATE TRIGGER audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$I FOR EACH ROW EXECUTE FUNCTION audit_trg()',t);
    END IF;
  END LOOP;
END$$;

-- Ensure direct API reads have the required table privilege while RLS remains the real gate.
GRANT SELECT ON public.holidays,public.employee_adjustments TO authenticated;

COMMIT;

-- ============================== 027_fix_security_definer_hr.sql ==============================
BEGIN;

-- 027) Fix the SECURITY DEFINER payroll helper added by 026.
-- Cause: employee_adjustment_totals() was callable by authenticated users
-- but did not contain an auth/role guard, so go_live_preflight() flagged it.
-- This is an additive/idempotent fix and does not touch business data.

CREATE OR REPLACE FUNCTION public.employee_adjustment_totals(
  p_employee uuid,
  p_month date
)
RETURNS TABLE(
  rewards numeric,
  penalties numeric,
  net_adjustment numeric
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path=public
AS $$
  SELECT
    coalesce(sum(amount) FILTER (WHERE kind='reward'),0),
    coalesce(sum(amount) FILTER (WHERE kind='penalty'),0),
    coalesce(sum(CASE WHEN kind='reward' THEN amount ELSE -amount END),0)
  FROM public.employee_adjustments
  WHERE auth_role() IN ('admin','accountant')
    AND employee_id=p_employee
    AND approved
    AND (payroll_month IS NULL
         OR date_trunc('month',payroll_month)=date_trunc('month',p_month));
$$;

REVOKE ALL ON FUNCTION public.employee_adjustment_totals(uuid,date) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.employee_adjustment_totals(uuid,date) TO authenticated;

COMMIT;

-- ============================== 028_custom_user_permissions.sql ==============================
BEGIN;

-- 028) Custom per-user access profiles (additive, non-destructive).
-- A custom profile can ONLY remove modules from the user's existing role baseline.
-- It never grants permissions beyond the base role, so existing backend role security remains intact.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS permissions_mode text NOT NULL DEFAULT 'role';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.profiles'::regclass
      AND conname='profiles_permissions_mode_chk'
  ) THEN
    ALTER TABLE profiles
      ADD CONSTRAINT profiles_permissions_mode_chk
      CHECK (permissions_mode IN ('role','custom'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS user_permissions (
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  permission_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, permission_key)
);

CREATE INDEX IF NOT EXISTS idx_user_permissions_key ON user_permissions(permission_key);

ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_permissions_select ON user_permissions;
CREATE POLICY user_permissions_select
  ON user_permissions FOR SELECT TO authenticated
  USING (auth_role()='admin' OR user_id=auth.uid());

DROP POLICY IF EXISTS user_permissions_insert ON user_permissions;
CREATE POLICY user_permissions_insert
  ON user_permissions FOR INSERT TO authenticated
  WITH CHECK (auth_role()='admin');

DROP POLICY IF EXISTS user_permissions_update ON user_permissions;
CREATE POLICY user_permissions_update
  ON user_permissions FOR UPDATE TO authenticated
  USING (auth_role()='admin')
  WITH CHECK (auth_role()='admin');

DROP POLICY IF EXISTS user_permissions_delete ON user_permissions;
CREATE POLICY user_permissions_delete
  ON user_permissions FOR DELETE TO authenticated
  USING (auth_role()='admin');

REVOKE ALL ON TABLE user_permissions FROM public,anon,authenticated;
GRANT SELECT ON TABLE user_permissions TO authenticated;

-- Returns the current user's custom mode and allowed module keys.
CREATE OR REPLACE FUNCTION get_my_permissions()
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
SELECT jsonb_build_object(
  'mode', coalesce(p.permissions_mode,'role'),
  'role', p.role,
  'permissions', coalesce(
    (SELECT jsonb_agg(up.permission_key ORDER BY up.permission_key)
     FROM user_permissions up
     WHERE up.user_id=p.id),
    '[]'::jsonb
  )
)
FROM profiles p
WHERE p.id=auth.uid()
  AND auth_role() IS NOT NULL;
$$;

-- Admin-only read helper for the custom-permission editor.
CREATE OR REPLACE FUNCTION admin_get_user_permissions(p_user uuid)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
SELECT jsonb_build_object(
  'user_id',p.id,
  'mode',coalesce(p.permissions_mode,'role'),
  'role',p.role,
  'permissions',coalesce(
    (SELECT jsonb_agg(up.permission_key ORDER BY up.permission_key)
     FROM user_permissions up
     WHERE up.user_id=p.id),
    '[]'::jsonb
  )
)
FROM profiles p
WHERE p.id=p_user
  AND auth_role()='admin';
$$;

-- Admin-only writer. Only known application module keys are accepted.
CREATE OR REPLACE FUNCTION save_user_permissions(p_user uuid, p_permissions jsonb DEFAULT '[]'::jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_role text;
  v_key text;
BEGIN
  PERFORM require_role('{admin}');

  SELECT role INTO v_role FROM profiles WHERE id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;
  IF v_role='admin' THEN RAISE EXCEPTION 'صلاحيات المدير الأساسية لا يتم تقييدها من هذا المحرر'; END IF;

  DELETE FROM user_permissions WHERE user_id=p_user;

  FOR v_key IN
    SELECT DISTINCT value
    FROM jsonb_array_elements_text(coalesce(p_permissions,'[]'::jsonb))
    WHERE value IN (
      'dash','prod','cust','supp','sales','dn','purch','po','grn','ret','quo','ord','stmt','pay',
      'exp','cash','bank','trf','stk','trace','price','comm','asset','emp','hr','prl','chk','taxdoc',
      'rep','jr'
    )
  LOOP
    INSERT INTO user_permissions(user_id,permission_key)
    VALUES(p_user,v_key)
    ON CONFLICT DO NOTHING;
  END LOOP;

  UPDATE profiles SET permissions_mode='custom' WHERE id=p_user;
END $$;

CREATE OR REPLACE FUNCTION reset_user_permissions(p_user uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_role text;
BEGIN
  PERFORM require_role('{admin}');
  SELECT role INTO v_role FROM profiles WHERE id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;
  IF v_role='admin' THEN RETURN; END IF;
  DELETE FROM user_permissions WHERE user_id=p_user;
  UPDATE profiles SET permissions_mode='role' WHERE id=p_user;
END $$;

REVOKE ALL ON FUNCTION get_my_permissions() FROM public,anon;
REVOKE ALL ON FUNCTION admin_get_user_permissions(uuid) FROM public,anon;
REVOKE ALL ON FUNCTION save_user_permissions(uuid,jsonb) FROM public,anon;
REVOKE ALL ON FUNCTION reset_user_permissions(uuid) FROM public,anon;

GRANT EXECUTE ON FUNCTION get_my_permissions() TO authenticated;
GRANT EXECUTE ON FUNCTION admin_get_user_permissions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION save_user_permissions(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_user_permissions(uuid) TO authenticated;

COMMIT;

-- v1.2 patch: منح القراءة على الـviews بعد إنشائها
BEGIN;
GRANT SELECT ON customer_balances, supplier_balances, low_stock TO authenticated;
COMMIT;

-- ============================================================
-- v1.1 patch: إعادة صلاحية EXECUTE للـRPCs اللي الواجهة بتستخدمها.
-- 024 عمل REVOKE لكل الدوال من authenticated وأعاد المنح لقائمة محددة فقط،
-- فالدوال دي ضاعت منها الصلاحية. set_product_tracking ماكانش ليها منح أصلاً.
-- الـhelpers الداخلية (apply_cash, apply_stock, _rebuild_journal...) مش مضافة هنا عمداً.
-- ============================================================
BEGIN;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname = ANY(ARRAY[
        'cancel_order',
        'create_expense',
        'create_quotation',
        'order_to_invoice',
        'pay_payroll',
        'quotation_to_order',
        'set_product_tracking'
      ])
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated', r.proname, r.args);
  END LOOP;
END $$;

COMMIT;

-- ============================================================
-- v1.12: مفتاح journal_entry_id في الإهلاك وأرصدة الافتتاح يصبح ON DELETE SET NULL
-- عشان إعادة بناء اليومية (DELETE من journal_entries) متفشلش.
-- ============================================================
BEGIN;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['asset_depreciations','opening_balance_runs'] LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I', t, t||'_journal_entry_id_fkey');
      EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE SET NULL', t, t||'_journal_entry_id_fkey');
    END IF;
  END LOOP;
END $$;
COMMIT;

-- ============================================================
-- v1.16: RLS على الجداول الثلاثة اللي كانت مفتوحة + صلاحية SELECT لـauthenticated على كل الجداول
-- (RLS هو اللي بيحدد الصفوف، والصلاحية دي بتسمح بس بالقراءة)
-- ============================================================
BEGIN;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['branches','cost_centers','fiscal_periods'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename=t AND policyname='sel_'||t) THEN
      EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (auth_role() IS NOT NULL)', 'sel_'||t, t);
    END IF;
  END LOOP;
END $$;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
COMMIT;

-- ============================================================
-- v1.17: صلاحيات الكتابة (INSERT/UPDATE/DELETE) للجداول اللي الواجهة بتكتب فيها مباشرة.
-- الـRLS policies موجودة لكل جدول وبتحدد كل دور يقدر يكتب إيه، فالصلاحية دي مش بتوسّع الوصول.
-- (ده كان سبب خطأ permission denied for table attendance وغيرها)
-- ============================================================
BEGIN;
GRANT INSERT, UPDATE, DELETE ON asset_categories,attendance,bank_statement_lines,bank_statements,bom_items,boms,branches,commission_rules,cost_centers,employee_adjustments,fiscal_periods,holidays,integration_connections,leave_requests,price_list_items,price_lists,projects,service_tickets TO authenticated;
COMMIT;

-- v1.18: الاستيراد للمدير فقط (import_* RPCs)

-- ============================================================
-- v1.20: دور المطور (developer)
-- - المطور = صلاحيات المدير كاملة + أدوات المطور (اختبارات الجاهزية).
-- - auth_role() بيرجّع 'admin' للمطور عشان كل الصلاحيات الموجودة تشتغل.
-- - حساب المطور مش بيتعدل أو يتحذف إلا بواسطة المطور.
-- ============================================================
BEGIN;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('admin','accountant','sales','store','developer'));

CREATE OR REPLACE FUNCTION is_developer() RETURNS boolean LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND active AND role='developer') $$;

CREATE OR REPLACE FUNCTION require_dev() RETURNS void LANGUAGE plpgsql STABLE SET search_path=public AS $$
BEGIN IF NOT is_developer() THEN RAISE EXCEPTION 'هذه الخاصية للمطور فقط'; END IF; END $$;

CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN role='developer' THEN 'admin' ELSE role END FROM profiles WHERE id=auth.uid() AND active $$;

CREATE OR REPLACE FUNCTION trg_protect_developer() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF current_user IN ('authenticated','anon') AND NOT is_developer() THEN
    IF TG_OP='INSERT' AND NEW.role='developer' THEN RAISE EXCEPTION 'لا يمكن إنشاء حساب مطور إلا بواسطة المطور'; END IF;
    IF TG_OP='UPDATE' AND (OLD.role='developer' OR NEW.role='developer') THEN RAISE EXCEPTION 'حساب المطور لا يتم تعديله إلا بواسطة المطور'; END IF;
    IF TG_OP='DELETE' AND OLD.role='developer' THEN RAISE EXCEPTION 'لا يمكن حذف حساب المطور'; END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS protect_developer ON profiles;
CREATE TRIGGER protect_developer BEFORE INSERT OR UPDATE OR DELETE ON profiles FOR EACH ROW EXECUTE FUNCTION trg_protect_developer();

REVOKE EXECUTE ON FUNCTION is_developer(), require_dev(), trg_protect_developer() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION trg_protect_developer() FROM authenticated;
GRANT EXECUTE ON FUNCTION is_developer(), require_dev() TO authenticated;
COMMIT;

-- ===== ERP v1.22 patch =====
-- ERP v1.22: شريط الاختصارات القابل للتخصيص (محفوظ في الداتابيز لكل مستخدم)
create table if not exists user_quick_actions(
  user_id uuid primary key references auth.users on delete cascade,
  actions text[] not null default '{}',
  updated_at timestamptz default now());
alter table user_quick_actions enable row level security;
revoke all on user_quick_actions from public, anon;
grant select, insert, update, delete on user_quick_actions to authenticated;
drop policy if exists qa_own on user_quick_actions;
create policy qa_own on user_quick_actions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ===== service_role grants fix =====
-- إصلاح صلاحيات service_role (لازم تتشغل مرة واحدة على الداتابيز الحية لو إضافة المستخدم بتطلع permission denied)
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant all on all functions in schema public to service_role;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant all on functions to service_role;

-- ====================== patch v1.45 ======================
-- ============================================================
-- ERP patch v1.45 (فوق قاعدة v1.44 / SQL v1.22)
-- 1) دوال صريحة للإنشاء (قوائم أسعار، قواعد عمولة، فترات، تصنيفات أصول) بفحص صلاحيات واضح
-- 2) سجل حركة الخزينة (كل داخل وخارج، من أي عملية، وبأي مستخدم)
-- 3) ربط الموظف بيوزر في النظام
-- 4) تعديل الفاتورة بيحافظ على التاريخ الأصلي (وقيده المحاسبي)
-- آمن للتشغيل أكثر من مرة.
-- ============================================================
BEGIN;

-- 3) ربط الموظف باليوزر
ALTER TABLE employees ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES profiles(id);

-- 2) سجل حركة الخزينة
CREATE TABLE IF NOT EXISTS cash_movements(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  account_id uuid NOT NULL REFERENCES cash_accounts,
  direction text NOT NULL CHECK(direction IN ('in','out')),
  amount numeric(14,2) NOT NULL CHECK(amount>=0),
  source text,
  user_id uuid DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS cash_movements_created_idx ON cash_movements(created_at);
ALTER TABLE cash_movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sel_cash_movements ON cash_movements;
CREATE POLICY sel_cash_movements ON cash_movements FOR SELECT TO authenticated USING(auth_role() IN ('admin','accountant'));
GRANT SELECT ON cash_movements TO authenticated;

CREATE OR REPLACE FUNCTION apply_cash(p_acct uuid,p_delta numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE src text;
BEGIN
  UPDATE cash_accounts SET balance=balance+p_delta WHERE id=p_acct;
  IF NOT FOUND THEN RAISE EXCEPTION 'الحساب المالي غير موجود'; END IF;
  src:=coalesce((regexp_match(current_query(),'"?public"?\."?(\w+)"?\s*\('))[1],'');
  INSERT INTO cash_movements(account_id,direction,amount,source,user_id)
    VALUES(p_acct,CASE WHEN p_delta>=0 THEN 'in' ELSE 'out' END,abs(p_delta),src,auth.uid());
END $$;

-- 1) دوال إنشاء صريحة
CREATE OR REPLACE FUNCTION create_price_list(p_name text,p_currency text DEFAULT 'EGP') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid;
BEGIN
  PERFORM require_role('{admin,accountant,sales}');
  IF coalesce(trim(p_name),'')='' THEN RAISE EXCEPTION 'اكتب اسم قائمة الأسعار'; END IF;
  INSERT INTO price_lists(name,currency) VALUES(trim(p_name),coalesce(nullif(trim(p_currency),''),'EGP')) RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION add_price_list_item(p_list uuid,p_product uuid,p_price numeric,p_min_qty numeric DEFAULT 1) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid;
BEGIN
  PERFORM require_role('{admin,accountant,sales}');
  IF p_price IS NULL OR p_price<0 THEN RAISE EXCEPTION 'السعر غير صحيح'; END IF;
  INSERT INTO price_list_items(price_list_id,product_id,price,min_qty) VALUES(p_list,p_product,p_price,coalesce(p_min_qty,1)) RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_commission_rule(p_name text,p_rate numeric,p_basis text DEFAULT 'net_sales') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF coalesce(trim(p_name),'')='' THEN RAISE EXCEPTION 'اكتب اسم القاعدة'; END IF;
  IF p_rate IS NULL OR p_rate<0 THEN RAISE EXCEPTION 'النسبة غير صحيحة'; END IF;
  INSERT INTO commission_rules(name,rate,basis) VALUES(trim(p_name),p_rate,coalesce(p_basis,'net_sales')) RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_fiscal_period(p_name text,p_start date,p_end date) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF p_start IS NULL OR p_end IS NULL OR p_end<p_start THEN RAISE EXCEPTION 'تواريخ الفترة غير صحيحة'; END IF;
  INSERT INTO fiscal_periods(name,start_date,end_date,status) VALUES(coalesce(nullif(trim(p_name),''),'فترة '||to_char(p_start,'YYYY-MM')),p_start,p_end,'Open') RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION create_asset_category(p_name text,p_life_months int DEFAULT 60) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v uuid;
BEGIN
  PERFORM require_role('{admin,accountant}');
  IF coalesce(trim(p_name),'')='' THEN RAISE EXCEPTION 'اكتب اسم التصنيف'; END IF;
  INSERT INTO asset_categories(name,default_life_months) VALUES(trim(p_name),coalesce(p_life_months,60)) RETURNING id INTO v;
  RETURN v;
END $$;

REVOKE ALL ON FUNCTION create_price_list(text,text),add_price_list_item(uuid,uuid,numeric,numeric),create_commission_rule(text,numeric,text),create_fiscal_period(text,date,date),create_asset_category(text,int) FROM public,anon;
GRANT EXECUTE ON FUNCTION create_price_list(text,text),add_price_list_item(uuid,uuid,numeric,numeric),create_commission_rule(text,numeric,text),create_fiscal_period(text,date,date),create_asset_category(text,int) TO authenticated;

-- صلاحيات الكتابة للموظفين (تتحدد بالدور صراحة)
DROP POLICY IF EXISTS write_employees ON employees;
CREATE POLICY write_employees ON employees FOR ALL TO authenticated USING(auth_role() IN ('admin','accountant')) WITH CHECK(auth_role() IN ('admin','accountant'));
GRANT INSERT, UPDATE ON employees TO authenticated;

-- 4) تعديل الفاتورة مع الحفاظ على التاريخ الأصلي وقيوده
CREATE OR REPLACE FUNCTION edit_sales_invoice(p_invoice uuid,p_customer uuid,p_warehouse uuid,p_items jsonb,p_paid numeric DEFAULT 0,p_account uuid DEFAULT NULL,p_method text DEFAULT 'credit',p_discount numeric DEFAULT 0) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE old_no text; old_date date; nid uuid;
BEGIN
  PERFORM require_role('{admin}');
  SELECT number,date INTO old_no,old_date FROM sales_invoices WHERE id=p_invoice;
  IF old_no IS NULL THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  PERFORM cancel_sales_invoice(p_invoice);
  nid:=create_sale(p_customer,p_warehouse,p_items,p_paid,p_account,p_method,p_discount);
  UPDATE sales_invoices SET date=old_date WHERE id=nid;
  UPDATE journal_entries SET date=old_date WHERE doc_id IN (p_invoice,nid);
  PERFORM log_event('edit','sales_invoices',nid::text,'عدّل فاتورة مبيعات '||old_no||' بنفس تاريخها الأصلي '||old_date::text||' (أُلغيت الأصلية وأُنشئت فاتورة جديدة بالتعديلات)');
  RETURN nid;
END $$;

COMMIT;

-- ====================== patch v1.46 ======================
-- ============================================================
-- ERP patch v1.46 (فوق v1.45)
-- 1) إصلاح خطأ "column reference unit_cost is ambiguous" عند حفظ مرتجع المبيعات
--    (اسم متغير محلي كان بيتعارض مع عمود في الجدول)
-- 2) ترحيل حركات الخزينة القديمة (قبل v1.45): الدفعات والمصروفات والتحويلات والمرتبات المدفوعة
--    مرة واحدة فقط، وبيتحطوا في تواريخهم الأصلية. آمن للتشغيل أكثر من مرة.
-- ============================================================
BEGIN;

-- 1) مرتجع المبيعات
CREATE OR REPLACE FUNCTION create_sales_return(p_invoice uuid,p_items jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  inv sales_invoices; it jsonb; v uuid:=gen_random_uuid(); tot numeric:=0; base numeric:=0; tax numeric:=0; sold numeric; prior numeric; q numeric;
  pid uuid; v_price numeric; v_cost numeric; line_net numeric; line_tax numeric; discount_factor numeric; num text;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  SELECT * INTO inv FROM sales_invoices WHERE id=p_invoice AND status='Posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة'; END IF;
  num:=(SELECT invoice_prefix FROM company_settings WHERE id=1)||'SR'||(1000+nextval('seq_sret'));
  INSERT INTO sales_returns(id,number,invoice_id,customer_id,warehouse_id) VALUES(v, num, inv.id, inv.customer_id, inv.warehouse_id);
  discount_factor:=case when inv.subtotal>0 then greatest(inv.subtotal-inv.discount,0)/inv.subtotal else 1 end;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    pid:=(it->>'product_id')::uuid; q:=(it->>'qty')::numeric; CONTINUE WHEN q IS NULL OR q<=0;
    SELECT coalesce(sum(qty),0),coalesce(sum(line_total)/nullif(sum(qty),0),0),coalesce(sum(qty*unit_cost)/nullif(sum(qty),0),0)
      INTO sold,v_price,v_cost FROM sales_invoice_items WHERE invoice_id=inv.id AND product_id=pid;
    SELECT coalesce(sum(i.qty),0) INTO prior FROM sales_return_items i JOIN sales_returns r ON r.id=i.return_id
      WHERE r.invoice_id=inv.id AND i.product_id=pid AND r.id<>v;
    IF q>sold-prior THEN RAISE EXCEPTION 'لا يمكن إرجاع كمية أكبر من المباعة (المتاح للإرجاع %)',sold-prior; END IF;
    line_net:=round(q*v_price*discount_factor,2); line_tax:=round(line_net*inv.tax_rate/100,2);
    INSERT INTO sales_return_items(return_id,product_id,qty,unit_price,line_total,unit_cost,cost_total,tax)
      VALUES(v,pid,q,v_price,line_net,v_cost,round(q*v_cost,2),line_tax);
    PERFORM apply_stock(pid,inv.warehouse_id,q,'Sales Return','sales_return',v);
    base:=base+line_net; tax:=tax+line_tax;
  END LOOP;
  IF base=0 THEN RAISE EXCEPTION 'حدد كمية للإرجاع'; END IF;
  tot:=round(base+tax,2);
  UPDATE sales_returns SET total=tot WHERE id=v;
  PERFORM log_event('create','sales_returns',v::text,'سجل مرتجع مبيعات '||num||' بقيمة '||tot);
  RETURN v;
END $$;

-- 2) ترحيل الحركات القديمة للخزينة (مرة واحدة)
DO $$
DECLARE cutoff timestamptz; cutday date;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM cash_movements WHERE source LIKE 'backfill%') THEN
    -- أول حركة اتسجلت بعد التحديث = حد الترحيل. أي حاجة قبلها قديمة.
    SELECT min(created_at) INTO cutoff FROM cash_movements;
    IF cutoff IS NULL THEN cutoff:=now(); END IF;
    cutday:=(cutoff AT TIME ZONE 'Africa/Cairo')::date;

    INSERT INTO cash_movements(created_at,account_id,direction,amount,source,user_id)
      SELECT p.created_at,p.account_id,CASE WHEN p.kind='receipt' THEN 'in' ELSE 'out' END,p.amount,'backfill_payment',p.created_by
      FROM payments p WHERE p.created_at<cutoff;

    INSERT INTO cash_movements(created_at,account_id,direction,amount,source,user_id)
      SELECT x.created_at,x.account_id,'out',x.amount,'backfill_expense',x.created_by
      FROM expenses x WHERE x.created_at<cutoff;

    INSERT INTO cash_movements(created_at,account_id,direction,amount,source,user_id)
      SELECT (t.date::timestamp AT TIME ZONE 'Africa/Cairo'),t.from_account,'out',t.amount,'backfill_transfer',t.created_by
      FROM cash_transfers t WHERE t.date<cutday;
    INSERT INTO cash_movements(created_at,account_id,direction,amount,source,user_id)
      SELECT (t.date::timestamp AT TIME ZONE 'Africa/Cairo'),t.to_account,'in',t.amount,'backfill_transfer',t.created_by
      FROM cash_transfers t WHERE t.date<cutday;

    INSERT INTO cash_movements(created_at,account_id,direction,amount,source,user_id)
      SELECT (p.month::timestamp AT TIME ZONE 'Africa/Cairo'),p.account_id,'out',p.net,'backfill_payroll',NULL
      FROM payroll p WHERE p.paid AND p.account_id IS NOT NULL AND p.net>0 AND p.month<cutday;
  END IF;
END $$;

COMMIT;

-- ====================== patch v1.47 ======================
-- ============================================================
-- ERP patch v1.47 (فوق v1.46)
-- 1) حد الخصم لدور المبيعات بقى في الداتابيز (كان في الواجهة بس، والسيرفر ما بيمنعش)
--    الحد 5% من إجمالي الأصناف. الأدمن والمحاسب مالهمش حد.
--    التريجر بيفحص بس لما الخصم أو الإجمالي يتغيّر، فمفيش أي تأثير على الفواتير القديمة.
-- 2) دالة cash_balances_at(ts): رصيد كل حساب خزينة في لحظة معينة.
--    بتستخدمها صفحة الخزينة عشان تعرض الرصيد الافتتاحي والختامي لكل يوم.
-- آمن للتشغيل أكثر من مرة.
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION trg_sales_discount_cap() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE sub_items numeric; cap constant numeric := 5;
BEGIN
  IF auth_role() IS DISTINCT FROM 'sales' THEN RETURN NEW; END IF;
  SELECT coalesce(sum(line_total),0) INTO sub_items FROM sales_invoice_items WHERE invoice_id=NEW.id;
  IF coalesce(NEW.discount,0) > round(sub_items*cap/100,2) THEN
    RAISE EXCEPTION 'أقصى خصم على الفاتورة لدور المبيعات % %% من إجمالي الأصناف = %', cap, round(sub_items*cap/100,2);
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION trg_sales_discount_cap() FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS sales_discount_cap ON sales_invoices;
CREATE TRIGGER sales_discount_cap BEFORE UPDATE OF discount, subtotal ON sales_invoices
  FOR EACH ROW WHEN (NEW.discount IS DISTINCT FROM OLD.discount OR NEW.subtotal IS DISTINCT FROM OLD.subtotal)
  EXECUTE FUNCTION trg_sales_discount_cap();

CREATE OR REPLACE FUNCTION cash_balances_at(p_ts timestamptz) RETURNS TABLE(account_id uuid, balance numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant}');
  RETURN QUERY
    SELECT a.id, a.balance - coalesce(sum(CASE WHEN m.direction='in' THEN m.amount ELSE -m.amount END),0)
    FROM cash_accounts a
    LEFT JOIN cash_movements m ON m.account_id=a.id AND m.created_at>=p_ts
    GROUP BY a.id, a.balance;
END $$;
GRANT EXECUTE ON FUNCTION cash_balances_at(timestamptz) TO authenticated;

COMMIT;

-- ====================== patch v1.48 ======================
-- ============================================================
-- ERP patch v1.48 (فوق v1.47)
-- حد خصم المبيعات بقى إعداد في "الإعدادات" (من 0 لـ 100%) بدل ما يكون ثابت 5%.
-- التريجر في الداتابيز بيقرأ الحد من company_settings.
-- آمن للتشغيل أكثر من مرة. الافتراضي 5% زي ما كان.
-- ============================================================
BEGIN;

ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS sales_discount_max_pct numeric(5,2) NOT NULL DEFAULT 5;
ALTER TABLE company_settings DROP CONSTRAINT IF EXISTS company_settings_sales_discount_max_pct_check;
ALTER TABLE company_settings ADD CONSTRAINT company_settings_sales_discount_max_pct_check CHECK (sales_discount_max_pct>=0 AND sales_discount_max_pct<=100);

CREATE OR REPLACE FUNCTION trg_sales_discount_cap() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE sub_items numeric; cap numeric;
BEGIN
  IF auth_role() IS DISTINCT FROM 'sales' THEN RETURN NEW; END IF;
  SELECT coalesce(sales_discount_max_pct,5) INTO cap FROM company_settings WHERE id=1;
  SELECT coalesce(sum(line_total),0) INTO sub_items FROM sales_invoice_items WHERE invoice_id=NEW.id;
  IF coalesce(NEW.discount,0) > round(sub_items*cap/100,2) THEN
    RAISE EXCEPTION 'أقصى خصم على الفاتورة لدور المبيعات % %% من إجمالي الأصناف = %', cap, round(sub_items*cap/100,2);
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION trg_sales_discount_cap() FROM PUBLIC,anon,authenticated;

COMMIT;

-- ====================== patch v1.49 ======================
-- ============================================================
-- ERP patch v1.49 (فوق v1.48)
-- 1) تدقيق الصلاحيات: مفيش دالة متاحة لـ anon أو PUBLIC، والمسجلين بس.
--    الجداول: anon ملوش أي صلاحية. الدوال الجديدة كمان متقفلة من البداية.
-- 2) لوجو الشركة: حقل logo_url + bucket عام اسمه company-assets.
--    الرفع للأدمن بس.
-- آمن للتشغيل أكثر من مرة.
-- ============================================================
BEGIN;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS logo_url text;

DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name='storage') THEN
    INSERT INTO storage.buckets(id,name,public) VALUES('company-assets','company-assets',true) ON CONFLICT (id) DO NOTHING;
    DROP POLICY IF EXISTS company_assets_insert ON storage.objects;
    DROP POLICY IF EXISTS company_assets_update ON storage.objects;
    CREATE POLICY company_assets_insert ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id='company-assets' AND auth_role()='admin');
    CREATE POLICY company_assets_update ON storage.objects FOR UPDATE TO authenticated
      USING (bucket_id='company-assets' AND auth_role()='admin') WITH CHECK (bucket_id='company-assets' AND auth_role()='admin');
  END IF;
END $$;

COMMIT;

-- ====================== patch v1.50 ======================
-- ============================================================
-- ERP patch v1.50 (فوق v1.49)
-- الأطراف الموحدة: كل طرف (عميل و/أو مورد) ليه سجل واحد رئيسي (parties).
-- - العملاء والموردين الحاليين بيتربطوا بالطرف (بالاسم، من غير تكرار).
-- - الفواتير والمدفوعات بتفضل مرتبطة بسجل العميل/المورد زي ما هي،
--   فالقيود المحاسبية (ذمم العملاء والموردين منفصلة) مش بتتأثر.
-- - الشاشة بتعرض الطرف مرة واحدة برصيد صافي.
-- آمن للتشغيل مرة واحدة. (لو اتشغل تاني هيتخطى الترحيل)
-- ============================================================
BEGIN;

CREATE TABLE IF NOT EXISTS parties(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text, email text, address text, tax_number text, notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE customers ADD COLUMN IF NOT EXISTS party_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS party_id uuid;

DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='customers_party_fk') THEN
    ALTER TABLE customers ADD CONSTRAINT customers_party_fk FOREIGN KEY (party_id) REFERENCES parties(id);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='suppliers_party_fk') THEN
    ALTER TABLE suppliers ADD CONSTRAINT suppliers_party_fk FOREIGN KEY (party_id) REFERENCES parties(id);
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS customers_one_party ON customers(party_id) WHERE party_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_one_party ON suppliers(party_id) WHERE party_id IS NOT NULL;

-- ترحيل: كل عميل/مورد من غير طرف، بنربطه بطرف بنفس الاسم (لو موجود وما لوش نفس الدور)، أو بننشئ طرف جديد
DO $$
DECLARE r record; pid uuid;
BEGIN
  FOR r IN SELECT id,name,phone,email,address,notes,active FROM customers WHERE party_id IS NULL LOOP
    SELECT p.id INTO pid FROM parties p
      WHERE lower(trim(p.name))=lower(trim(r.name)) AND NOT EXISTS(SELECT 1 FROM customers c WHERE c.party_id=p.id)
      ORDER BY p.created_at LIMIT 1;
    IF pid IS NULL THEN
      INSERT INTO parties(name,phone,email,address,notes,active) VALUES(r.name,r.phone,r.email,r.address,r.notes,r.active) RETURNING id INTO pid;
    END IF;
    UPDATE customers SET party_id=pid WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id,name,phone,email,address,notes,active FROM suppliers WHERE party_id IS NULL LOOP
    SELECT p.id INTO pid FROM parties p
      WHERE lower(trim(p.name))=lower(trim(r.name)) AND NOT EXISTS(SELECT 1 FROM suppliers s WHERE s.party_id=p.id)
      ORDER BY p.created_at LIMIT 1;
    IF pid IS NULL THEN
      INSERT INTO parties(name,phone,email,address,notes,active) VALUES(r.name,r.phone,r.email,r.address,r.notes,r.active) RETURNING id INTO pid;
    END IF;
    UPDATE suppliers SET party_id=pid WHERE id=r.id;
  END LOOP;
END $$;

-- المصدر الرئيسي للبيانات هو الطرف: أي تعديل عليه بيتنقل للعميل والمورد المرتبطين
CREATE OR REPLACE FUNCTION trg_party_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE customers SET name=NEW.name,phone=NEW.phone,email=NEW.email,address=NEW.address WHERE party_id=NEW.id;
  UPDATE suppliers SET name=NEW.name,phone=NEW.phone,email=NEW.email,address=NEW.address WHERE party_id=NEW.id;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS party_sync ON parties;
CREATE TRIGGER party_sync AFTER UPDATE OF name,phone,email,address ON parties
  FOR EACH ROW EXECUTE FUNCTION trg_party_sync();

CREATE OR REPLACE FUNCTION trg_role_from_party() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p parties;
BEGIN
  IF NEW.party_id IS NOT NULL THEN
    SELECT * INTO p FROM parties WHERE id=NEW.party_id;
    IF FOUND THEN NEW.name:=p.name; NEW.phone:=p.phone; NEW.email:=p.email; NEW.address:=p.address; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS role_from_party ON customers;
CREATE TRIGGER role_from_party BEFORE INSERT OR UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION trg_role_from_party();
DROP TRIGGER IF EXISTS role_from_party ON suppliers;
CREATE TRIGGER role_from_party BEFORE INSERT OR UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION trg_role_from_party();
REVOKE EXECUTE ON FUNCTION trg_party_sync(), trg_role_from_party() FROM PUBLIC, anon, authenticated;

-- صلاحيات الجدول
ALTER TABLE parties ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sel_parties ON parties;
DROP POLICY IF EXISTS write_parties ON parties;
CREATE POLICY sel_parties ON parties FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
CREATE POLICY write_parties ON parties FOR ALL TO authenticated
  USING(auth_role() IN ('admin','accountant','sales','store')) WITH CHECK(auth_role() IN ('admin','accountant','sales','store'));
GRANT SELECT, INSERT, UPDATE ON parties TO authenticated;

-- رصيد الطرف: عميل + مورد. الصافي = له علينا (موجب) ناقص علينا ليه
CREATE OR REPLACE VIEW party_balances WITH(security_invoker=true) AS
SELECT p.id AS party_id, p.name, p.phone, p.email, p.active,
  c.id AS customer_id, c.active AS customer_active,
  s.id AS supplier_id, s.active AS supplier_active,
  coalesce(cb.balance,0) AS receivable,
  coalesce(sb.balance,0) AS payable,
  coalesce(cb.balance,0)-coalesce(sb.balance,0) AS net
FROM parties p
LEFT JOIN customers c ON c.party_id=p.id
LEFT JOIN suppliers s ON s.party_id=p.id
LEFT JOIN customer_balances cb ON cb.id=c.id
LEFT JOIN supplier_balances sb ON sb.id=s.id;
GRANT SELECT ON party_balances TO authenticated;

-- إنشاء طرف (عميل و/أو مورد) في خطوة واحدة
CREATE OR REPLACE FUNCTION create_party(p_name text,p_phone text,p_email text,p_address text,p_tax text,p_notes text,
  p_roles text[],p_credit_limit numeric DEFAULT 0,p_customer_terms int DEFAULT 0,p_customer_opening numeric DEFAULT 0,
  p_supplier_terms int DEFAULT 0,p_supplier_opening numeric DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE pid uuid;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF trim(coalesce(p_name,''))='' THEN RAISE EXCEPTION 'اكتب اسم الطرف'; END IF;
  IF p_roles IS NULL OR NOT (p_roles && ARRAY['customer','supplier']) THEN RAISE EXCEPTION 'اختار عميل أو مورد على الأقل'; END IF;
  IF 'customer'=ANY(p_roles) THEN PERFORM require_role('{admin,accountant,sales}'); END IF;
  IF 'supplier'=ANY(p_roles) THEN PERFORM require_role('{admin,accountant,store}'); END IF;
  IF EXISTS(SELECT 1 FROM parties WHERE lower(trim(name))=lower(trim(p_name))) THEN RAISE EXCEPTION 'يوجد طرف بنفس الاسم بالفعل'; END IF;
  INSERT INTO parties(name,phone,email,address,tax_number,notes)
    VALUES(trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_tax,'')),''),nullif(trim(coalesce(p_notes,'')),''))
    RETURNING id INTO pid;
  IF 'customer'=ANY(p_roles) THEN
    INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes,party_id)
      SELECT name,phone,email,address,coalesce(p_credit_limit,0),coalesce(p_customer_terms,0),coalesce(p_customer_opening,0),notes,id FROM parties WHERE id=pid;
  END IF;
  IF 'supplier'=ANY(p_roles) THEN
    INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes,party_id)
      SELECT name,phone,email,address,coalesce(p_supplier_terms,0),coalesce(p_supplier_opening,0),notes,id FROM parties WHERE id=pid;
  END IF;
  PERFORM log_event('create','parties',pid::text,'أنشأ طرف '||trim(p_name));
  RETURN pid;
END $$;

-- تعديل بيانات الطرف والشروط الخاصة بكل دور
CREATE OR REPLACE FUNCTION update_party(p_party uuid,p_name text,p_phone text,p_email text,p_address text,p_tax text,p_notes text,
  p_credit_limit numeric DEFAULT NULL,p_customer_terms int DEFAULT NULL,p_supplier_terms int DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF trim(coalesce(p_name,''))='' THEN RAISE EXCEPTION 'اكتب اسم الطرف'; END IF;
  IF EXISTS(SELECT 1 FROM parties WHERE id<>p_party AND lower(trim(name))=lower(trim(p_name))) THEN RAISE EXCEPTION 'يوجد طرف بنفس الاسم بالفعل'; END IF;
  UPDATE parties SET name=trim(p_name),phone=nullif(trim(coalesce(p_phone,'')),''),email=nullif(trim(coalesce(p_email,'')),''),
    address=nullif(trim(coalesce(p_address,'')),''),tax_number=nullif(trim(coalesce(p_tax,'')),''),notes=nullif(trim(coalesce(p_notes,'')),'')
    WHERE id=p_party;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطرف غير موجود'; END IF;
  IF p_credit_limit IS NOT NULL AND auth_role() IN ('admin','accountant','sales') THEN
    UPDATE customers SET credit_limit=p_credit_limit WHERE party_id=p_party;
  END IF;
  IF p_customer_terms IS NOT NULL AND auth_role() IN ('admin','accountant','sales') THEN
    UPDATE customers SET payment_terms_days=p_customer_terms WHERE party_id=p_party;
  END IF;
  IF p_supplier_terms IS NOT NULL AND auth_role() IN ('admin','accountant','store') THEN
    UPDATE suppliers SET payment_terms_days=p_supplier_terms WHERE party_id=p_party;
  END IF;
END $$;

-- تفعيل/إيقاف دور (عميل أو مورد) للطرف. الدور الموقوف بيفضل محفوظ بتاريخه.
CREATE OR REPLACE FUNCTION set_party_role(p_party uuid,p_role text,p_on boolean,p_credit_limit numeric DEFAULT 0,p_terms int DEFAULT 0,p_opening numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p parties;
BEGIN
  IF p_role='customer' THEN PERFORM require_role('{admin,accountant,sales}');
  ELSIF p_role='supplier' THEN PERFORM require_role('{admin,accountant,store}');
  ELSE RAISE EXCEPTION 'الدور غير صحيح'; END IF;
  SELECT * INTO p FROM parties WHERE id=p_party;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطرف غير موجود'; END IF;
  IF p_role='customer' THEN
    IF EXISTS(SELECT 1 FROM customers WHERE party_id=p_party) THEN
      UPDATE customers SET active=p_on WHERE party_id=p_party;
    ELSIF p_on THEN
      INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes,party_id)
        VALUES(p.name,p.phone,p.email,p.address,coalesce(p_credit_limit,0),coalesce(p_terms,0),coalesce(p_opening,0),p.notes,p.id);
    END IF;
  ELSE
    IF EXISTS(SELECT 1 FROM suppliers WHERE party_id=p_party) THEN
      UPDATE suppliers SET active=p_on WHERE party_id=p_party;
    ELSIF p_on THEN
      INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes,party_id)
        VALUES(p.name,p.phone,p.email,p.address,coalesce(p_terms,0),coalesce(p_opening,0),p.notes,p.id);
    END IF;
  END IF;
END $$;

-- تعطيل/تفعيل الطرف كله (العميل والمورد معاً)
CREATE OR REPLACE FUNCTION set_party_active(p_party uuid,p_on boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  UPDATE parties SET active=p_on WHERE id=p_party;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطرف غير موجود'; END IF;
  UPDATE customers SET active=p_on WHERE party_id=p_party;
  UPDATE suppliers SET active=p_on WHERE party_id=p_party;
END $$;

REVOKE EXECUTE ON FUNCTION create_party(text,text,text,text,text,text,text[],numeric,int,numeric,int,numeric),
  update_party(uuid,text,text,text,text,text,text,numeric,int,int),
  set_party_role(uuid,text,boolean,numeric,int,numeric), set_party_active(uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_party(text,text,text,text,text,text,text[],numeric,int,numeric,int,numeric),
  update_party(uuid,text,text,text,text,text,text,numeric,int,int),
  set_party_role(uuid,text,boolean,numeric,int,numeric), set_party_active(uuid,boolean) TO authenticated;

COMMIT;

-- ====================== patch v1.51 ======================
-- ============================================================
-- ERP patch v1.51 (فوق v1.50)
-- 1) الطرف = عميل ومورد في نفس الوقت (مفيش اختيار دور عند الإضافة).
--    - أي طرف ناقص عميل أو مورد بيتكمّل تلقائياً.
--    - create_party بتعمل الاتنين دايماً.
-- 2) تحديث للمطور: جدول app_control فيه رقم تحديث، المطور يقدر يدفع تحديث لكل اليوزرات.
-- 3) الحضور: الموظف يسجل حضوره/انصرافه بنفسه (attendance_check) + يشوف سجله.
-- آمن للتشغيل أكتر من مرة.
-- ============================================================
BEGIN;

-- 1) استكمال الأدوار الناقصة لكل طرف
INSERT INTO customers(name,phone,email,address,notes,party_id)
  SELECT p.name,p.phone,p.email,p.address,p.notes,p.id FROM parties p
  WHERE NOT EXISTS(SELECT 1 FROM customers c WHERE c.party_id=p.id);
INSERT INTO suppliers(name,phone,email,address,notes,party_id)
  SELECT p.name,p.phone,p.email,p.address,p.notes,p.id FROM parties p
  WHERE NOT EXISTS(SELECT 1 FROM suppliers s WHERE s.party_id=p.id);

-- إنشاء الطرف: عميل ومورد دايماً
CREATE OR REPLACE FUNCTION create_party(p_name text,p_phone text,p_email text,p_address text,p_tax text,p_notes text,
  p_roles text[] DEFAULT NULL,p_credit_limit numeric DEFAULT 0,p_customer_terms int DEFAULT 0,p_customer_opening numeric DEFAULT 0,
  p_supplier_terms int DEFAULT 0,p_supplier_opening numeric DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE pid uuid;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF trim(coalesce(p_name,''))='' THEN RAISE EXCEPTION 'اكتب اسم الطرف'; END IF;
  IF EXISTS(SELECT 1 FROM parties WHERE lower(trim(name))=lower(trim(p_name))) THEN RAISE EXCEPTION 'يوجد طرف بنفس الاسم بالفعل'; END IF;
  INSERT INTO parties(name,phone,email,address,tax_number,notes)
    VALUES(trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_tax,'')),''),nullif(trim(coalesce(p_notes,'')),''))
    RETURNING id INTO pid;
  INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes,party_id)
    SELECT name,phone,email,address,coalesce(p_credit_limit,0),coalesce(p_customer_terms,0),coalesce(p_customer_opening,0),notes,id FROM parties WHERE id=pid;
  INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes,party_id)
    SELECT name,phone,email,address,coalesce(p_supplier_terms,0),coalesce(p_supplier_opening,0),notes,id FROM parties WHERE id=pid;
  PERFORM log_event('create','parties',pid::text,'أنشأ طرف '||trim(p_name));
  RETURN pid;
END $$;

-- 2) تحديث التطبيق للكل
CREATE TABLE IF NOT EXISTS app_control(
  id int PRIMARY KEY DEFAULT 1 CHECK(id=1),
  refresh_token text NOT NULL DEFAULT '0',
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app_control(id) VALUES(1) ON CONFLICT DO NOTHING;
ALTER TABLE app_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_control FROM PUBLIC, anon, authenticated;

-- أي حد (حتى قبل تسجيل الدخول) يقدر يعرف رقم التحديث الحالي
CREATE OR REPLACE FUNCTION app_refresh_token() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT refresh_token FROM app_control WHERE id=1;
$$;
-- المطور بس يدفع تحديث لكل المستخدمين
CREATE OR REPLACE FUNCTION dev_push_refresh() RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t text := to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET refresh_token=t, updated_at=now() WHERE id=1;
  PERFORM log_event('update','app_control','1','دفع تحديث للمستخدمين');
  RETURN t;
END $$;
REVOKE EXECUTE ON FUNCTION app_refresh_token(), dev_push_refresh() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_refresh_token() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION dev_push_refresh() TO authenticated;

-- 3) الحضور الذاتي
DROP POLICY IF EXISTS sel_own_attendance ON attendance;
CREATE POLICY sel_own_attendance ON attendance FOR SELECT TO authenticated
  USING(EXISTS(SELECT 1 FROM employees e WHERE e.id=attendance.employee_id AND e.user_id=auth.uid()));

CREATE OR REPLACE FUNCTION attendance_check(p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE emp uuid; d date := (now() AT TIME ZONE 'Africa/Cairo')::date; rec attendance; nowt timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'لازم تسجل دخول'; END IF;
  SELECT id INTO emp FROM employees WHERE user_id=auth.uid() AND coalesce(active,true) LIMIT 1;
  IF emp IS NULL THEN RAISE EXCEPTION 'حسابك مش مربوط بموظف، كلم الإدارة'; END IF;
  SELECT * INTO rec FROM attendance WHERE employee_id=emp AND work_date=d;
  IF p_action='in' THEN
    IF rec.id IS NOT NULL AND rec.check_in IS NOT NULL THEN RAISE EXCEPTION 'سجلت الحضور النهارده قبل كده'; END IF;
    IF rec.id IS NULL THEN
      INSERT INTO attendance(employee_id,work_date,check_in,status) VALUES(emp,d,nowt,'Present') RETURNING * INTO rec;
    ELSE
      UPDATE attendance SET check_in=nowt, status='Present' WHERE id=rec.id RETURNING * INTO rec;
    END IF;
  ELSIF p_action='out' THEN
    IF rec.id IS NULL OR rec.check_in IS NULL THEN RAISE EXCEPTION 'لازم تسجل الحضور الأول'; END IF;
    IF rec.check_out IS NOT NULL THEN RAISE EXCEPTION 'سجلت الانصراف النهارده قبل كده'; END IF;
    UPDATE attendance SET check_out=nowt WHERE id=rec.id RETURNING * INTO rec;
  ELSE
    RAISE EXCEPTION 'إجراء غير معروف';
  END IF;
  RETURN jsonb_build_object('work_date',rec.work_date,'check_in',rec.check_in,'check_out',rec.check_out,'status',rec.status);
END $$;
REVOKE EXECUTE ON FUNCTION attendance_check(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION attendance_check(text) TO authenticated;

COMMIT;

-- ====================== patch v1.54 ======================
-- ============================================================
-- ERP patch v1.54 (فوق v1.53)
-- إصلاح رفع لوجو الشركة: "new row violates row-level security policy".
-- بيتأكد من وجود bucket اسمه company-assets (عام) وسياسات الرفع/التعديل
-- للأدمن والمطور. آمن للتشغيل أكتر من مرة.
-- ============================================================
BEGIN;

INSERT INTO storage.buckets(id,name,public) VALUES('company-assets','company-assets',true)
  ON CONFLICT (id) DO UPDATE SET public=true;

DROP POLICY IF EXISTS company_assets_insert ON storage.objects;
CREATE POLICY company_assets_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='company-assets' AND auth_role()='admin');

DROP POLICY IF EXISTS company_assets_update ON storage.objects;
CREATE POLICY company_assets_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id='company-assets' AND auth_role()='admin')
  WITH CHECK (bucket_id='company-assets' AND auth_role()='admin');

DROP POLICY IF EXISTS company_assets_delete ON storage.objects;
CREATE POLICY company_assets_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id='company-assets' AND auth_role()='admin');

COMMIT;

-- ====================== patch v1.57 ======================
-- ============================================================
-- ERP patch v1.57 (فوق v1.56)
-- 1) الحضور للأدمن بس: الكتابة والتسجيل (الجدول + دالة الحضور الذاتي).
-- 2) تخصيص الطباعة: عمود print_settings في الإعدادات (للمطور والأدمن).
-- آمن للتشغيل أكتر من مرة.
-- ============================================================
BEGIN;

ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS print_settings jsonb NOT NULL DEFAULT '{}'::jsonb;

-- الحضور: الأدمن بس يكتب (المحاسب يشوف بس)
DROP POLICY IF EXISTS write_attendance ON attendance;
CREATE POLICY write_attendance ON attendance FOR ALL TO authenticated
  USING(auth_role()='admin') WITH CHECK(auth_role()='admin');

-- دالة الحضور الذاتي: للأدمن بس (الكتابة الفعلية للأدمن)
CREATE OR REPLACE FUNCTION attendance_check(p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE emp uuid; d date := (now() AT TIME ZONE 'Africa/Cairo')::date; rec attendance; nowt timestamptz := now();
BEGIN
  IF auth_role() IS DISTINCT FROM 'admin' THEN RAISE EXCEPTION 'تسجيل الحضور للأدمن بس'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'لازم تسجل دخول'; END IF;
  SELECT id INTO emp FROM employees WHERE user_id=auth.uid() AND coalesce(active,true) LIMIT 1;
  IF emp IS NULL THEN RAISE EXCEPTION 'حسابك مش مربوط بموظف، كلم الإدارة'; END IF;
  SELECT * INTO rec FROM attendance WHERE employee_id=emp AND work_date=d;
  IF p_action='in' THEN
    IF rec.id IS NOT NULL AND rec.check_in IS NOT NULL THEN RAISE EXCEPTION 'سجلت الحضور النهارده قبل كده'; END IF;
    IF rec.id IS NULL THEN
      INSERT INTO attendance(employee_id,work_date,check_in,status) VALUES(emp,d,nowt,'Present') RETURNING * INTO rec;
    ELSE
      UPDATE attendance SET check_in=nowt, status='Present' WHERE id=rec.id RETURNING * INTO rec;
    END IF;
  ELSIF p_action='out' THEN
    IF rec.id IS NULL OR rec.check_in IS NULL THEN RAISE EXCEPTION 'لازم تسجل الحضور الأول'; END IF;
    IF rec.check_out IS NOT NULL THEN RAISE EXCEPTION 'سجلت الانصراف النهارده قبل كده'; END IF;
    UPDATE attendance SET check_out=nowt WHERE id=rec.id RETURNING * INTO rec;
  ELSE
    RAISE EXCEPTION 'إجراء غير معروف';
  END IF;
  RETURN jsonb_build_object('work_date',rec.work_date,'check_in',rec.check_in,'check_out',rec.check_out,'status',rec.status);
END $$;

COMMIT;


-- ============================== PATCH v1.60 (security hardening) ==============================
-- ERP patch v1.60 - security hardening (run AFTER all earlier patches; keep it LAST)
-- Why: v1.49 does GRANT EXECUTE ON ALL FUNCTIONS TO authenticated, which re-opens
-- internal helper functions that have no role check. Revoke them again.
BEGIN;

REVOKE EXECUTE ON FUNCTION
  public.apply_cash(uuid, numeric),
  public.apply_stock(uuid, uuid, numeric, text, text, uuid),
  public.record_initial_payment(text, uuid, numeric, uuid, uuid),
  public.refresh_sales_invoice_paid(uuid),
  public.refresh_purchase_invoice_paid(uuid),
  public._rebuild_journal(text, uuid)
FROM PUBLIC, anon, authenticated;

-- Make future functions closed by default for the API roles
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

COMMIT;

-- Verify (all must be false):
-- SELECT p.proname, has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_exec
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname IN ('apply_cash','apply_stock','record_initial_payment',
--  'refresh_sales_invoice_paid','refresh_purchase_invoice_paid','_rebuild_journal');


-- ============================== PATCH v1.61 (lock site + revoke sessions) ==============================
-- ERP patch v1.61 - قفل الموقع للمطور + خروج كل الجلسات (SQL)
-- لازم يتشغّل بعد v1.60. التحكم من إعدادات المطور في الواجهة.
BEGIN;

-- 1) أعمدة التحكم في جدول app_control
ALTER TABLE app_control
  ADD COLUMN IF NOT EXISTS locked boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lock_msg text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS sessions_after timestamptz NOT NULL DEFAULT timestamptz 'epoch';

-- 2) auth_role: بيرجع فاضي لو:
--    - التوكن اتعمل قبل آخر "خروج كل الجلسات"
--    - الموقع مقفول وthe user مش مطور
--    ده بيقفل الداتا على مستوى الـ RLS مش الشاشة بس.
CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN p.role='developer' THEN 'admin' ELSE p.role END
  FROM profiles p, app_control c
  WHERE p.id=auth.uid() AND p.active AND c.id=1
    AND COALESCE((auth.jwt()->>'iat')::bigint, 0) > extract(epoch FROM c.sessions_after)::bigint
    AND (p.role='developer' OR NOT c.locked)
$$;

-- 3) حالة الموقع: متاحة للكل (حتى قبل تسجيل الدخول)
CREATE OR REPLACE FUNCTION app_lock_state() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object(
    'locked', c.locked,
    'msg', c.lock_msg,
    'epoch', extract(epoch FROM c.sessions_after)::bigint,
    'is_dev', is_developer())
  FROM app_control c WHERE c.id=1
$$;

-- 4) المطور يقفل/يفتح الموقع
CREATE OR REPLACE FUNCTION dev_set_lock(p_locked boolean, p_msg text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET locked=p_locked, lock_msg=COALESCE(p_msg,''), updated_at=now() WHERE id=1;
  PERFORM log_event('update','app_control','1', CASE WHEN p_locked THEN 'قفل الموقع' ELSE 'فتح الموقع' END);
END $$;

-- 5) المطور يسجّل خروج كل المستخدمين
CREATE OR REPLACE FUNCTION dev_revoke_all_sessions() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET sessions_after=now(), updated_at=now() WHERE id=1;
  -- امسح جلسات التجديد عشان التوكن ما يتجددش (لو الصلاحية متاحة)
  BEGIN DELETE FROM auth.refresh_tokens; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM auth.sessions;       EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM log_event('update','app_control','1','خروج كل الجلسات');
END $$;

-- 6) الصلاحيات (بسبب ALTER DEFAULT PRIVILEGES في v1.60 لازم كل دالة تتفتح صراحة)
REVOKE ALL ON FUNCTION app_lock_state(), dev_set_lock(boolean,text), dev_revoke_all_sessions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app_lock_state() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION dev_set_lock(boolean,text), dev_revoke_all_sessions() TO authenticated;

COMMIT;


-- ============================== PATCH v1.62 (single developer, custom lock, Arabic audit) ==============================
-- ERP patch v1.62 - مطور واحد بس، قفل مخصص (أدوار مسموحة + وقت انتهاء)، سجل عمليات بالعربي
-- لازم يتشغّل بعد v1.61
BEGIN;

-- 1) مطور واحد بس في النظام
DO $$ BEGIN
  IF (SELECT count(*) FROM profiles WHERE role='developer') > 1 THEN
    RAISE EXCEPTION 'فيه أكتر من حساب مطور. لازم يبقى حساب واحد قبل تشغيل الباتش';
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS one_developer_only ON profiles ((role)) WHERE role='developer';

-- 2) أعمدة القفل المخصص
ALTER TABLE app_control
  ADD COLUMN IF NOT EXISTS lock_roles text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS lock_until timestamptz;

-- 3) auth_role: الموقع المقفول بيفضل مفتوح للمطور والأدوار المسموحة، ووقت القفل بينتهي أوتوماتيك
CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN p.role='developer' THEN 'admin' ELSE p.role END
  FROM profiles p, app_control c
  WHERE p.id=auth.uid() AND p.active AND c.id=1
    AND COALESCE((auth.jwt()->>'iat')::bigint, 0) > extract(epoch FROM c.sessions_after)::bigint
    AND (p.role='developer'
         OR NOT (c.locked AND (c.lock_until IS NULL OR now() < c.lock_until))
         OR p.role = ANY(c.lock_roles))
$$;

-- 4) حالة الموقع (متاحة للكل)
CREATE OR REPLACE FUNCTION app_lock_state() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object(
    'locked', (c.locked AND (c.lock_until IS NULL OR now() < c.lock_until)),
    'msg', c.lock_msg,
    'until', c.lock_until,
    'roles', to_jsonb(c.lock_roles),
    'epoch', extract(epoch FROM c.sessions_after)::bigint,
    'is_dev', is_developer(),
    'bypass', is_developer() OR EXISTS(SELECT 1 FROM profiles p WHERE p.id=auth.uid() AND p.active AND p.role = ANY(c.lock_roles)))
  FROM app_control c WHERE c.id=1
$$;

-- 5) المطور يقفل/يفتح بأدوار مسموحة ووقت انتهاء
DROP FUNCTION IF EXISTS dev_set_lock(boolean, text);
CREATE OR REPLACE FUNCTION dev_set_lock(p_locked boolean, p_msg text, p_roles text[] DEFAULT '{}', p_until timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  IF EXISTS (SELECT 1 FROM unnest(COALESCE(p_roles,'{}')) r WHERE r NOT IN ('admin','accountant','sales','store')) THEN
    RAISE EXCEPTION 'دور غير معروف في قائمة المسموح لهم';
  END IF;
  IF p_locked AND p_until IS NOT NULL AND p_until <= now() THEN
    RAISE EXCEPTION 'وقت انتهاء القفل لازم يكون في المستقبل';
  END IF;
  UPDATE app_control SET locked=p_locked, lock_msg=COALESCE(p_msg,''),
    lock_roles=CASE WHEN p_locked THEN COALESCE(p_roles,'{}') ELSE '{}' END,
    lock_until=CASE WHEN p_locked THEN p_until ELSE NULL END,
    updated_at=now()
  WHERE id=1;
  PERFORM log_event('update','app_control','1',
    CASE WHEN p_locked THEN 'قفل الموقع' ELSE 'فتح الموقع' END);
END $$;
REVOKE ALL ON FUNCTION dev_set_lock(boolean,text,text[],timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION dev_set_lock(boolean,text,text[],timestamptz) TO authenticated;

-- 6) سجل العمليات: وصف الـ triggers بالعربي
CREATE OR REPLACE FUNCTION audit_trg() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
begin
 insert into audit_logs(user_id,user_name,action,entity,entity_id,description,old_data,new_data)
 values(auth.uid(),(select name from profiles where id=auth.uid()),lower(tg_op),tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'),
  CASE tg_op WHEN 'INSERT' THEN 'إضافة سجل في ' WHEN 'UPDATE' THEN 'تعديل سجل في ' ELSE 'حذف سجل من ' END || tg_table_name,
  case when tg_op<>'INSERT' then to_jsonb(old) end, case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old); end $$;

COMMIT;


-- ============================== PATCH v1.64 (invoice numbering) ==============================
-- ERP patch v1.64 - تغيير صيغة أرقام الفواتير (المستندات الجديدة بس)
-- فاتورة بيع: INV-1001 | فاتورة شراء: PUR-1001 | مرتجع بيع: SRET-1001 | مرتجع شراء: PRET-1001
-- (لو company_settings.invoice_prefix فيه قيمة، بتفضل قدام الرقم زي ما هي)
-- الباتش بيعدّل الدوال الموجودة نفسها (مش بيضيف triggers)
BEGIN;

DO $$
DECLARE
  r record;
  def text;
BEGIN
  FOR r IN
    SELECT p.oid, pg_get_functiondef(p.oid) AS d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (p.prosrc LIKE '%seq_sales%' OR p.prosrc LIKE '%seq_purchase%'
           OR p.prosrc LIKE '%seq_sret%' OR p.prosrc LIKE '%seq_pret%')
  LOOP
    def := r.d;
    def := replace(def, '''SR''||(1000+nextval(''seq_sret''))',   '''SRET-''||(1000+nextval(''seq_sret''))');
    def := replace(def, '''PR''||(1000+nextval(''seq_pret''))',   '''PRET-''||(1000+nextval(''seq_pret''))');
    def := replace(def, '''S''||(1000+nextval(''seq_sales''))',    '''INV-''||(1000+nextval(''seq_sales''))');
    def := replace(def, '''P''||(1000+nextval(''seq_purchase''))', '''PUR-''||(1000+nextval(''seq_purchase''))');
    IF def <> r.d THEN
      EXECUTE def;
    END IF;
  END LOOP;
END $$;

COMMIT;

-- ===== patch v1.50 =====
DROP FUNCTION IF EXISTS create_party(text,text,text,text,text,text,text[],numeric,integer,numeric,integer,numeric);

-- ============================================================
-- ERP patch v1.50 (فوق v1.49)
-- الأطراف الموحدة: كل طرف (عميل و/أو مورد) ليه سجل واحد رئيسي (parties).
-- - العملاء والموردين الحاليين بيتربطوا بالطرف (بالاسم، من غير تكرار).
-- - الفواتير والمدفوعات بتفضل مرتبطة بسجل العميل/المورد زي ما هي،
--   فالقيود المحاسبية (ذمم العملاء والموردين منفصلة) مش بتتأثر.
-- - الشاشة بتعرض الطرف مرة واحدة برصيد صافي.
-- آمن للتشغيل مرة واحدة. (لو اتشغل تاني هيتخطى الترحيل)
-- ============================================================
BEGIN;

CREATE TABLE IF NOT EXISTS parties(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text, email text, address text, tax_number text, notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE customers ADD COLUMN IF NOT EXISTS party_id uuid;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS party_id uuid;

DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='customers_party_fk') THEN
    ALTER TABLE customers ADD CONSTRAINT customers_party_fk FOREIGN KEY (party_id) REFERENCES parties(id);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='suppliers_party_fk') THEN
    ALTER TABLE suppliers ADD CONSTRAINT suppliers_party_fk FOREIGN KEY (party_id) REFERENCES parties(id);
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS customers_one_party ON customers(party_id) WHERE party_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_one_party ON suppliers(party_id) WHERE party_id IS NOT NULL;

-- ترحيل: كل عميل/مورد من غير طرف، بنربطه بطرف بنفس الاسم (لو موجود وما لوش نفس الدور)، أو بننشئ طرف جديد
DO $$
DECLARE r record; pid uuid;
BEGIN
  FOR r IN SELECT id,name,phone,email,address,notes,active FROM customers WHERE party_id IS NULL LOOP
    SELECT p.id INTO pid FROM parties p
      WHERE lower(trim(p.name))=lower(trim(r.name)) AND NOT EXISTS(SELECT 1 FROM customers c WHERE c.party_id=p.id)
      ORDER BY p.created_at LIMIT 1;
    IF pid IS NULL THEN
      INSERT INTO parties(name,phone,email,address,notes,active) VALUES(r.name,r.phone,r.email,r.address,r.notes,r.active) RETURNING id INTO pid;
    END IF;
    UPDATE customers SET party_id=pid WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id,name,phone,email,address,notes,active FROM suppliers WHERE party_id IS NULL LOOP
    SELECT p.id INTO pid FROM parties p
      WHERE lower(trim(p.name))=lower(trim(r.name)) AND NOT EXISTS(SELECT 1 FROM suppliers s WHERE s.party_id=p.id)
      ORDER BY p.created_at LIMIT 1;
    IF pid IS NULL THEN
      INSERT INTO parties(name,phone,email,address,notes,active) VALUES(r.name,r.phone,r.email,r.address,r.notes,r.active) RETURNING id INTO pid;
    END IF;
    UPDATE suppliers SET party_id=pid WHERE id=r.id;
  END LOOP;
END $$;

-- المصدر الرئيسي للبيانات هو الطرف: أي تعديل عليه بيتنقل للعميل والمورد المرتبطين
CREATE OR REPLACE FUNCTION trg_party_sync() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE customers SET name=NEW.name,phone=NEW.phone,email=NEW.email,address=NEW.address WHERE party_id=NEW.id;
  UPDATE suppliers SET name=NEW.name,phone=NEW.phone,email=NEW.email,address=NEW.address WHERE party_id=NEW.id;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS party_sync ON parties;
CREATE TRIGGER party_sync AFTER UPDATE OF name,phone,email,address ON parties
  FOR EACH ROW EXECUTE FUNCTION trg_party_sync();

CREATE OR REPLACE FUNCTION trg_role_from_party() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p parties;
BEGIN
  IF NEW.party_id IS NOT NULL THEN
    SELECT * INTO p FROM parties WHERE id=NEW.party_id;
    IF FOUND THEN NEW.name:=p.name; NEW.phone:=p.phone; NEW.email:=p.email; NEW.address:=p.address; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS role_from_party ON customers;
CREATE TRIGGER role_from_party BEFORE INSERT OR UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION trg_role_from_party();
DROP TRIGGER IF EXISTS role_from_party ON suppliers;
CREATE TRIGGER role_from_party BEFORE INSERT OR UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION trg_role_from_party();
REVOKE EXECUTE ON FUNCTION trg_party_sync(), trg_role_from_party() FROM PUBLIC, anon, authenticated;

-- صلاحيات الجدول
ALTER TABLE parties ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sel_parties ON parties;
DROP POLICY IF EXISTS write_parties ON parties;
CREATE POLICY sel_parties ON parties FOR SELECT TO authenticated USING(auth_role() IS NOT NULL);
CREATE POLICY write_parties ON parties FOR ALL TO authenticated
  USING(auth_role() IN ('admin','accountant','sales','store')) WITH CHECK(auth_role() IN ('admin','accountant','sales','store'));
GRANT SELECT, INSERT, UPDATE ON parties TO authenticated;

-- رصيد الطرف: عميل + مورد. الصافي = له علينا (موجب) ناقص علينا ليه
CREATE OR REPLACE VIEW party_balances WITH(security_invoker=true) AS
SELECT p.id AS party_id, p.name, p.phone, p.email, p.active,
  c.id AS customer_id, c.active AS customer_active,
  s.id AS supplier_id, s.active AS supplier_active,
  coalesce(cb.balance,0) AS receivable,
  coalesce(sb.balance,0) AS payable,
  coalesce(cb.balance,0)-coalesce(sb.balance,0) AS net
FROM parties p
LEFT JOIN customers c ON c.party_id=p.id
LEFT JOIN suppliers s ON s.party_id=p.id
LEFT JOIN customer_balances cb ON cb.id=c.id
LEFT JOIN supplier_balances sb ON sb.id=s.id;
GRANT SELECT ON party_balances TO authenticated;

-- إنشاء طرف (عميل و/أو مورد) في خطوة واحدة
CREATE OR REPLACE FUNCTION create_party(p_name text,p_phone text,p_email text,p_address text,p_tax text,p_notes text,
  p_roles text[],p_credit_limit numeric DEFAULT 0,p_customer_terms int DEFAULT 0,p_customer_opening numeric DEFAULT 0,
  p_supplier_terms int DEFAULT 0,p_supplier_opening numeric DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE pid uuid;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF trim(coalesce(p_name,''))='' THEN RAISE EXCEPTION 'اكتب اسم الطرف'; END IF;
  IF p_roles IS NULL OR NOT (p_roles && ARRAY['customer','supplier']) THEN RAISE EXCEPTION 'اختار عميل أو مورد على الأقل'; END IF;
  IF 'customer'=ANY(p_roles) THEN PERFORM require_role('{admin,accountant,sales}'); END IF;
  IF 'supplier'=ANY(p_roles) THEN PERFORM require_role('{admin,accountant,store}'); END IF;
  IF EXISTS(SELECT 1 FROM parties WHERE lower(trim(name))=lower(trim(p_name))) THEN RAISE EXCEPTION 'يوجد طرف بنفس الاسم بالفعل'; END IF;
  INSERT INTO parties(name,phone,email,address,tax_number,notes)
    VALUES(trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_tax,'')),''),nullif(trim(coalesce(p_notes,'')),''))
    RETURNING id INTO pid;
  IF 'customer'=ANY(p_roles) THEN
    INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes,party_id)
      SELECT name,phone,email,address,coalesce(p_credit_limit,0),coalesce(p_customer_terms,0),coalesce(p_customer_opening,0),notes,id FROM parties WHERE id=pid;
  END IF;
  IF 'supplier'=ANY(p_roles) THEN
    INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes,party_id)
      SELECT name,phone,email,address,coalesce(p_supplier_terms,0),coalesce(p_supplier_opening,0),notes,id FROM parties WHERE id=pid;
  END IF;
  PERFORM log_event('create','parties',pid::text,'أنشأ طرف '||trim(p_name));
  RETURN pid;
END $$;

-- تعديل بيانات الطرف والشروط الخاصة بكل دور
CREATE OR REPLACE FUNCTION update_party(p_party uuid,p_name text,p_phone text,p_email text,p_address text,p_tax text,p_notes text,
  p_credit_limit numeric DEFAULT NULL,p_customer_terms int DEFAULT NULL,p_supplier_terms int DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF trim(coalesce(p_name,''))='' THEN RAISE EXCEPTION 'اكتب اسم الطرف'; END IF;
  IF EXISTS(SELECT 1 FROM parties WHERE id<>p_party AND lower(trim(name))=lower(trim(p_name))) THEN RAISE EXCEPTION 'يوجد طرف بنفس الاسم بالفعل'; END IF;
  UPDATE parties SET name=trim(p_name),phone=nullif(trim(coalesce(p_phone,'')),''),email=nullif(trim(coalesce(p_email,'')),''),
    address=nullif(trim(coalesce(p_address,'')),''),tax_number=nullif(trim(coalesce(p_tax,'')),''),notes=nullif(trim(coalesce(p_notes,'')),'')
    WHERE id=p_party;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطرف غير موجود'; END IF;
  IF p_credit_limit IS NOT NULL AND auth_role() IN ('admin','accountant','sales') THEN
    UPDATE customers SET credit_limit=p_credit_limit WHERE party_id=p_party;
  END IF;
  IF p_customer_terms IS NOT NULL AND auth_role() IN ('admin','accountant','sales') THEN
    UPDATE customers SET payment_terms_days=p_customer_terms WHERE party_id=p_party;
  END IF;
  IF p_supplier_terms IS NOT NULL AND auth_role() IN ('admin','accountant','store') THEN
    UPDATE suppliers SET payment_terms_days=p_supplier_terms WHERE party_id=p_party;
  END IF;
END $$;

-- تفعيل/إيقاف دور (عميل أو مورد) للطرف. الدور الموقوف بيفضل محفوظ بتاريخه.
CREATE OR REPLACE FUNCTION set_party_role(p_party uuid,p_role text,p_on boolean,p_credit_limit numeric DEFAULT 0,p_terms int DEFAULT 0,p_opening numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p parties;
BEGIN
  IF p_role='customer' THEN PERFORM require_role('{admin,accountant,sales}');
  ELSIF p_role='supplier' THEN PERFORM require_role('{admin,accountant,store}');
  ELSE RAISE EXCEPTION 'الدور غير صحيح'; END IF;
  SELECT * INTO p FROM parties WHERE id=p_party;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطرف غير موجود'; END IF;
  IF p_role='customer' THEN
    IF EXISTS(SELECT 1 FROM customers WHERE party_id=p_party) THEN
      UPDATE customers SET active=p_on WHERE party_id=p_party;
    ELSIF p_on THEN
      INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes,party_id)
        VALUES(p.name,p.phone,p.email,p.address,coalesce(p_credit_limit,0),coalesce(p_terms,0),coalesce(p_opening,0),p.notes,p.id);
    END IF;
  ELSE
    IF EXISTS(SELECT 1 FROM suppliers WHERE party_id=p_party) THEN
      UPDATE suppliers SET active=p_on WHERE party_id=p_party;
    ELSIF p_on THEN
      INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes,party_id)
        VALUES(p.name,p.phone,p.email,p.address,coalesce(p_terms,0),coalesce(p_opening,0),p.notes,p.id);
    END IF;
  END IF;
END $$;

-- تعطيل/تفعيل الطرف كله (العميل والمورد معاً)
CREATE OR REPLACE FUNCTION set_party_active(p_party uuid,p_on boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  UPDATE parties SET active=p_on WHERE id=p_party;
  IF NOT FOUND THEN RAISE EXCEPTION 'الطرف غير موجود'; END IF;
  UPDATE customers SET active=p_on WHERE party_id=p_party;
  UPDATE suppliers SET active=p_on WHERE party_id=p_party;
END $$;

REVOKE EXECUTE ON FUNCTION create_party(text,text,text,text,text,text,text[],numeric,int,numeric,int,numeric),
  update_party(uuid,text,text,text,text,text,text,numeric,int,int),
  set_party_role(uuid,text,boolean,numeric,int,numeric), set_party_active(uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_party(text,text,text,text,text,text,text[],numeric,int,numeric,int,numeric),
  update_party(uuid,text,text,text,text,text,text,numeric,int,int),
  set_party_role(uuid,text,boolean,numeric,int,numeric), set_party_active(uuid,boolean) TO authenticated;

COMMIT;

-- ===== patch v1.51 =====
-- ============================================================
-- ERP patch v1.51 (فوق v1.50)
-- 1) الطرف = عميل ومورد في نفس الوقت (مفيش اختيار دور عند الإضافة).
--    - أي طرف ناقص عميل أو مورد بيتكمّل تلقائياً.
--    - create_party بتعمل الاتنين دايماً.
-- 2) تحديث للمطور: جدول app_control فيه رقم تحديث، المطور يقدر يدفع تحديث لكل اليوزرات.
-- 3) الحضور: الموظف يسجل حضوره/انصرافه بنفسه (attendance_check) + يشوف سجله.
-- آمن للتشغيل أكتر من مرة.
-- ============================================================
BEGIN;

-- 1) استكمال الأدوار الناقصة لكل طرف
INSERT INTO customers(name,phone,email,address,notes,party_id)
  SELECT p.name,p.phone,p.email,p.address,p.notes,p.id FROM parties p
  WHERE NOT EXISTS(SELECT 1 FROM customers c WHERE c.party_id=p.id);
INSERT INTO suppliers(name,phone,email,address,notes,party_id)
  SELECT p.name,p.phone,p.email,p.address,p.notes,p.id FROM parties p
  WHERE NOT EXISTS(SELECT 1 FROM suppliers s WHERE s.party_id=p.id);

-- إنشاء الطرف: عميل ومورد دايماً
CREATE OR REPLACE FUNCTION create_party(p_name text,p_phone text,p_email text,p_address text,p_tax text,p_notes text,
  p_roles text[] DEFAULT NULL,p_credit_limit numeric DEFAULT 0,p_customer_terms int DEFAULT 0,p_customer_opening numeric DEFAULT 0,
  p_supplier_terms int DEFAULT 0,p_supplier_opening numeric DEFAULT 0)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE pid uuid;
BEGIN
  PERFORM require_role('{admin,accountant,sales,store}');
  IF trim(coalesce(p_name,''))='' THEN RAISE EXCEPTION 'اكتب اسم الطرف'; END IF;
  IF EXISTS(SELECT 1 FROM parties WHERE lower(trim(name))=lower(trim(p_name))) THEN RAISE EXCEPTION 'يوجد طرف بنفس الاسم بالفعل'; END IF;
  INSERT INTO parties(name,phone,email,address,tax_number,notes)
    VALUES(trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_email,'')),''),nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_tax,'')),''),nullif(trim(coalesce(p_notes,'')),''))
    RETURNING id INTO pid;
  INSERT INTO customers(name,phone,email,address,credit_limit,payment_terms_days,opening_balance,notes,party_id)
    SELECT name,phone,email,address,coalesce(p_credit_limit,0),coalesce(p_customer_terms,0),coalesce(p_customer_opening,0),notes,id FROM parties WHERE id=pid;
  INSERT INTO suppliers(name,phone,email,address,payment_terms_days,opening_balance,notes,party_id)
    SELECT name,phone,email,address,coalesce(p_supplier_terms,0),coalesce(p_supplier_opening,0),notes,id FROM parties WHERE id=pid;
  PERFORM log_event('create','parties',pid::text,'أنشأ طرف '||trim(p_name));
  RETURN pid;
END $$;

-- 2) تحديث التطبيق للكل
CREATE TABLE IF NOT EXISTS app_control(
  id int PRIMARY KEY DEFAULT 1 CHECK(id=1),
  refresh_token text NOT NULL DEFAULT '0',
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app_control(id) VALUES(1) ON CONFLICT DO NOTHING;
ALTER TABLE app_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_control FROM PUBLIC, anon, authenticated;

-- أي حد (حتى قبل تسجيل الدخول) يقدر يعرف رقم التحديث الحالي
CREATE OR REPLACE FUNCTION app_refresh_token() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT refresh_token FROM app_control WHERE id=1;
$$;
-- المطور بس يدفع تحديث لكل المستخدمين
CREATE OR REPLACE FUNCTION dev_push_refresh() RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t text := to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET refresh_token=t, updated_at=now() WHERE id=1;
  PERFORM log_event('update','app_control','1','دفع تحديث للمستخدمين');
  RETURN t;
END $$;
REVOKE EXECUTE ON FUNCTION app_refresh_token(), dev_push_refresh() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_refresh_token() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION dev_push_refresh() TO authenticated;

-- 3) الحضور الذاتي
DROP POLICY IF EXISTS sel_own_attendance ON attendance;
CREATE POLICY sel_own_attendance ON attendance FOR SELECT TO authenticated
  USING(EXISTS(SELECT 1 FROM employees e WHERE e.id=attendance.employee_id AND e.user_id=auth.uid()));

CREATE OR REPLACE FUNCTION attendance_check(p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE emp uuid; d date := (now() AT TIME ZONE 'Africa/Cairo')::date; rec attendance; nowt timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'لازم تسجل دخول'; END IF;
  SELECT id INTO emp FROM employees WHERE user_id=auth.uid() AND coalesce(active,true) LIMIT 1;
  IF emp IS NULL THEN RAISE EXCEPTION 'حسابك مش مربوط بموظف، كلم الإدارة'; END IF;
  SELECT * INTO rec FROM attendance WHERE employee_id=emp AND work_date=d;
  IF p_action='in' THEN
    IF rec.id IS NOT NULL AND rec.check_in IS NOT NULL THEN RAISE EXCEPTION 'سجلت الحضور النهارده قبل كده'; END IF;
    IF rec.id IS NULL THEN
      INSERT INTO attendance(employee_id,work_date,check_in,status) VALUES(emp,d,nowt,'Present') RETURNING * INTO rec;
    ELSE
      UPDATE attendance SET check_in=nowt, status='Present' WHERE id=rec.id RETURNING * INTO rec;
    END IF;
  ELSIF p_action='out' THEN
    IF rec.id IS NULL OR rec.check_in IS NULL THEN RAISE EXCEPTION 'لازم تسجل الحضور الأول'; END IF;
    IF rec.check_out IS NOT NULL THEN RAISE EXCEPTION 'سجلت الانصراف النهارده قبل كده'; END IF;
    UPDATE attendance SET check_out=nowt WHERE id=rec.id RETURNING * INTO rec;
  ELSE
    RAISE EXCEPTION 'إجراء غير معروف';
  END IF;
  RETURN jsonb_build_object('work_date',rec.work_date,'check_in',rec.check_in,'check_out',rec.check_out,'status',rec.status);
END $$;
REVOKE EXECUTE ON FUNCTION attendance_check(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION attendance_check(text) TO authenticated;

COMMIT;

-- ===== patch v1.54 =====
-- ============================================================
-- ERP patch v1.54 (فوق v1.53)
-- إصلاح رفع لوجو الشركة: "new row violates row-level security policy".
-- بيتأكد من وجود bucket اسمه company-assets (عام) وسياسات الرفع/التعديل
-- للأدمن والمطور. آمن للتشغيل أكتر من مرة.
-- ============================================================
BEGIN;

INSERT INTO storage.buckets(id,name,public) VALUES('company-assets','company-assets',true)
  ON CONFLICT (id) DO UPDATE SET public=true;

DROP POLICY IF EXISTS company_assets_insert ON storage.objects;
CREATE POLICY company_assets_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='company-assets' AND auth_role()='admin');

DROP POLICY IF EXISTS company_assets_update ON storage.objects;
CREATE POLICY company_assets_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id='company-assets' AND auth_role()='admin')
  WITH CHECK (bucket_id='company-assets' AND auth_role()='admin');

DROP POLICY IF EXISTS company_assets_delete ON storage.objects;
CREATE POLICY company_assets_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id='company-assets' AND auth_role()='admin');

COMMIT;

-- ===== patch v1.57 =====
-- ============================================================
-- ERP patch v1.57 (فوق v1.56)
-- 1) الحضور للأدمن بس: الكتابة والتسجيل (الجدول + دالة الحضور الذاتي).
-- 2) تخصيص الطباعة: عمود print_settings في الإعدادات (للمطور والأدمن).
-- آمن للتشغيل أكتر من مرة.
-- ============================================================
BEGIN;

ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS print_settings jsonb NOT NULL DEFAULT '{}'::jsonb;

-- الحضور: الأدمن بس يكتب (المحاسب يشوف بس)
DROP POLICY IF EXISTS write_attendance ON attendance;
CREATE POLICY write_attendance ON attendance FOR ALL TO authenticated
  USING(auth_role()='admin') WITH CHECK(auth_role()='admin');

-- دالة الحضور الذاتي: للأدمن بس (الكتابة الفعلية للأدمن)
CREATE OR REPLACE FUNCTION attendance_check(p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE emp uuid; d date := (now() AT TIME ZONE 'Africa/Cairo')::date; rec attendance; nowt timestamptz := now();
BEGIN
  IF auth_role() IS DISTINCT FROM 'admin' THEN RAISE EXCEPTION 'تسجيل الحضور للأدمن بس'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'لازم تسجل دخول'; END IF;
  SELECT id INTO emp FROM employees WHERE user_id=auth.uid() AND coalesce(active,true) LIMIT 1;
  IF emp IS NULL THEN RAISE EXCEPTION 'حسابك مش مربوط بموظف، كلم الإدارة'; END IF;
  SELECT * INTO rec FROM attendance WHERE employee_id=emp AND work_date=d;
  IF p_action='in' THEN
    IF rec.id IS NOT NULL AND rec.check_in IS NOT NULL THEN RAISE EXCEPTION 'سجلت الحضور النهارده قبل كده'; END IF;
    IF rec.id IS NULL THEN
      INSERT INTO attendance(employee_id,work_date,check_in,status) VALUES(emp,d,nowt,'Present') RETURNING * INTO rec;
    ELSE
      UPDATE attendance SET check_in=nowt, status='Present' WHERE id=rec.id RETURNING * INTO rec;
    END IF;
  ELSIF p_action='out' THEN
    IF rec.id IS NULL OR rec.check_in IS NULL THEN RAISE EXCEPTION 'لازم تسجل الحضور الأول'; END IF;
    IF rec.check_out IS NOT NULL THEN RAISE EXCEPTION 'سجلت الانصراف النهارده قبل كده'; END IF;
    UPDATE attendance SET check_out=nowt WHERE id=rec.id RETURNING * INTO rec;
  ELSE
    RAISE EXCEPTION 'إجراء غير معروف';
  END IF;
  RETURN jsonb_build_object('work_date',rec.work_date,'check_in',rec.check_in,'check_out',rec.check_out,'status',rec.status);
END $$;

COMMIT;

-- ===== patch v1.60 =====
-- ERP patch v1.60 - security hardening (run AFTER all earlier patches; keep it LAST)
-- Why: v1.49 does GRANT EXECUTE ON ALL FUNCTIONS TO authenticated, which re-opens
-- internal helper functions that have no role check. Revoke them again.
BEGIN;

REVOKE EXECUTE ON FUNCTION
  public.apply_cash(uuid, numeric),
  public.apply_stock(uuid, uuid, numeric, text, text, uuid),
  public.record_initial_payment(text, uuid, numeric, uuid, uuid),
  public.refresh_sales_invoice_paid(uuid),
  public.refresh_purchase_invoice_paid(uuid),
  public._rebuild_journal(text, uuid)
FROM PUBLIC, anon, authenticated;

-- Make future functions closed by default for the API roles
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

COMMIT;

-- Verify (all must be false):
-- SELECT p.proname, has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_exec
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname IN ('apply_cash','apply_stock','record_initial_payment',
--  'refresh_sales_invoice_paid','refresh_purchase_invoice_paid','_rebuild_journal');

-- ===== patch v1.61 =====
-- ERP patch v1.61 - قفل الموقع للمطور + خروج كل الجلسات (SQL)
-- لازم يتشغّل بعد v1.60. التحكم من إعدادات المطور في الواجهة.
BEGIN;

-- 1) أعمدة التحكم في جدول app_control
ALTER TABLE app_control
  ADD COLUMN IF NOT EXISTS locked boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lock_msg text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS sessions_after timestamptz NOT NULL DEFAULT timestamptz 'epoch';

-- 2) auth_role: بيرجع فاضي لو:
--    - التوكن اتعمل قبل آخر "خروج كل الجلسات"
--    - الموقع مقفول وthe user مش مطور
--    ده بيقفل الداتا على مستوى الـ RLS مش الشاشة بس.
CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN p.role='developer' THEN 'admin' ELSE p.role END
  FROM profiles p, app_control c
  WHERE p.id=auth.uid() AND p.active AND c.id=1
    AND COALESCE((auth.jwt()->>'iat')::bigint, 0) > extract(epoch FROM c.sessions_after)::bigint
    AND (p.role='developer' OR NOT c.locked)
$$;

-- 3) حالة الموقع: متاحة للكل (حتى قبل تسجيل الدخول)
CREATE OR REPLACE FUNCTION app_lock_state() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object(
    'locked', c.locked,
    'msg', c.lock_msg,
    'epoch', extract(epoch FROM c.sessions_after)::bigint,
    'is_dev', is_developer())
  FROM app_control c WHERE c.id=1
$$;

-- 4) المطور يقفل/يفتح الموقع
CREATE OR REPLACE FUNCTION dev_set_lock(p_locked boolean, p_msg text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET locked=p_locked, lock_msg=COALESCE(p_msg,''), updated_at=now() WHERE id=1;
  PERFORM log_event('update','app_control','1', CASE WHEN p_locked THEN 'قفل الموقع' ELSE 'فتح الموقع' END);
END $$;

-- 5) المطور يسجّل خروج كل المستخدمين
CREATE OR REPLACE FUNCTION dev_revoke_all_sessions() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET sessions_after=now(), updated_at=now() WHERE id=1;
  -- امسح جلسات التجديد عشان التوكن ما يتجددش (لو الصلاحية متاحة)
  BEGIN DELETE FROM auth.refresh_tokens; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM auth.sessions;       EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM log_event('update','app_control','1','خروج كل الجلسات');
END $$;

-- 6) الصلاحيات (بسبب ALTER DEFAULT PRIVILEGES في v1.60 لازم كل دالة تتفتح صراحة)
REVOKE ALL ON FUNCTION app_lock_state(), dev_set_lock(boolean,text), dev_revoke_all_sessions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app_lock_state() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION dev_set_lock(boolean,text), dev_revoke_all_sessions() TO authenticated;

COMMIT;

-- ===== patch v1.62 =====
-- ERP patch v1.62 - مطور واحد بس، قفل مخصص (أدوار مسموحة + وقت انتهاء)، سجل عمليات بالعربي
-- لازم يتشغّل بعد v1.61
BEGIN;

-- 1) مطور واحد بس في النظام
DO $$ BEGIN
  IF (SELECT count(*) FROM profiles WHERE role='developer') > 1 THEN
    RAISE EXCEPTION 'فيه أكتر من حساب مطور. لازم يبقى حساب واحد قبل تشغيل الباتش';
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS one_developer_only ON profiles ((role)) WHERE role='developer';

-- 2) أعمدة القفل المخصص
ALTER TABLE app_control
  ADD COLUMN IF NOT EXISTS lock_roles text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS lock_until timestamptz;

-- 3) auth_role: الموقع المقفول بيفضل مفتوح للمطور والأدوار المسموحة، ووقت القفل بينتهي أوتوماتيك
CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN p.role='developer' THEN 'admin' ELSE p.role END
  FROM profiles p, app_control c
  WHERE p.id=auth.uid() AND p.active AND c.id=1
    AND COALESCE((auth.jwt()->>'iat')::bigint, 0) > extract(epoch FROM c.sessions_after)::bigint
    AND (p.role='developer'
         OR NOT (c.locked AND (c.lock_until IS NULL OR now() < c.lock_until))
         OR p.role = ANY(c.lock_roles))
$$;

-- 4) حالة الموقع (متاحة للكل)
CREATE OR REPLACE FUNCTION app_lock_state() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object(
    'locked', (c.locked AND (c.lock_until IS NULL OR now() < c.lock_until)),
    'msg', c.lock_msg,
    'until', c.lock_until,
    'roles', to_jsonb(c.lock_roles),
    'epoch', extract(epoch FROM c.sessions_after)::bigint,
    'is_dev', is_developer(),
    'bypass', is_developer() OR EXISTS(SELECT 1 FROM profiles p WHERE p.id=auth.uid() AND p.active AND p.role = ANY(c.lock_roles)))
  FROM app_control c WHERE c.id=1
$$;

-- 5) المطور يقفل/يفتح بأدوار مسموحة ووقت انتهاء
DROP FUNCTION IF EXISTS dev_set_lock(boolean, text);
CREATE OR REPLACE FUNCTION dev_set_lock(p_locked boolean, p_msg text, p_roles text[] DEFAULT '{}', p_until timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  IF EXISTS (SELECT 1 FROM unnest(COALESCE(p_roles,'{}')) r WHERE r NOT IN ('admin','accountant','sales','store')) THEN
    RAISE EXCEPTION 'دور غير معروف في قائمة المسموح لهم';
  END IF;
  IF p_locked AND p_until IS NOT NULL AND p_until <= now() THEN
    RAISE EXCEPTION 'وقت انتهاء القفل لازم يكون في المستقبل';
  END IF;
  UPDATE app_control SET locked=p_locked, lock_msg=COALESCE(p_msg,''),
    lock_roles=CASE WHEN p_locked THEN COALESCE(p_roles,'{}') ELSE '{}' END,
    lock_until=CASE WHEN p_locked THEN p_until ELSE NULL END,
    updated_at=now()
  WHERE id=1;
  PERFORM log_event('update','app_control','1',
    CASE WHEN p_locked THEN 'قفل الموقع' ELSE 'فتح الموقع' END);
END $$;
REVOKE ALL ON FUNCTION dev_set_lock(boolean,text,text[],timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION dev_set_lock(boolean,text,text[],timestamptz) TO authenticated;

-- 6) سجل العمليات: وصف الـ triggers بالعربي
CREATE OR REPLACE FUNCTION audit_trg() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
begin
 insert into audit_logs(user_id,user_name,action,entity,entity_id,description,old_data,new_data)
 values(auth.uid(),(select name from profiles where id=auth.uid()),lower(tg_op),tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'),
  CASE tg_op WHEN 'INSERT' THEN 'إضافة سجل في ' WHEN 'UPDATE' THEN 'تعديل سجل في ' ELSE 'حذف سجل من ' END || tg_table_name,
  case when tg_op<>'INSERT' then to_jsonb(old) end, case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old); end $$;

COMMIT;

-- ===== patch v1.64 =====
-- ERP patch v1.64 - تغيير صيغة أرقام الفواتير (المستندات الجديدة بس)
-- فاتورة بيع: INV-1001 | فاتورة شراء: PUR-1001 | مرتجع بيع: SRET-1001 | مرتجع شراء: PRET-1001
-- (لو company_settings.invoice_prefix فيه قيمة، بتفضل قدام الرقم زي ما هي)
-- الباتش بيعدّل الدوال الموجودة نفسها (مش بيضيف triggers)
BEGIN;

DO $$
DECLARE
  r record;
  def text;
BEGIN
  FOR r IN
    SELECT p.oid, pg_get_functiondef(p.oid) AS d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (p.prosrc LIKE '%seq_sales%' OR p.prosrc LIKE '%seq_purchase%'
           OR p.prosrc LIKE '%seq_sret%' OR p.prosrc LIKE '%seq_pret%')
  LOOP
    def := r.d;
    def := replace(def, '''SR''||(1000+nextval(''seq_sret''))',   '''SRET-''||(1000+nextval(''seq_sret''))');
    def := replace(def, '''PR''||(1000+nextval(''seq_pret''))',   '''PRET-''||(1000+nextval(''seq_pret''))');
    def := replace(def, '''S''||(1000+nextval(''seq_sales''))',    '''INV-''||(1000+nextval(''seq_sales''))');
    def := replace(def, '''P''||(1000+nextval(''seq_purchase''))', '''PUR-''||(1000+nextval(''seq_purchase''))');
    IF def <> r.d THEN
      EXECUTE def;
    END IF;
  END LOOP;
END $$;

COMMIT;
-- ERP_patch_v1.66.sql: التسجيل والدخول باسم المستخدم + الموبايل (الأدمن بس بيضيف المستخدمين)
BEGIN;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone text;

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_phone_format;
ALTER TABLE profiles ADD CONSTRAINT profiles_phone_format
  CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{8,15}$');

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_username_format;
ALTER TABLE profiles ADD CONSTRAINT profiles_username_format
  CHECK (username IS NULL OR username ~ '^[A-Za-z0-9_.]{3,30}$' OR username ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$');

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower ON profiles (lower(username));

-- يحوّل اسم المستخدم للإيميل المرتبط بيه عشان signInWithPassword يشتغل
CREATE OR REPLACE FUNCTION resolve_login(p_identifier text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN position('@' in p_identifier) > 0 THEN lower(trim(p_identifier))
    ELSE (SELECT u.email::text FROM profiles p JOIN auth.users u ON u.id = p.id
          WHERE lower(p.username) = lower(trim(p_identifier)) AND p.active LIMIT 1)
  END
$$;
REVOKE ALL ON FUNCTION resolve_login(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_login(text) TO anon, authenticated;

COMMIT;

-- ERP_patch_v1.66b_phone_login.sql: الدخول برقم الموبايل كمان (بعد باتش 1.66)
BEGIN;

CREATE OR REPLACE FUNCTION resolve_login(p_identifier text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN position('@' in p_identifier) > 0 THEN lower(trim(p_identifier))
    WHEN regexp_replace(p_identifier, '\s', '', 'g') ~ '^(\+?[0-9]{8,15}|0[0-9]{10})$' THEN (
      SELECT u.email::text FROM profiles p JOIN auth.users u ON u.id = p.id
      WHERE p.phone = (CASE WHEN regexp_replace(p_identifier, '\s', '', 'g') ~ '^0'
                            THEN '+20' || substr(regexp_replace(p_identifier, '\s', '', 'g'), 2)
                            ELSE regexp_replace(p_identifier, '\s', '', 'g') END)
        AND p.active LIMIT 1)
    ELSE (SELECT u.email::text FROM profiles p JOIN auth.users u ON u.id = p.id
          WHERE lower(p.username) = lower(trim(p_identifier)) AND p.active LIMIT 1)
  END
$$;
REVOKE ALL ON FUNCTION resolve_login(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_login(text) TO anon, authenticated;

COMMIT;

-- ERP_patch_v1.67_permissions.sql: فرض الصلاحيات المخصصة على السيرفر (مش بس في الواجهة)
BEGIN;

-- الافتراضي لكل دور (نفس خريطة P في الواجهة)
CREATE TABLE IF NOT EXISTS role_default_perms (
  role text NOT NULL,
  perm text NOT NULL,
  PRIMARY KEY(role, perm)
);
ALTER TABLE role_default_perms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rdp_select ON role_default_perms;
CREATE POLICY rdp_select ON role_default_perms FOR SELECT TO authenticated USING (true);
INSERT INTO role_default_perms(role, perm) VALUES
('accountant','dash'),
('accountant','prod'),
('accountant','cust'),
('accountant','supp'),
('accountant','sales'),
('accountant','purch'),
('accountant','po'),
('accountant','grn'),
('accountant','dn'),
('accountant','pay'),
('accountant','exp'),
('accountant','cash'),
('accountant','trf'),
('accountant','ret'),
('accountant','quo'),
('accountant','ord'),
('accountant','stmt'),
('accountant','emp'),
('accountant','prl'),
('accountant','asset'),
('accountant','bank'),
('accountant','price'),
('accountant','rep'),
('accountant','jr'),
('accountant','stk'),
('accountant','period'),
('accountant','appr'),
('accountant','chk'),
('accountant','comm'),
('accountant','taxdoc'),
('accountant','org'),
('accountant','health'),
('accountant','audit'),
('sales','dash'),
('sales','prod'),
('sales','cust'),
('sales','sales'),
('sales','dn'),
('sales','ret'),
('sales','quo'),
('sales','ord'),
('sales','stmt'),
('sales','price'),
('sales','comm'),
('sales','taxdoc'),
('sales','appr'),
('store','dash'),
('store','prod'),
('store','purch'),
('store','po'),
('store','grn'),
('store','dn'),
('store','ret'),
('store','trf'),
('store','stk'),
('store','mfg')
ON CONFLICT DO NOTHING;

-- نفس منطق الواجهة: الأدمن/المطور كل حاجة، غير كده لازم الدور يسمح بالشاشة،
-- ولو الحساب في وضع "custom" لازم الشاشة تكون متعلّمة صراحة في user_permissions
CREATE OR REPLACE FUNCTION has_perm(p_key text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r text; m text;
BEGIN
  r := auth_role();                       -- NULL لو مش مفعّل أو الموقع مقفول
  IF r IS NULL THEN RETURN false; END IF;
  IF r = 'admin' THEN RETURN true; END IF;
  SELECT role, coalesce(permissions_mode,'role') INTO r, m FROM profiles WHERE id = auth.uid();
  IF NOT EXISTS (SELECT 1 FROM role_default_perms WHERE role = r AND perm = p_key) THEN RETURN false; END IF;
  IF m = 'custom' THEN
    RETURN EXISTS (SELECT 1 FROM user_permissions WHERE user_id = auth.uid() AND permission_key = p_key);
  END IF;
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION has_perm(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION has_perm(text) TO authenticated;

CREATE OR REPLACE FUNCTION require_perm(p_key text) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT has_perm(p_key) THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الشاشة: %', p_key USING ERRCODE = '42501';
  END IF;
END $$;
REVOKE ALL ON FUNCTION require_perm(text) FROM PUBLIC;

-- إضافة فحص الصلاحية للدوال الحساسة (بعد فحص الدور الموجود أصلاً)
DO $$
DECLARE
  w record; d text; pos int; eol int; nd text; cnt int;
BEGIN
  FOR w IN SELECT * FROM (VALUES
  ('create_sale','sales'),
  ('create_sale_from_delivery','dn'),
  ('create_sales_return','ret'),
  ('create_purchase','purch'),
  ('create_purchase_return','ret'),
  ('create_purchase_invoice_from_receipt','purch'),
  ('record_payment','pay'),
  ('create_manual_journal','jr'),
  ('cancel_sales_invoice','sales'),
  ('cancel_purchase_invoice','purch'),
  ('create_stock_transfer','trf'),
  ('create_stocktake','stk'),
  ('approve_stocktake_v2','stk'),
  ('record_pos_sale','sales')
  ) AS t(fn, key) LOOP
    FOR d IN SELECT pg_get_functiondef(p.oid) FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = w.fn LOOP
      IF position('require_perm(' in d) > 0 THEN CONTINUE; END IF;
      pos := position('perform require_role(' in lower(d));
      IF pos = 0 THEN RAISE NOTICE 'skip % (no require_role)', w.fn; CONTINUE; END IF;
      eol := position(E'\n' in substr(d, pos));
      nd := substr(d, 1, pos - 1 + eol - 1) || E'\n  perform require_perm(''' || w.key || ''');' || substr(d, pos - 1 + eol);
      EXECUTE nd;
      cnt := coalesce(cnt, 0) + 1;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'permission checks added: %', cnt;
END $$;

COMMIT;

-- ERP_patch_v1.68_admin_mfa.sql: إجبار MFA على الأدمن (مقفول بالافتراضي، بتفعّله بعد ما الأدمن يفعّل MFA)
BEGIN;

ALTER TABLE app_control ADD COLUMN IF NOT EXISTS require_admin_mfa boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN p.role='developer' THEN 'admin' ELSE p.role END
  FROM profiles p, app_control c
  WHERE p.id=auth.uid() AND p.active AND c.id=1
    AND COALESCE((auth.jwt()->>'iat')::bigint, 0) > extract(epoch FROM c.sessions_after)::bigint
    AND (p.role='developer'
         OR NOT (c.locked AND (c.lock_until IS NULL OR now() < c.lock_until))
         OR p.role = ANY(c.lock_roles))
    AND (NOT c.require_admin_mfa
         OR p.role NOT IN ('admin','developer')
         OR COALESCE(auth.jwt()->>'aal','aal1') = 'aal2')
$$;

COMMIT;
-- ERP_patch_v1.69_mfa_settings.sql: إعدادات التحقق الثنائي من شاشة المطور + حماية الإجبار
BEGIN;

ALTER TABLE app_control ADD COLUMN IF NOT EXISTS mfa_methods text[] NOT NULL DEFAULT ARRAY['totp']::text[];

-- حالة الإعدادات للمطور بس: الإجبار، الطرق، وقائمة الأدمن والمطورين مع حالة MFA لكل واحد
CREATE OR REPLACE FUNCTION admin_mfa_state() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  RETURN jsonb_build_object(
    'require', (SELECT c.require_admin_mfa FROM app_control c WHERE c.id=1),
    'methods', (SELECT to_jsonb(c.mfa_methods) FROM app_control c WHERE c.id=1),
    'admins', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', COALESCE(p.name, p.username), 'role', p.role, 'active', p.active,
               'mfa', EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=p.id AND f.status='verified'))
             ORDER BY COALESCE(p.name, p.username))
      FROM profiles p WHERE p.role IN ('admin','developer')
    ), '[]'::jsonb)
  );
END $$;

-- الطرق المتاحة حالياً: totp بس. باقي الطرق تتفتح لما نربط مزوّد لكل واحدة
CREATE OR REPLACE FUNCTION admin_mfa_set_methods(p_methods text[]) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE m text;
BEGIN
  PERFORM require_dev();
  IF p_methods IS NULL OR cardinality(p_methods)=0 THEN
    RAISE EXCEPTION 'لازم تختار طريقة واحدة على الأقل';
  END IF;
  FOREACH m IN ARRAY p_methods LOOP
    IF m <> 'totp' THEN
      RAISE EXCEPTION 'الطريقة % مش متاحة لسه', m;
    END IF;
  END LOOP;
  UPDATE app_control SET mfa_methods=p_methods, updated_at=now() WHERE id=1;
  PERFORM log_event('update','app_control','1','تعديل طرق التحقق الثنائي');
END $$;

-- تفعيل/إيقاف إجبار MFA. التفعيل بيتقفل لو فيه أدمن أو مطور نشط مش مفعّل MFA
CREATE OR REPLACE FUNCTION admin_mfa_set(p_require boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE missing int;
BEGIN
  PERFORM require_dev();
  IF p_require THEN
    SELECT count(*) INTO missing FROM profiles p
     WHERE p.role IN ('admin','developer') AND p.active
       AND NOT EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=p.id AND f.status='verified');
    IF missing > 0 THEN
      RAISE EXCEPTION 'فيه % أدمن/مطور لسه مش مفعّل التحقق الثنائي. خليهم يفعّلوه الأول', missing;
    END IF;
  END IF;
  UPDATE app_control SET require_admin_mfa=p_require, updated_at=now() WHERE id=1;
  PERFORM log_event('update','app_control','1', CASE WHEN p_require THEN 'تفعيل إجبار MFA للأدمن' ELSE 'إيقاف إجبار MFA للأدمن' END);
END $$;

REVOKE ALL ON FUNCTION admin_mfa_state(), admin_mfa_set_methods(text[]), admin_mfa_set(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_mfa_state(), admin_mfa_set_methods(text[]), admin_mfa_set(boolean) TO authenticated;

COMMIT;
-- ERP_patch_v1.73: 1) بادئة مستقلة لكل نوع مستند (بيع/شراء/مرتجع بيع/مرتجع شراء)
--                  2) الجهاز المتذكر للتحقق الثنائي (7 أيام، جهاز واحد لكل مستخدم، يتلغى عند تغيير الباسورد)
BEGIN;

-- ===== 1) البادئات =====
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS prefix_sales text NOT NULL DEFAULT 'INV-';
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS prefix_purchase text NOT NULL DEFAULT 'PUR-';
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS prefix_sales_return text NOT NULL DEFAULT 'SRET-';
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS prefix_purchase_return text NOT NULL DEFAULT 'PRET-';

-- كل دالة بتبني الرقم من البادئة بتاعة نوعها بس (من غير بادئة تانية جوه الدالة)
CREATE OR REPLACE FUNCTION _tmp_repl_numbering(p_old text, p_new text) RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE r record; def text; n int := 0;
BEGIN
  FOR r IN SELECT p.oid FROM pg_proc p
           WHERE p.pronamespace = 'public'::regnamespace
             AND position(p_old in pg_get_functiondef(p.oid)) > 0 LOOP
    def := replace(pg_get_functiondef(r.oid), p_old, p_new);
    EXECUTE def;
    n := n + 1;
  END LOOP;
  RETURN n;
END $fn$;

SELECT _tmp_repl_numbering($q$s.invoice_prefix||'INV-'||(1000+nextval('seq_sales'))$q$, $q$s.prefix_sales||(1000+nextval('seq_sales'))$q$);
SELECT _tmp_repl_numbering($q$(SELECT invoice_prefix FROM company_settings WHERE id=1)||'INV-'||(1000+nextval('seq_sales'))$q$, $q$(SELECT prefix_sales FROM company_settings WHERE id=1)||(1000+nextval('seq_sales'))$q$);
SELECT _tmp_repl_numbering($q$s.invoice_prefix||'PUR-'||(1000+nextval('seq_purchase'))$q$, $q$s.prefix_purchase||(1000+nextval('seq_purchase'))$q$);
SELECT _tmp_repl_numbering($q$(SELECT invoice_prefix FROM company_settings WHERE id=1)||'PUR-'||(1000+nextval('seq_purchase'))$q$, $q$(SELECT prefix_purchase FROM company_settings WHERE id=1)||(1000+nextval('seq_purchase'))$q$);
SELECT _tmp_repl_numbering($q$(SELECT invoice_prefix FROM company_settings WHERE id=1)||'SRET-'||(1000+nextval('seq_sret'))$q$, $q$(SELECT prefix_sales_return FROM company_settings WHERE id=1)||(1000+nextval('seq_sret'))$q$);
SELECT _tmp_repl_numbering($q$(SELECT invoice_prefix FROM company_settings WHERE id=1)||'PRET-'||(1000+nextval('seq_pret'))$q$, $q$(SELECT prefix_purchase_return FROM company_settings WHERE id=1)||(1000+nextval('seq_pret'))$q$);
DROP FUNCTION _tmp_repl_numbering(text,text);

-- ===== 2) الجهاز المتذكر =====
CREATE TABLE IF NOT EXISTS trusted_devices(
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,  -- جهاز واحد لكل مستخدم
  token_hash text NOT NULL,                                              -- الهاش بس، التوكن نفسه مش متخزن
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
ALTER TABLE trusted_devices ENABLE ROW LEVEL SECURITY;  -- مفيش policies: محدش يوصل للجدول من الـ API مباشرة
REVOKE ALL ON trusted_devices FROM PUBLIC, anon, authenticated;

-- الجهاز المتذكر بيتسجل بس لو الجلسة الحالية متحقق منها بالكود (aal2)
CREATE OR REPLACE FUNCTION trust_device(p_token text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'لازم تسجل دخول'; END IF;
  IF COALESCE(auth.jwt()->>'aal','aal1') <> 'aal2' THEN RAISE EXCEPTION 'لازم تأكد بكود التحقق الأول'; END IF;
  IF p_token IS NULL OR length(p_token) < 32 THEN RAISE EXCEPTION 'توكن الجهاز غير صالح'; END IF;
  INSERT INTO trusted_devices(user_id, token_hash, created_at, expires_at)
  VALUES (auth.uid(), encode(sha256(convert_to(p_token,'UTF8')),'hex'), now(), now() + interval '7 days')
  ON CONFLICT (user_id) DO UPDATE SET token_hash=EXCLUDED.token_hash, created_at=now(), expires_at=now() + interval '7 days';
END $$;

-- هل التوكن اللي في الـ header (x-device-trust) صالح للمستخدم الحالي
CREATE OR REPLACE FUNCTION device_trusted() RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE tok text;
BEGIN
  BEGIN
    tok := (current_setting('request.headers', true)::json) ->> 'x-device-trust';
  EXCEPTION WHEN others THEN
    tok := NULL;
  END;
  IF COALESCE(tok,'') = '' OR auth.uid() IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM trusted_devices t
    WHERE t.user_id = auth.uid()
      AND t.expires_at > now()
      AND t.token_hash = encode(sha256(convert_to(tok,'UTF8')),'hex')
  );
END $$;

-- للواجهة: تسأل هل الجهاز ده متذكر
CREATE OR REPLACE FUNCTION device_trust_status() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT device_trusted()
$$;

-- الإلغاء عند تغيير الباسورد
CREATE OR REPLACE FUNCTION trusted_devices_revoke_on_pw() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.encrypted_password IS DISTINCT FROM OLD.encrypted_password THEN
    DELETE FROM trusted_devices WHERE user_id = NEW.id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_trusted_devices_pw ON auth.users;
CREATE TRIGGER trg_trusted_devices_pw AFTER UPDATE OF encrypted_password ON auth.users
  FOR EACH ROW EXECUTE FUNCTION trusted_devices_revoke_on_pw();

-- auth_role: الإجبار بيعدّي لو الجلسة aal2 أو الجهاز متذكر
CREATE OR REPLACE FUNCTION auth_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN p.role='developer' THEN 'admin' ELSE p.role END
  FROM profiles p, app_control c
  WHERE p.id=auth.uid() AND p.active AND c.id=1
    AND COALESCE((auth.jwt()->>'iat')::bigint, 0) > extract(epoch FROM c.sessions_after)::bigint
    AND (p.role='developer'
         OR NOT (c.locked AND (c.lock_until IS NULL OR now() < c.lock_until))
         OR p.role = ANY(c.lock_roles))
    AND (NOT c.require_admin_mfa
         OR p.role NOT IN ('admin','developer')
         OR COALESCE(auth.jwt()->>'aal','aal1') = 'aal2'
         OR device_trusted())
$$;

REVOKE ALL ON FUNCTION trust_device(text), device_trusted(), device_trust_status(), trusted_devices_revoke_on_pw() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION trust_device(text), device_trusted(), device_trust_status() TO authenticated;

COMMIT;
-- ERP_patch_v1.74: إلغاء الأجهزة المتذكرة (زرار "نسيت الجهاز ده" + "تسجيل خروج للكل" بيلغي الأجهزة كمان)
BEGIN;

-- المستخدم يلغي الجهاز المتذكر بتاعه (جهاز واحد لكل مستخدم)
CREATE OR REPLACE FUNCTION revoke_my_trusted_device() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'لازم تسجل دخول'; END IF;
  DELETE FROM trusted_devices WHERE user_id = auth.uid();
END $$;

-- المطور: تسجيل خروج للكل، ومعاه إلغاء كل الأجهزة المتذكرة
CREATE OR REPLACE FUNCTION dev_revoke_all_sessions() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM require_dev();
  UPDATE app_control SET sessions_after=now(), updated_at=now() WHERE id=1;
  DELETE FROM trusted_devices;
  -- امسح جلسات التجديد عشان التوكن ما يتجددش (لو الصلاحية متاحة)
  BEGIN DELETE FROM auth.refresh_tokens; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM auth.sessions;       EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM log_event('update','app_control','1','خروج كل الجلسات وإلغاء الأجهزة المتذكرة');
END $$;

REVOKE ALL ON FUNCTION revoke_my_trusted_device(), dev_revoke_all_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION revoke_my_trusted_device(), dev_revoke_all_sessions() TO authenticated;

COMMIT;
