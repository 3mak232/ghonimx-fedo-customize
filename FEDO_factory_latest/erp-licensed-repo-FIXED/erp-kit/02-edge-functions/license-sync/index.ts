// license-sync: بتستقبل أمر ترخيص موقّع من اللوحة المركزية وتطبّقه عند العميل.
// النشر:  supabase functions deploy license-sync --no-verify-jwt   (التوثيق هنا بالتوقيع مش بالـJWT)
// الـSecrets المطلوبة:
//   LICENSE_PUBLIC_KEY  المفتاح العام Ed25519 (raw 32 bytes بصيغة base64) من أداة gen_keys.mjs
//   CLIENT_ID           معرّف العميل زي ما هو في اللوحة (UUID). بيمنع استخدام أمر عميل على عميل تاني
//   ADMIN_SECRET_KEY    مفتاح الخدمة (نفس اللي بتستخدمه admin-create-user)
// المفتاح الخاص مش هنا أبدًا، بيفضل في اللوحة بس.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const b64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const MAX_AGE_MS = 15 * 60 * 1000;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("ADMIN_SECRET_KEY");
  const pub = Deno.env.get("LICENSE_PUBLIC_KEY");
  const clientId = Deno.env.get("CLIENT_ID");
  if (!url || !serviceKey || !pub || !clientId) return json(500, { error: "server not configured" });

  let body: { payload?: string; sig?: string };
  try { body = await req.json(); } catch { return json(400, { error: "bad json" }); }
  if (typeof body.payload !== "string" || typeof body.sig !== "string") return json(400, { error: "bad body" });

  // 1) التحقق من التوقيع على النص الخام بالظبط (من غير إعادة تسلسل)
  let ok = false;
  try {
    const key = await crypto.subtle.importKey("raw", b64(pub), { name: "Ed25519" }, false, ["verify"]);
    ok = await crypto.subtle.verify({ name: "Ed25519" }, key, b64(body.sig), new TextEncoder().encode(body.payload));
  } catch { ok = false; }
  if (!ok) return json(401, { error: "invalid signature" });

  let p: Record<string, unknown>;
  try { p = JSON.parse(body.payload); } catch { return json(400, { error: "bad payload" }); }

  // 2) الأمر لازم يكون لعميل ده بالذات، وحديث
  if (p.client_id !== clientId) return json(403, { error: "wrong client" });
  const issued = Date.parse(String(p.issued_at ?? ""));
  if (!Number.isFinite(issued) || Math.abs(Date.now() - issued) > MAX_AGE_MS) {
    return json(400, { error: "stale or missing issued_at" });
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // 3) ping: يرجّع الحالة من غير تغيير (لشاشة المتابعة)
  if (p.type === "ping") {
    const { data, error } = await admin.from("license").select(
      "plan_code,status,seq,schema_version,synced_at,max_users,max_branches,max_warehouses",
    ).eq("id", 1).single();
    if (error) return json(500, { error: error.message });
    const { count } = await admin.from("profiles").select("id", { count: "exact", head: true })
      .eq("active", true).neq("role", "developer");
    return json(200, { ok: true, license: data, users_used: count });
  }

  // 4) تطبيق الترخيص (الـseq المتكرر بيترفض داخل قاعدة البيانات)
  const { data, error } = await admin.rpc("license_apply", { p });
  if (error) return json(409, { error: error.message });
  return json(200, data);
});
