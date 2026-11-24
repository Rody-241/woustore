"""Récupère le VRAI logo de chaque appli du catalogue, tel que son créateur l'a mis
dans son APK, et l'enregistre dans icons/<id>.png.

- Si icons/<id>.png existe déjà et que "keepIcon" est vrai dans le catalogue, on n'y touche pas.
- Sinon : téléchargement de la dernière version de l'APK, lecture de l'icône avec
  `aapt dump badging`, puis copie de la plus grande image PNG trouvée.
Appelé par le workflow « Logos des applis »."""
import glob
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request
import zipfile

TOKEN = os.environ.get("GITHUB_TOKEN", "")
OUT = pathlib.Path("icons")
META = pathlib.Path("meta")


def api(url):
    req = urllib.request.Request(url, headers={"User-Agent": "WouStore", "Authorization": f"Bearer {TOKEN}"} if TOKEN else {"User-Agent": "WouStore"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": "WouStore"})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)


def find_aapt():
    home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or "/usr/local/lib/android/sdk"
    tools = sorted(glob.glob(f"{home}/build-tools/*/aapt"))
    if not tools:
        sys.exit("aapt introuvable")
    return tools[-1]


def to_png(data):
    """Les logos en WebP sont convertis en PNG."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return data
    import io
    from PIL import Image
    out = io.BytesIO()
    Image.open(io.BytesIO(data)).convert("RGBA").save(out, "PNG")
    return out.getvalue()


def resource_values(apk, aapt):
    """id de ressource -> liste de valeurs (chemins de fichiers ou couleurs)."""
    out = subprocess.run([aapt, "dump", "--values", "resources", apk], capture_output=True, text=True).stdout
    values, current = {}, None
    for line in out.splitlines():
        m = re.match(r"\s*resource (0x[0-9a-f]+) \S+: t=(0x[0-9a-f]+) d=(0x[0-9a-f]+)", line)
        if m:
            current = int(m.group(1), 16)
            t, d = int(m.group(2), 16), int(m.group(3), 16)
            if 0x1c <= t <= 0x1f:  # couleur
                values.setdefault(current, []).append(("color", d))
            continue
        m = re.match(r'\s*\((?:string8|string16)\) "(res/[^"]+)"', line)
        if m and current is not None:
            values.setdefault(current, []).append(("file", m.group(1)))
    return values


def layer_image(ref, values, z, size):
    from PIL import Image
    files = [v for k, v in values.get(ref, []) if k == "file" and v.endswith((".png", ".webp"))]
    colors = [v for k, v in values.get(ref, []) if k == "color"]
    if files:
        best = max(files, key=lambda f: z.getinfo(f).file_size if f in z.namelist() else 0)
        if best in z.namelist():
            import io
            return Image.open(io.BytesIO(z.read(best))).convert("RGBA").resize((size, size), Image.LANCZOS)
    if colors:
        c = colors[0]
        return Image.new("RGBA", (size, size), ((c >> 16) & 255, (c >> 8) & 255, c & 255, (c >> 24) & 255 or 255))
    return None


def compose_adaptive(apk, aapt, xml_path, z):
    try:
        tree = subprocess.run([aapt, "dump", "xmltree", apk, xml_path], capture_output=True, text=True).stdout
        refs, layer = {}, None
        for line in tree.splitlines():
            m = re.search(r"E: (background|foreground)", line)
            if m:
                layer = m.group(1)
                continue
            m = re.search(r"android:drawable\([^)]*\)=@(0x[0-9a-f]+)", line)
            if m and layer and layer not in refs:
                refs[layer] = int(m.group(1), 16)
        if "foreground" not in refs:
            return None
        values = resource_values(apk, aapt)
        size = 432  # 108 dp en xxxhdpi
        fg = layer_image(refs["foreground"], values, z, size)
        if fg is None:
            return None
        from PIL import Image
        bg = layer_image(refs.get("background", -1), values, z, size) or Image.new("RGBA", (size, size), (255, 255, 255, 255))
        bg.alpha_composite(fg)
        # Android n'affiche que les 72 dp du centre.
        m = size * 18 // 108
        icon = bg.crop((m, m, size - m, size - m)).resize((192, 192), Image.LANCZOS)
        import io
        out = io.BytesIO()
        icon.save(out, "PNG")
        print("  icône adaptative assemblée depuis", xml_path)
        return out.getvalue()
    except Exception as e:
        print("  icône adaptative impossible :", e)
        return None


def icon_from_apk(apk, aapt):
    out = subprocess.run([aapt, "dump", "badging", apk], capture_output=True, text=True).stdout
    # application-icon-640:'res/xx.png'  → on garde les PNG, de la plus grande à la plus petite.
    icons = re.findall(r"application-icon-(\d+):'([^']+)'", out)
    icons.sort(key=lambda t: int(t[0]), reverse=True)
    with zipfile.ZipFile(apk) as z:
        names = set(z.namelist())
        for _, path in icons:
            if path.endswith((".png", ".webp")) and path in names:
                return to_png(z.read(path))
        # Icône adaptative : on assemble le fond et le dessin, comme le fait Android.
        for _, path in icons:
            if path.endswith(".xml"):
                data = compose_adaptive(apk, aapt, path, z)
                if data:
                    return data
        # Sinon : une image ic_launcher en PNG.
        cands = [n for n in names if re.search(r"mipmap-[a-z]*hdpi[^/]*/ic_launcher(_round)?\.(png|webp)$", n)]
        cands.sort(key=lambda n: ("xxxhdpi" in n, "xxhdpi" in n, "xhdpi" in n, "_round" not in n, n), reverse=True)
        if cands:
            return to_png(z.read(cands[0]))
    return None


def get_bytes(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "WouStore"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        return to_png(data) if data else None
    except Exception:
        return None


def icon_from_store_pages(app):
    repo = app["github"]
    urls = [
        f"https://f-droid.org/repo/{app['id']}/en-US/icon.png",
    ]
    for branch in ("master", "main", "dev"):
        urls.append(f"https://raw.githubusercontent.com/{repo}/{branch}/fastlane/metadata/android/en-US/images/icon.png")
    for url in urls:
        data = get_bytes(url)
        if data:
            print(app["name"], ": logo trouvé sur", url)
            return data
    return None


def apk_cert(apk, aapt):
    """Empreinte SHA-256 du certificat qui signe l'APK (avec apksigner)."""
    apksigner = os.path.join(os.path.dirname(aapt), "apksigner")
    out = subprocess.run([apksigner, "verify", "--print-certs", apk], capture_output=True, text=True).stdout
    m = re.search(r"certificate SHA-256 digest: ([0-9a-f]{64})", out)
    return m.group(1) if m else None


def apk_info(apk, aapt):
    """Ce que l'APK déclare : autorisations, Android minimum, version."""
    out = subprocess.run([aapt, "dump", "badging", apk], capture_output=True, text=True).stdout
    perms = sorted(set(re.findall(r"uses-permission: name='([^']+)'", out)))
    sdk = re.search(r"sdkVersion:'(\d+)'", out)
    ver = re.search(r"versionName='([^']*)'", out)
    code = re.search(r"versionCode='(\d+)'", out)
    target = re.search(r"targetSdkVersion:'(\d+)'", out)
    pkg = re.search(r"package: name='([^']+)'", out)
    return {
        "permissions": perms,
        "minSdk": int(sdk.group(1)) if sdk else None,
        "versionName": ver.group(1) if ver else None,
        "versionCode": int(code.group(1)) if code else None,
        "targetSdk": int(target.group(1)) if target else None,
        "package": pkg.group(1) if pkg else None,
    }


FIRESTORE = ("https://firestore.googleapis.com/v1/projects/woustore-c9e0b/databases/(default)/documents/apps"
             "?pageSize=300&key=AIzaSyBbEay6vUZU9nCraZ3pZCmKpbMsweJ4aOM")


def _value(v):
    """Convertit une valeur Firestore (format REST) en valeur Python."""
    if "stringValue" in v:
        return v["stringValue"]
    if "booleanValue" in v:
        return v["booleanValue"]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return v["doubleValue"]
    if "arrayValue" in v:
        return [_value(x) for x in v["arrayValue"].get("values", [])]
    if "mapValue" in v:
        return {k: _value(x) for k, x in v["mapValue"].get("fields", {}).items()}
    return None


def published_apps():
    """Les applis validées par l'administrateur dans WouStore (collection « apps »)."""
    try:
        req = urllib.request.Request(FIRESTORE, headers={"User-Agent": "WouStore"})
        with urllib.request.urlopen(req, timeout=60) as r:
            docs = json.load(r).get("documents", [])
    except Exception as e:
        print("Firestore illisible :", e)
        return []
    apps = []
    for d in docs:
        app = {k: _value(v) for k, v in d.get("fields", {}).items()}
        app["id"] = d["name"].rsplit("/", 1)[-1]
        if app.get("github"):
            apps.append(app)
    print(len(apps), "appli(s) publiée(s) par des développeurs")
    return apps


# ---------- Anti-virus : VirusTotal (environ 70 anti-virus) ----------

VT_KEY = os.environ.get("VIRUSTOTAL_API_KEY", "")
VT = "https://www.virustotal.com/api/v3"
_vt_calls = [0]


def _vt(method, url, data=None, headers=None):
    """Appel à VirusTotal, en respectant la limite gratuite (4 appels par minute)."""
    import time
    if _vt_calls[0]:
        time.sleep(16)
    _vt_calls[0] += 1
    h = {"x-apikey": VT_KEY, "User-Agent": "WouStore"}
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, None


def sha256_of(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def _upload(path):
    import uuid
    size = os.path.getsize(path)
    url = VT + "/files"
    if size > 32 * 1024 * 1024:  # gros fichiers : adresse d'envoi spéciale
        st, js = _vt("GET", VT + "/files/upload_url")
        if st != 200:
            return False
        url = js["data"]
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        content = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"app.apk\"\r\n"
            f"Content-Type: application/octet-stream\r\n\r\n").encode() + content + f"\r\n--{boundary}--\r\n".encode()
    st, _ = _vt("POST", url, data=body, headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    return st == 200


def vt_scan(path, previous=None):
    """Résultat de l'analyse du fichier. Réutilise l'ancien résultat si le fichier n'a pas changé."""
    sha = sha256_of(path)
    if previous and previous.get("sha256") == sha and previous.get("status") == "done":
        return previous
    if not VT_KEY:
        return {"sha256": sha, "status": "disabled"}
    st, js = _vt("GET", f"{VT}/files/{sha}")
    if st == 200:
        stats = js["data"]["attributes"].get("last_analysis_stats", {})
        total = sum(v for v in stats.values() if isinstance(v, int))
        if total == 0:
            return {"sha256": sha, "status": "pending", "link": f"https://www.virustotal.com/gui/file/{sha}"}
        return {
            "sha256": sha,
            "status": "done",
            "malicious": stats.get("malicious", 0),
            "suspicious": stats.get("suspicious", 0),
            "engines": total,
            "link": f"https://www.virustotal.com/gui/file/{sha}",
        }
    if st == 404:  # jamais vu par VirusTotal : on l'envoie, résultat au prochain passage
        ok = _upload(path)
        return {"sha256": sha, "status": "pending" if ok else "error"}
    return {"sha256": sha, "status": "error", "code": st}


def submission_queue():
    """Les applis proposées en attente (seulement le dépôt GitHub : aucune donnée personnelle)."""
    url = FIRESTORE.replace("/documents/apps?", "/documents/submission_queue?")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "WouStore"})
        with urllib.request.urlopen(req, timeout=60) as r:
            docs = json.load(r).get("documents", [])
    except Exception as e:
        print("File d'attente illisible :", e)
        return []
    out = []
    for d in docs:
        q = {k: _value(v) for k, v in d.get("fields", {}).items()}
        q["docId"] = d["name"].rsplit("/", 1)[-1]
        if q.get("github"):
            out.append(q)
    return out


def scan_submissions(aapt):
    """Analyse les applis en attente ; le résultat va dans scans/<id>.json pour la page d'administration."""
    scans = pathlib.Path("scans")
    scans.mkdir(exist_ok=True)
    changed = False
    for q in submission_queue():
        dest = scans / f"{q['docId']}.json"
        previous = json.loads(dest.read_text()) if dest.exists() else None
        result = {"github": q["github"], "checkedAt": __import__("datetime").datetime.utcnow().isoformat() + "Z"}
        try:
            rel = api(f"https://api.github.com/repos/{q['github']}/releases/latest")
            pat = re.compile(q.get("asset") or r"\.(apk|xapk|apks|apkm)$")
            asset = next((a for a in rel["assets"] if pat.search(a["name"])), None)
            if asset is None:
                result.update({"status": "no_apk", "message": "Aucun fichier APK dans la dernière version publiée."})
            else:
                f = f"/tmp/queue-{q['docId']}"
                download(asset["browser_download_url"], f)
                result["file"] = asset["name"]
                result["size"] = asset["size"]
                result["tag"] = rel.get("tag_name")
                if asset["name"].lower().endswith(".apk"):
                    info = apk_info(f, aapt)
                    result["package"] = (re.search(r"package: name='([^']+)'", subprocess.run(
                        [aapt, "dump", "badging", f], capture_output=True, text=True).stdout) or [None, None])[1]
                    result["permissions"] = info["permissions"]
                result["scan"] = vt_scan(f, (previous or {}).get("scan"))
                os.remove(f)
        except Exception as e:
            result.update({"status": "error", "message": f"Dépôt ou version introuvable ({e})"})
        old = dict(previous or {})
        old.pop("checkedAt", None)
        new = dict(result)
        new.pop("checkedAt", None)
        if old != new:
            dest.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
            changed = True
            print("Proposition", q["docId"], ":", result.get("scan", {}).get("status", result.get("status")))
    return changed


def hold_suspicious_update(app, info, previous):
    """Surveillance après publication, comme Google Play : une nouvelle version suspecte
    n'est pas proposée. Les utilisateurs gardent la version précédente, déjà contrôlée."""
    reason = None
    if previous.get("cert") and info.get("cert") and previous["cert"] != info["cert"]:
        reason = "signature différente de la version précédente (fausse mise à jour possible)"
    scan = info.get("scan") or {}
    if scan.get("status") == "done" and (scan.get("malicious", 0) + scan.get("suspicious", 0)) >= 3:
        reason = f"{scan.get('malicious', 0) + scan.get('suspicious', 0)} anti-virus signalent un danger"
    if not reason:
        return info
    print(app["name"], ": nouvelle version retenue :", reason)
    if previous.get("release") and previous.get("cert"):
        kept = dict(previous)
        kept["heldUpdate"] = {"tag": (info.get("release") or {}).get("tag"), "reason": reason}
        return kept
    # Pas de version saine connue : l'appli est retirée du magasin.
    info["blocked"] = {"reason": reason}
    return info

def main():
    OUT.mkdir(exist_ok=True)
    catalog = json.load(open("catalog.json"))
    known = {a["id"] for a in catalog["apps"]}
    catalog["apps"] += [a for a in published_apps() if a["id"] not in known]
    aapt = find_aapt()
    META.mkdir(exist_ok=True)
    changed = False
    for app in catalog["apps"]:
        dest = OUT / f"{app['id']}.png"
        keep = app.get("keepIcon") and dest.exists()
        try:
            rel = api(f"https://api.github.com/repos/{app['github']}/releases/latest")
            pat = re.compile(app.get("asset", r"\.apk$"))
            asset = next(a for a in rel["assets"] if pat.search(a["name"]))
            apk = f"/tmp/{app['id']}.apk"
            download(asset["browser_download_url"], apk)
            info = apk_info(apk, aapt)
            # Tout ce dont WouStore a besoin pour télécharger, sans interroger l'API de GitHub
            # (limitée à 60 questions par heure et par adresse internet).
            info["release"] = {
                "tag": rel.get("tag_name"),
                "publishedAt": rel.get("published_at"),
                "notes": (rel.get("body") or "")[:4000],
                "assets": [
                    {"name": a["name"], "url": a["browser_download_url"], "size": a["size"]}
                    for a in rel.get("assets", [])
                ],
            }
            info["cert"] = apk_cert(apk, aapt)
            meta_file = META / f"{app['id']}.json"
            previous = json.loads(meta_file.read_text()) if meta_file.exists() else {}
            info["scan"] = vt_scan(apk, previous.get("scan"))
            info = hold_suspicious_update(app, info, previous)
            data = None if keep else icon_from_apk(apk, aapt)
            os.remove(apk)
        except Exception as e:  # une appli en erreur ne bloque pas les autres
            print(app["name"], ": erreur", e)
            continue

        meta = META / f"{app['id']}.json"
        text = json.dumps(info, ensure_ascii=False, indent=2) + "\n"
        if not meta.exists() or meta.read_text() != text:
            meta.write_text(text)
            changed = True
            print(app["name"], ": infos mises à jour", len(info["permissions"]), "autorisations")

        if keep:
            print(app["name"], ": logo fourni, gardé")
            continue
        if not data:
            # Icône dessinée en vectoriel dans l'APK : on prend le logo publié
            # par le créateur ailleurs (F-Droid, ou les fiches « fastlane » de son dépôt).
            data = icon_from_store_pages(app)
        if not data:
            print(app["name"], ": aucun logo trouvé")
            continue
        if not dest.exists() or dest.read_bytes() != data:
            dest.write_bytes(data)
            changed = True
            print(app["name"], ": logo mis à jour")
        else:
            print(app["name"], ": logo inchangé")
    if scan_submissions(aapt):
        changed = True
    print("CHANGED" if changed else "UNCHANGED")


if __name__ == "__main__":
    main()
