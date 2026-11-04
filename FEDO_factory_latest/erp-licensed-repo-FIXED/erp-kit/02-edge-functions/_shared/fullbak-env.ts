// أدوات مشتركة للـ Edge Functions الخاصة بالنسخة الكاملة (v1.69)
import postgres from "npm:postgres@3.4.5";
export { collectBackup, checkState, restoreDb, listObjects } from "./fullbak-core.mjs";

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
