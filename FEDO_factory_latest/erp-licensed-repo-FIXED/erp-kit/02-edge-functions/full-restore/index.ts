// استعادة النسخة الكاملة. mode=check بيرجع هل فيه داتا حالية، mode=restore بينفذ الاستعادة (للمطور بس)
import { authz, checkState, restoreDb, listObjects, storage, cors, json } from "../_shared/fullbak-env.ts";

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
