import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const ROLES = ["admin", "accountant", "sales", "store", "developer"];
const USER_RE = /^[A-Za-z0-9_.]{3,30}$/;
const PHONE_RE = /^\+?[0-9]{8,15}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("ADMIN_SECRET_KEY");

  if (!url || !anonKey) {
    return json(500, { error: "إعدادات السيرفر الأساسية مش موجودة" });
  }
  if (!serviceKey) {
    return json(500, { error: "مفتاح الخدمة ADMIN_SECRET_KEY مش متضبط في الـ Secrets" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";

  // 1) مين اللي بيطلب؟
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return json(401, { error: "يجب تسجيل الدخول أولاً" });

  // 2) عميل الخدمة
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 3) لازم الطالب يكون أدمن أو مطور مفعّل
  const { data: caller, error: callerErr } = await admin
    .from("profiles")
    .select("role, active")
    .eq("id", userData.user.id)
    .single();
  if (!caller || !caller.active || !["admin", "developer"].includes(caller.role)) {
    return json(403, { error: "ليس لديك صلاحية" });
  }

  // 4) التحقق من البيانات
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "بيانات غير صالحة" });
  }
  // v1.45: إجراءات إدارة المستخدم الموجود (تغيير كلمة السر / تعديل البيانات)
  const action = String(body?.action ?? "create");
  if (action === "reset_password" || action === "update_user") {
    const targetId = String(body?.user_id ?? "");
    if (!targetId) return json(400, { error: "المستخدم غير محدد" });
    const { data: target, error: tErr } = await admin
      .from("profiles")
      .select("id, role")
      .eq("id", targetId)
      .single();
    if (tErr || !target) return json(404, { error: "المستخدم غير موجود" });
    if (target.role === "developer" && caller.role !== "developer") {
      return json(403, { error: "تعديل حساب المطور متاح للمطور فقط" });
    }

    if (action === "reset_password") {
      const pw = String(body?.password ?? "");
      if (pw.length < 8) return json(400, { error: "كلمة السر لازم تكون 8 حروف على الأقل" });
      const { error: pwErr } = await admin.auth.admin.updateUserById(targetId, { password: pw });
      if (pwErr) return json(400, { error: pwErr.message });
      return json(200, { ok: true });
    }

    const uName = String(body?.name ?? "").trim();
    const uEmail = String(body?.email ?? "").trim().toLowerCase();
    const uRole = String(body?.role ?? "");
    const uUser = String(body?.username ?? "").trim();
    let uPhone = String(body?.phone ?? "").replace(/\s+/g, "");
    if (/^0[0-9]{10}$/.test(uPhone)) uPhone = "+20" + uPhone.slice(1);
    if (!uName) return json(400, { error: "الاسم مطلوب" });
    if (!USER_RE.test(uUser)) return json(400, { error: "اسم المستخدم لازم يكون من 3 لـ 30 حرف (إنجليزي أو أرقام أو _ أو .)" });
    if (!PHONE_RE.test(uPhone)) return json(400, { error: "رقم الموبايل غير صحيح" });
    const { data: uTaken } = await admin.from("profiles").select("id").ilike("username", uUser).neq("id", targetId).maybeSingle();
    if (uTaken) return json(400, { error: "اسم المستخدم ده مستخدم قبل كده" });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(uEmail)) return json(400, { error: "الإيميل غير صحيح" });
    if (!ROLES.includes(uRole)) return json(400, { error: "الدور غير صحيح" });
    if (uRole === "developer" && caller.role !== "developer") {
      return json(403, { error: "إضافة مطور متاحة للمطور فقط" });
    }
    const { error: authErr } = await admin.auth.admin.updateUserById(targetId, {
      email: uEmail,
      email_confirm: true,
      user_metadata: { name: uName },
    });
    if (authErr) return json(400, { error: authErr.message });
    const { error: profErr2 } = await admin
      .from("profiles")
      .update({ name: uName, username: uUser, phone: uPhone, role: uRole })
      .eq("id", targetId);
    if (profErr2) return json(500, { error: "تعذر تحديث بيانات المستخدم: " + profErr2.message });
    return json(200, { ok: true });
  }

  const name = String(body?.name ?? "").trim();
  const email = String(body?.email ?? "").trim().toLowerCase();
  const password = String(body?.password ?? "");
  const role = String(body?.role ?? "");
  const username = String(body?.username ?? "").trim();
  let phone = String(body?.phone ?? "").replace(/\s+/g, "");
  if (/^0[0-9]{10}$/.test(phone)) phone = "+20" + phone.slice(1);

  if (!name) return json(400, { error: "الاسم مطلوب" });
  if (!USER_RE.test(username)) return json(400, { error: "اسم المستخدم لازم يكون من 3 لـ 30 حرف (إنجليزي أو أرقام أو _ أو .)" });
  if (!PHONE_RE.test(phone)) return json(400, { error: "رقم الموبايل غير صحيح" });
  const { data: taken } = await admin.from("profiles").select("id").ilike("username", username).maybeSingle();
  if (taken) return json(400, { error: "اسم المستخدم ده مستخدم قبل كده" });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "الإيميل غير صحيح" });
  if (password.length < 8) return json(400, { error: "كلمة السر لازم تكون 8 حروف على الأقل" });
  if (!ROLES.includes(role)) return json(400, { error: "الدور غير صحيح" });
  if (role === "developer" && caller.role !== "developer") {
    return json(403, { error: "إضافة مطور متاحة للمطور فقط" });
  }

  // 5) إنشاء الحساب
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name },
  });
  if (createErr || !created?.user) {
    return json(400, { error: createErr?.message ?? "تعذر إنشاء المستخدم" });
  }

  // 6) تفعيل الصلاحيات (الـ trigger بيعمل profile بدور sales وغير مفعّل)
  const { error: profErr } = await admin
    .from("profiles")
    .update({ name, username, phone, role, active: true })
    .eq("id", created.user.id);

  if (profErr) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json(500, { error: "تعذر تفعيل صلاحيات المستخدم: " + profErr.message });
  }

  return json(200, { id: created.user.id, email, username, role });
});
