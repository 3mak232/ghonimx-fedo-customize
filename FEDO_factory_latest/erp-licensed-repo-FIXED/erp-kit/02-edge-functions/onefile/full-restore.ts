// ملف واحد جاهز للصق في Supabase Dashboard. (v1.73)
import postgres from "npm:postgres@3.4.5";

// ===== الكور المشترك =====
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

// ===== أدوات الاتصال والتحقق =====
// أدوات مشتركة للـ Edge Functions الخاصة بالنسخة الكاملة (v1.69)

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-device-trust",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });
}

const URL_ = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DB_URL = Deno.env.get("SUPABASE_DB_URL")!;

const encName = (name: string) => name.split("/").map(encodeURIComponent).join("/");
const svcHeaders = { apikey: KEY, authorization: `Bearer ${KEY}` };

// تحقق من المستخدم: لازم يكون نشط، ودور المطور لو needDev، والـ MFA لو الإجبار مفعّل
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function authz(req: Request, needDev: boolean): Promise<any> {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return { status: 401, error: "لازم تسجل دخول الأول" };
  const u = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: KEY, authorization: `Bearer ${token}` } });
  if (!u.ok) return { status: 401, error: "الجلسة منتهية، سجّل دخول تاني" };
  const user = await u.json();
  const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
  const sql = postgres(DB_URL, { max: 1, prepare: false });
  const [p] = await sql`select role, active from public.profiles where id=${user.id}`;
  const [c] = await sql`select require_admin_mfa from public.app_control where id=1`;
  const allowed = p && p.active && (p.role === "developer" || (!needDev && p.role === "admin"));
  if (!allowed) { await sql.end(); return { status: 403, error: needDev ? "الاستعادة للمطور بس" : "النسخة الكاملة للأدمن والمطور بس" }; }
  if (c?.require_admin_mfa && (payload.aal || "aal1") !== "aal2") {
    // الجهاز المتذكر: بنقارن الهاش بتاع التوكن بنفس طريقة السيرفر (sha256 hex)
    const tok = req.headers.get("x-device-trust") || "";
    let ok = false;
    if (tok.length >= 32) {
      const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(tok));
      const hex = Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
      const [t] = await sql`select 1 as ok from public.trusted_devices where user_id=${user.id} and expires_at>now() and token_hash=${hex}`;
      ok = !!t;
    }
    if (!ok) {
      await sql.end();
      return { status: 403, error: "لازم تفعّل التحقق الثنائي الأول" };
    }
  }
  return { sql, user, role: p.role };
}

function b64FromBytes(buf: Uint8Array): string {
  let s = "";
  for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(s);
}

// adapter للـ Storage: بيستخدم مفتاح الخدمة عشان يقرأ/يكتب كل البكتات (الخاصة كمان)
export const storage = {
  async download(bucket: string, name: string): Promise<string> {
    const r = await fetch(`${URL_}/storage/v1/object/${encodeURIComponent(bucket)}/${encName(name)}`, { headers: svcHeaders });
    if (!r.ok) throw new Error(`تعذر تحميل الملف ${bucket}/${name}`);
    return b64FromBytes(new Uint8Array(await r.arrayBuffer()));
  },
  async upload(bucket: string, name: string, b64: string, mime: string | null): Promise<{ ok: boolean; error?: string }> {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const r = await fetch(`${URL_}/storage/v1/object/${encodeURIComponent(bucket)}/${encName(name)}`, {
      method: "POST",
      headers: { ...svcHeaders, "x-upsert": "true", "content-type": mime || "application/octet-stream" },
      body: bytes,
    });
    return r.ok ? { ok: true } : { ok: false, error: (await r.text()).slice(0, 200) };
  },
  async removeBlobs(objs: { bucket_id: string; name: string }[]): Promise<void> {
    const byBucket: Record<string, string[]> = {};
    for (const o of objs) (byBucket[o.bucket_id] ||= []).push(o.name);
    for (const [bucket, prefixes] of Object.entries(byBucket)) {
      for (let i = 0; i < prefixes.length; i += 500) {
        await fetch(`${URL_}/storage/v1/object/${encodeURIComponent(bucket)}`, {
          method: "DELETE",
          headers: { ...svcHeaders, "content-type": "application/json" },
          body: JSON.stringify({ prefixes: prefixes.slice(i, i + 500) }),
        });
      }
    }
  },
};

// ===== الدالة =====
// استعادة النسخة الكاملة. mode=check بيرجع هل فيه داتا حالية، mode=restore بينفذ الاستعادة (للمطور بس)

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const body = await req.json().catch(() => ({}));
  const a = await authz(req, true);
  if (a.error) return json({ error: a.error }, a.status);
  try {
    if (body.mode === "check") return json(await checkState(a.sql));
    if (body.mode !== "restore") return json({ error: "وضع غير معروف" }, 400);
    const data = body.data;
    if (!data || data.format !== "ERP-FULLBAK") return json({ error: "الملف مش نسخة ERP كاملة صحيحة" }, 400);

    const oldObjects = await listObjects(a.sql);
    let counts: Record<string, number>;
    try {
      counts = await a.sql.begin(async (tx) => await restoreDb(tx, data));
    } catch (e) {
      // الـ transaction اتعملها rollback، فالداتا اللي كانت موجودة سليمة
      return json({ error: "فشلت الاستعادة، ومفيش حاجة اتغيرت: " + (e as Error).message }, 500);
    }

    // بعد الـ commit: نمسح الملفات القديمة ونرفع ملفات النسخة
    await storage.removeBlobs(oldObjects).catch(() => {});
    const errors: string[] = [];
    let filesUploaded = 0;
    for (const f of data.storage?.files ?? []) {
      const r = await storage.upload(f.bucket_id, f.name, f.data, f.mime);
      if (r.ok) filesUploaded++;
      else errors.push(`${f.bucket_id}/${f.name}: ${r.error}`);
    }
    return json({ ok: true, counts, filesUploaded, errors });
  } finally {
    await a.sql.end();
  }
});
