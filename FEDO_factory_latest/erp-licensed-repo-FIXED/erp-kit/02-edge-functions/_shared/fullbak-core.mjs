// نسخة احتياطية كاملة + استعادة (v1.69)
// الملف ده بيشتغل في Edge Functions (Deno) وفي الاختبار المحلي (Node). مفيهوش استدعاءات لأي مكتبة خاصة بالبيئة.
// الـ sql هنا = اتصال postgres.js (أو transaction منه). الـ storage = adapter فيه:
//   download(bucket, name) -> base64 string
//   upload(bucket, name, base64, mime) -> {ok, error?}
//   removeBlobs([{bucket_id, name}]) -> void

export const FORMAT = 'ERP-FULLBAK';
export const VERSION = 'v1.69';

// جداول مش بنفحصها عشان نعرف الداتا "فاضية" ولا لأ (بيتعملوا تلقائي مع الـ setup أو بيتسجلوا مع أول مستخدم)
export const SEED_TABLES = new Set(['profiles', 'app_control', 'company_settings', 'role_default_perms', 'units', 'branches', 'warehouses', 'cash_accounts', 'accounts', 'audit_logs']);

const q = s => '"' + String(s).replace(/"/g, '""') + '"';

async function publicTables(sql) {
  return (await sql`select tablename from pg_tables where schemaname='public' order by tablename`).map(r => r.tablename);
}
async function tableExists(sql, schema, t) {
  return (await sql`select 1 from information_schema.tables where table_schema=${schema} and table_name=${t}`).length > 0;
}
async function writableCols(sql, schema, t) {
  return (await sql`select column_name from information_schema.columns where table_schema=${schema} and table_name=${t} and is_generated='NEVER' order by ordinal_position`).map(r => r.column_name);
}

async function dumpTable(sql, schema, t) {
  const cols = await writableCols(sql, schema, t);
  if (!cols.length) return { columns: [], rows: [] };
  const [r] = await sql.unsafe(`select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) as rows from (select ${cols.map(q).join(',')} from ${q(schema)}.${q(t)}) x`);
  return { columns: cols, rows: r.rows };
}

export async function listObjects(sql) {
  if (!(await tableExists(sql, 'storage', 'objects'))) return [];
  return await sql`select bucket_id, name, metadata->>'mimetype' as mimetype from storage.objects`;
}

// ---------- النسخ ----------
export async function collectBackup(sql, storage) {
  const data = {
    format: FORMAT, version: VERSION, created_at: new Date().toISOString(),
    public: {}, sequences: {}, auth: {},
    storage: { buckets: null, files: [] },
  };
  for (const t of await publicTables(sql)) data.public[t] = await dumpTable(sql, 'public', t);

  const seqs = await sql`select sequencename from pg_sequences where schemaname='public'`;
  for (const { sequencename: s } of seqs) {
    const [r] = await sql.unsafe(`select last_value, is_called from public.${q(s)}`);
    data.sequences[s] = { last: String(r.last_value), called: r.is_called };
  }

  for (const t of ['users', 'identities', 'mfa_factors']) {
    if (await tableExists(sql, 'auth', t)) data.auth[t] = await dumpTable(sql, 'auth', t);
  }

  if (await tableExists(sql, 'storage', 'buckets')) {
    data.storage.buckets = await dumpTable(sql, 'storage', 'buckets');
    for (const o of await listObjects(sql)) {
      const b64 = await storage.download(o.bucket_id, o.name);
      data.storage.files.push({ bucket_id: o.bucket_id, name: o.name, mime: o.mimetype || null, data: b64 });
    }
  }
  return data;
}

// ---------- الفحص قبل الاستعادة ----------
export async function checkState(sql) {
  const tables = [];
  for (const t of await publicTables(sql)) {
    if (SEED_TABLES.has(t)) continue;
    const [r] = await sql.unsafe(`select exists(select 1 from public.${q(t)}) as e`);
    if (r.e) tables.push(t);
  }
  const files = (await listObjects(sql)).length;
  return { hasData: tables.length > 0, tables, storageFiles: files };
}

// ---------- الاستعادة (داخل transaction واحدة) ----------
async function insertRows(tx, schema, t, d, upsert = false) {
  if (!d || !d.rows || !d.rows.length) return;
  if (!(await tableExists(tx, schema, t))) return;
  const target = new Set(await writableCols(tx, schema, t));
  const cols = (d.columns || []).filter(c => target.has(c));
  if (!cols.length) return;
  const list = cols.map(q).join(',');
  let sqlText = `INSERT INTO ${q(schema)}.${q(t)} (${list}) SELECT ${list} FROM jsonb_populate_recordset(null::${q(schema)}.${q(t)}, $1::text::jsonb)`;
  if (upsert) {
    const rest = cols.filter(c => c !== 'id').map(c => `${q(c)}=EXCLUDED.${q(c)}`).join(',');
    sqlText += ` ON CONFLICT (id) DO UPDATE SET ${rest}`;
  }
  await tx.unsafe(sqlText, [JSON.stringify(d.rows)]);
}

export async function restoreDb(tx, data) {
  if (!data || data.format !== FORMAT) throw new Error('الملف مش نسخة ERP كاملة صحيحة');
  const counts = {};
  const tablesNow = await publicTables(tx);
  const wipe = async () => {
    if (tablesNow.length) await tx.unsafe(`TRUNCATE ${tablesNow.map(t => 'public.' + q(t)).join(',')} RESTART IDENTITY`);
  };

  // 1) نوقف التريجرز اليوزر (audit وغيره) أثناء التحميل. ده مش بيلمس الـ FK
  for (const t of tablesNow) await tx.unsafe(`ALTER TABLE public.${q(t)} DISABLE TRIGGER USER`);

  // 2) امسح الداتا الحالية
  await wipe();

  // 3) حسابات الدخول (بالباسوردات والهاشات)
  if (data.auth && data.auth.users) {
    for (const t of ['mfa_factors', 'identities']) {
      if (await tableExists(tx, 'auth', t)) await tx.unsafe(`DELETE FROM auth.${q(t)}`);
    }
    await tx.unsafe(`DELETE FROM auth.users`);
    await insertRows(tx, 'auth', 'users', data.auth.users);
    await insertRows(tx, 'auth', 'identities', data.auth.identities);
    await insertRows(tx, 'auth', 'mfa_factors', data.auth.mfa_factors);
    // تريجر handle_new_user بيعمل صفوف في الجداول بعد إدخال المستخدمين: نمسحها تاني قبل الاستعادة الفعلية
    await wipe();
  }

  // 4) بيانات الجداول
  for (const t of Object.keys(data.public || {})) {
    if (!tablesNow.includes(t)) continue; // جدول مش موجود في النسخة الحالية للتطبيق
    const d = data.public[t];
    await insertRows(tx, 'public', t, d, false);
    counts[t] = (d.rows || []).length;
  }

  // 5) العدادات (الـ ids التلقائية) ترجع لآخر قيمة
  for (const [s, v] of Object.entries(data.sequences || {})) {
    const exists = (await tx`select 1 from pg_sequences where schemaname='public' and sequencename=${s}`).length > 0;
    if (exists) await tx.unsafe(`select setval($1::text::regclass, $2::bigint, $3::boolean)`, ['public.' + q(s), v.last, v.called]);
  }

  // 6) الـ Storage: نحدّث البكتات ونمسح ميتاداتا الملفات القديمة (الملفات نفسها بترفع بعد الـ commit)
  if (data.storage && data.storage.buckets && (await tableExists(tx, 'storage', 'buckets'))) {
    await insertRows(tx, 'storage', 'buckets', data.storage.buckets, true);
    await tx.unsafe(`set local storage.allow_delete_query = 'true'`);
    await tx.unsafe(`DELETE FROM storage.objects`);
  }

  // 7) نرجّع التريجرز
  for (const t of tablesNow) await tx.unsafe(`ALTER TABLE public.${q(t)} ENABLE TRIGGER USER`);
  return counts;
}
