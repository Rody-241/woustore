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
        cands.sort(key=lambda n: ("xxxhdpi" in n, "xxhdpi" in n, "xhdpi" in n), reverse=True)
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
    print("CHANGED" if changed else "UNCHANGED")


main()
