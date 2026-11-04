"""رفع الملفات على Google Drive وتنظيف النسخ القديمة.
usage:
  python drive_tool.py upload <local_file> <drive_name>
  python drive_tool.py keep <N>        # يحتفظ بآخر N نسخ (erp-backup-*) ويحذف الباقي
  python drive_tool.py download <drive_name> <local_path>
Env: GDRIVE_SERVICE_ACCOUNT_JSON, GDRIVE_FOLDER_ID
"""
import json, os, sys
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request

SCOPES = ["https://www.googleapis.com/auth/drive"]

def token():
    # الأولوية لـ OAuth (حساب Gmail شخصي) لو الـ secrets موجودة، وإلا service account
    if os.environ.get("GDRIVE_REFRESH_TOKEN"):
        from google.oauth2.credentials import Credentials
        creds = Credentials(
            token=None,
            refresh_token=os.environ["GDRIVE_REFRESH_TOKEN"],
            token_uri="https://oauth2.googleapis.com/token",
            client_id=os.environ["GDRIVE_CLIENT_ID"],
            client_secret=os.environ["GDRIVE_CLIENT_SECRET"],
            scopes=SCOPES,
        )
    else:
        info = json.loads(os.environ["GDRIVE_SERVICE_ACCOUNT_JSON"])
        creds = service_account.Credentials.from_service_account_info(info, scopes=SCOPES)
    creds.refresh(Request())
    return creds.token

def h(t):
    return {"Authorization": "Bearer " + t}

def list_backups(t):
    folder = os.environ["GDRIVE_FOLDER_ID"]
    q = f"'{folder}' in parents and trashed=false and name contains 'erp-backup-'"
    files, page = [], None
    while True:
        params = {"q": q, "orderBy": "name desc", "pageSize": 200, "fields": "nextPageToken,files(id,name,size)"}
        if page: params["pageToken"] = page
        r = requests.get("https://www.googleapis.com/drive/v3/files", headers=h(t), params=params, timeout=60)
        r.raise_for_status()
        j = r.json()
        files += j.get("files", [])
        page = j.get("nextPageToken")
        if not page: break
    return files  # الأحدث الأول (الاسم بيحتوي التاريخ والوقت)

def upload(local, name):
    t = token()
    folder = os.environ["GDRIVE_FOLDER_ID"]
    r = requests.post("https://www.googleapis.com/drive/v3/files", headers=h(t),
                      json={"name": name, "parents": [folder]}, timeout=60)
    r.raise_for_status()
    fid = r.json()["id"]
    with open(local, "rb") as f:
        r = requests.patch(f"https://www.googleapis.com/upload/drive/v3/files/{fid}?uploadType=media",
                           headers={**h(t), "Content-Type": "application/octet-stream"}, data=f, timeout=3600)
    r.raise_for_status()
    print("uploaded:", name, "id:", fid)

def keep(n):
    t = token()
    files = list_backups(t)
    for f in files[n:]:
        r = requests.delete(f"https://www.googleapis.com/drive/v3/files/{f['id']}", headers=h(t), timeout=60)
        r.raise_for_status()
        print("deleted old backup:", f["name"])
    print(f"kept {min(len(files), n)} backup(s)")

def download(name, local):
    t = token()
    matches = [f for f in list_backups(t) if f["name"] == name]
    if not matches: sys.exit("not found: " + name)
    with requests.get(f"https://www.googleapis.com/drive/v3/files/{matches[0]['id']}?alt=media",
                      headers=h(t), stream=True, timeout=3600) as r:
        r.raise_for_status()
        with open(local, "wb") as out:
            for chunk in r.iter_content(1024 * 1024):
                out.write(chunk)
    print("downloaded:", name)

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "upload": upload(sys.argv[2], sys.argv[3])
    elif cmd == "keep": keep(int(sys.argv[2]))
    elif cmd == "download": download(sys.argv[2], sys.argv[3])
    else: sys.exit("unknown command")
