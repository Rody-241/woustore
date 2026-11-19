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
OUT.mkdir(exist_ok=True)


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


def icon_from_apk(apk, aapt):
    out = subprocess.run([aapt, "dump", "badging", apk], capture_output=True, text=True).stdout
    # application-icon-640:'res/xx.png'  → on garde les PNG, de la plus grande à la plus petite.
    icons = re.findall(r"application-icon-(\d+):'([^']+)'", out)
    icons.sort(key=lambda t: int(t[0]), reverse=True)
    with zipfile.ZipFile(apk) as z:
        names = set(z.namelist())
        for _, path in icons:
            if path.endswith(".png") and path in names:
                return z.read(path)
        # Icône adaptative seulement : on cherche une image ic_launcher en PNG.
        cands = [n for n in names if re.search(r"mipmap-[a-z]*hdpi[^/]*/ic_launcher\.png$", n)]
        cands.sort(key=lambda n: ("xxxhdpi" in n, "xxhdpi" in n, "xhdpi" in n), reverse=True)
        if cands:
            return z.read(cands[0])
    return None


def main():
    catalog = json.load(open("catalog.json"))
    aapt = find_aapt()
    changed = False
    for app in catalog["apps"]:
        dest = OUT / f"{app['id']}.png"
        if app.get("keepIcon") and dest.exists():
            print(app["name"], ": logo fourni, gardé")
            continue
        try:
            rel = api(f"https://api.github.com/repos/{app['github']}/releases/latest")
            pat = re.compile(app.get("asset", r"\.apk$"))
            asset = next(a for a in rel["assets"] if pat.search(a["name"]))
            apk = f"/tmp/{app['id']}.apk"
            download(asset["browser_download_url"], apk)
            data = icon_from_apk(apk, aapt)
            os.remove(apk)
        except Exception as e:  # une appli en erreur ne bloque pas les autres
            print(app["name"], ": erreur", e)
            continue
        if not data:
            print(app["name"], ": aucune image PNG dans l'APK")
            continue
        if not dest.exists() or dest.read_bytes() != data:
            dest.write_bytes(data)
            changed = True
            print(app["name"], ": logo mis à jour")
        else:
            print(app["name"], ": logo inchangé")
    print("CHANGED" if changed else "UNCHANGED")


main()
