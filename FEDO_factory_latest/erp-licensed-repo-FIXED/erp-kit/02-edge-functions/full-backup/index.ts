// نسخة احتياطية كاملة: كل الجداول + المستخدمين والباسوردات + الإعدادات + ملفات الـ Storage
import { authz, collectBackup, storage, cors, json } from "../_shared/fullbak-env.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const a = await authz(req, false);
  if (a.error) return json({ error: a.error }, a.status);
  try {
    return json(await collectBackup(a.sql, storage));
  } catch (e) {
    return json({ error: "تعذر تجهيز النسخة: " + (e as Error).message }, 500);
  } finally {
    await a.sql.end();
  }
});
