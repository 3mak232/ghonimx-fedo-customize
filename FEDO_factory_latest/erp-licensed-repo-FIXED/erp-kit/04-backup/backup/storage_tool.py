"""نسخ ملفات Supabase Storage.
usage:
  python storage_tool.py download <dest_dir>     # ينزّل كل الملفات في كل الـ buckets
  python storage_tool.py upload <src_dir>        # يرفع كل الملفات للـ buckets (للاستعادة)
Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
"""
import os, sys, json
import requests

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
H = {"apikey": KEY, "Authorization": "Bearer " + KEY}

def list_buckets():
    r = requests.get(f"{URL}/storage/v1/bucket", headers=H, timeout=60)
    r.raise_for_status()
    return [b["name"] for b in r.json()]

def list_folder(bucket, prefix):
    items, offset = [], 0
    while True:
        body = {"prefix": prefix, "limit": 1000, "offset": offset, "sortBy": {"column": "name", "order": "asc"}}
        r = requests.post(f"{URL}/storage/v1/object/list/{bucket}", headers={**H, "Content-Type": "application/json"}, data=json.dumps(body), timeout=60)
        r.raise_for_status()
        page = r.json()
        items += page
        if len(page) < 1000: break
        offset += 1000
    return items

def walk(bucket, prefix=""):
    for it in list_folder(bucket, prefix):
        path = (prefix + "/" if prefix else "") + it["name"]
        if it.get("id") is None:          # مجلد
            yield from walk(bucket, path)
        else:
            yield path

def download(dest):
    manifest = {}
    for b in list_buckets():
        for path in walk(b):
            local = os.path.join(dest, b, path)
            os.makedirs(os.path.dirname(local), exist_ok=True)
            with requests.get(f"{URL}/storage/v1/object/{b}/{path}", headers=H, stream=True, timeout=600) as r:
                r.raise_for_status()
                with open(local, "wb") as f:
                    for chunk in r.iter_content(1024 * 1024): f.write(chunk)
            manifest.setdefault(b, []).append(path)
    with open(os.path.join(dest, "_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("storage files:", sum(len(v) for v in manifest.values()))

def upload(src):
    for b in os.listdir(src):
        bdir = os.path.join(src, b)
        if not os.path.isdir(bdir): continue
        for root, _, files in os.walk(bdir):
            for fn in files:
                full = os.path.join(root, fn)
                path = os.path.relpath(full, bdir).replace(os.sep, "/")
                with open(full, "rb") as f:
                    r = requests.post(f"{URL}/storage/v1/object/{b}/{path}", headers={**H, "x-upsert": "true"}, data=f, timeout=600)
                if r.status_code >= 300:
                    print("FAILED", b, path, r.status_code, r.text[:200])
                else:
                    print("uploaded", b, path)

if __name__ == "__main__":
    cmd, arg = sys.argv[1], sys.argv[2]
    if cmd == "download": download(arg)
    elif cmd == "upload": upload(arg)
    else: sys.exit("unknown command")
