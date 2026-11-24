"""Le portique automatique de WouStore, comme chez Google Play.

Chaque appli proposée passe une série de contrôles :
  - tout est vert  -> publiée automatiquement ;
  - un contrôle orange -> « À vérifier » dans la page d'administration ;
  - un contrôle rouge  -> refusée, avec la raison envoyée au développeur.

Lancé toutes les 15 minutes par le workflow « Portique ».
Il a besoin du secret FIREBASE_SERVICE_ACCOUNT (accès administrateur à Firestore).
"""
import datetime
import json
import os
import re
import subprocess
import sys
import unicodedata
import zipfile

sys.path.insert(0, os.path.dirname(__file__))
from fetch_icons import api, apk_cert, apk_info, download, find_aapt, vt_scan  # noqa: E402

import firebase_admin  # noqa: E402
from firebase_admin import credentials, firestore  # noqa: E402

GREEN, ORANGE, RED, WAIT = "green", "orange", "red", "wait"

# Autorisations qui demandent une justification, comme sur Google Play.
SENSITIVE = {
    "android.permission.READ_SMS": "lire les SMS",
    "android.permission.SEND_SMS": "envoyer des SMS",
    "android.permission.RECEIVE_SMS": "recevoir les SMS",
    "android.permission.READ_CALL_LOG": "lire le journal d'appels",
    "android.permission.WRITE_CALL_LOG": "modifier le journal d'appels",
    "android.permission.PROCESS_OUTGOING_CALLS": "intercepter les appels",
    "android.permission.ACCESS_BACKGROUND_LOCATION": "la position en arrière-plan",
    "android.permission.MANAGE_EXTERNAL_STORAGE": "accéder à tous les fichiers",
    "android.permission.BIND_ACCESSIBILITY_SERVICE": "le service d'accessibilité",
    "android.permission.REQUEST_INSTALL_PACKAGES": "installer d'autres applis",
    "android.permission.SYSTEM_ALERT_WINDOW": "s'afficher par-dessus les autres applis",
    "android.permission.QUERY_ALL_PACKAGES": "voir toutes les applis installées",
}

# Autorisations qui touchent aux données personnelles : elles doivent être déclarées.
PERSONAL = {
    "android.permission.ACCESS_FINE_LOCATION": "position",
    "android.permission.ACCESS_COARSE_LOCATION": "position",
    "android.permission.READ_CONTACTS": "contacts",
    "android.permission.CAMERA": "photos",
    "android.permission.RECORD_AUDIO": "audio",
    "android.permission.READ_MEDIA_IMAGES": "photos",
    "android.permission.READ_EXTERNAL_STORAGE": "fichiers",
}

# Marques connues : une appli qui reprend ces noms risque d'être une imitation.
BRANDS = [
    "whatsapp", "facebook", "messenger", "instagram", "tiktok", "youtube", "google", "gmail",
    "telegram", "snapchat", "twitter", "netflix", "spotify", "microsoft", "samsung", "tecno",
    "infinix", "itel", "huawei", "xiaomi", "airtel", "moov", "mtn", "orange money", "wave",
    "freefire", "free fire", "pubg", "minecraft", "roblox", "fortnite", "canal+", "paypal",
    "visa", "mastercard", "binance", "chatgpt", "openai", "claude",
]

# Contenus interdits (rouge) ou à vérifier (orange) dans le nom et la description.
FORBIDDEN = ["crack", "cracked", "mod apk", "piratage", "pirater", "hack compte", "carding",
             "faux billets", "arnaque", "keylogger", "espionner", "spy whatsapp"]
SUSPICIOUS = ["argent facile", "gagner de l'argent", "gratuit illimité", "illimité gratuit",
              "diamants gratuits", "free diamonds", "pari", "casino", "paris sportifs",
              "sexe", "porno", "adulte", "rencontre coquine"]


def norm(text):
    t = unicodedata.normalize("NFD", (text or "").lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9+ ]", " ", t)


def check(cid, label, level, message):
    return {"id": cid, "label": label, "level": level, "message": message}


def base_apk(path):
    """Un APK simple, ou l'APK principal d'une archive (XAPK, APKS, APKM)."""
    with zipfile.ZipFile(path) as z:
        if "AndroidManifest.xml" in z.namelist():
            return path
        apks = [n for n in z.namelist() if n.lower().endswith(".apk")]
        if not apks:
            return None
        base = next((n for n in apks if n.split("/")[-1].lower() == "base.apk"), None)
        if base is None:
            plain = [n for n in apks if not re.search(r"(^|/)(split|config\.)", n.lower())]
            base = max(plain or apks, key=lambda n: z.getinfo(n).file_size)
        out = path + ".base.apk"
        with open(out, "wb") as f:
            f.write(z.read(base))
        return out


def run_checks(sub, app, existing, aapt):
    """Tous les contrôles d'une appli proposée. Renvoie (contrôles, infos de l'APK)."""
    checks = []
    info = {}

    # 1. Fichier publié sur GitHub
    try:
        rel = api(f"https://api.github.com/repos/{app['github']}/releases/latest")
    except Exception:
        return [check("file", "Fichier", RED, "Aucune version publiée dans le dépôt GitHub « %s »." % app["github"])], info
    pat = re.compile(app.get("asset") or r"\.(apk|xapk|apks|apkm)$")
    asset = next((a for a in rel.get("assets", []) if pat.search(a["name"])), None)
    if asset is None:
        return [check("file", "Fichier", RED, "La dernière version GitHub ne contient aucun fichier APK.")], info
    path = f"/tmp/gate-{sub['id']}"
    download(asset["browser_download_url"], path)
    apk = base_apk(path)
    if apk is None:
        return [check("file", "Fichier", RED, "Le fichier publié n'est pas une appli Android lisible.")], info
    info = apk_info(apk, aapt)
    info["cert"] = apk_cert(apk, aapt)
    info["file"] = asset["name"]
    info["size"] = asset["size"]

    # 2. Nom de paquet identique à celui déclaré
    if info.get("package") != app["id"]:
        checks.append(check("package", "Nom de paquet", RED,
                            f"Le fichier contient « {info.get('package')} », pas « {app['id']} » comme déclaré."))
    else:
        checks.append(check("package", "Nom de paquet", GREEN, "Identique à la déclaration."))

    # 3. Paquet déjà utilisé par un autre développeur / nom déjà pris
    other = existing.get(app["id"])
    if other and other.get("owner") != sub.get("uid"):
        checks.append(check("unique", "Appli originale", RED, "Ce nom de paquet appartient déjà à une autre appli de WouStore."))
    elif any(norm(e.get("name")) == norm(app["name"]) for k, e in existing.items() if k != app["id"]):
        checks.append(check("unique", "Appli originale", RED, "Une autre appli de WouStore porte déjà ce nom."))
    else:
        checks.append(check("unique", "Appli originale", GREEN, "Nom et paquet disponibles."))

    # 4. Signature : la même que les versions déjà publiées (protection contre les fausses mises à jour)
    if other and other.get("cert") and info.get("cert") and other["cert"] != info["cert"]:
        checks.append(check("signature", "Signature", RED, "Signature différente de la version déjà publiée."))
    elif not info.get("cert"):
        checks.append(check("signature", "Signature", ORANGE, "Signature illisible."))
    else:
        checks.append(check("signature", "Signature", GREEN, "Fichier signé correctement."))

    # 5. Version d'Android visée assez récente (sécurité et vie privée)
    target = info.get("targetSdk") or 0
    if target and target < 30:
        checks.append(check("target", "Version d'Android visée", ORANGE,
                            f"L'appli vise Android API {target} : trop ancienne, elle contourne des protections récentes."))
    else:
        checks.append(check("target", "Version d'Android visée", GREEN, f"API {target or 'inconnue'}."))

    # 6. Anti-virus (VirusTotal)
    scan = vt_scan(path, (sub.get("checks_scan") or None))
    info["scan"] = scan
    bad = (scan.get("malicious") or 0) + (scan.get("suspicious") or 0)
    if scan.get("status") == "done":
        if bad == 0:
            checks.append(check("antivirus", "Anti-virus", GREEN, f"Aucune menace ({scan.get('engines')} anti-virus)."))
        elif bad <= 2:
            checks.append(check("antivirus", "Anti-virus", ORANGE, f"{bad} anti-virus sur {scan.get('engines')} signalent un risque."))
        else:
            checks.append(check("antivirus", "Anti-virus", RED, f"{bad} anti-virus sur {scan.get('engines')} signalent un danger."))
    elif scan.get("status") == "pending":
        checks.append(check("antivirus", "Anti-virus", WAIT, "Analyse VirusTotal en cours."))
    else:
        checks.append(check("antivirus", "Anti-virus", ORANGE, "Analyse anti-virus indisponible."))

    # 7. Autorisations sensibles : justification obligatoire, vérifiée par un humain
    perms = set(info.get("permissions") or [])
    sensitive = sorted({SENSITIVE[p] for p in perms if p in SENSITIVE})
    if sensitive:
        why = (app.get("permissionsWhy") or "").strip()
        checks.append(check("permissions", "Autorisations sensibles", ORANGE,
                            "Demande : " + ", ".join(sensitive) + ". Justification : " + (why or "aucune")))
    else:
        checks.append(check("permissions", "Autorisations sensibles", GREEN, "Aucune."))

    # 8. Sécurité des données : la déclaration doit correspondre à l'APK
    declared = set(app.get("dataCollected") or [])
    used = sorted({PERSONAL[p] for p in perms if p in PERSONAL})
    missing = [u for u in used if u not in declared]
    if declared and not (app.get("privacyUrl") or "").startswith("http"):
        checks.append(check("data", "Sécurité des données", RED,
                            "L'appli collecte des données mais n'a pas de politique de confidentialité."))
    elif missing:
        checks.append(check("data", "Sécurité des données", ORANGE,
                            "L'APK accède à : " + ", ".join(missing) + ", mais ce n'est pas déclaré."))
    else:
        checks.append(check("data", "Sécurité des données", GREEN, "Déclaration cohérente."))

    # 9. Imitation d'une marque connue
    text = norm(app["name"] + " " + app["id"].replace(".", " "))
    brands = [b for b in BRANDS if re.search(r"\b" + re.escape(b) + r"\b", text)]
    if brands:
        checks.append(check("brand", "Imitation", ORANGE, "Le nom rappelle : " + ", ".join(brands) + "."))
    else:
        checks.append(check("brand", "Imitation", GREEN, "Nom original."))

    # 10. Contenu de la fiche
    fiche = norm(" ".join([app.get("name", ""), app.get("tagline", ""), app.get("description", "")]))
    forbidden = [w for w in FORBIDDEN if norm(w) in fiche]
    suspicious = [w for w in SUSPICIOUS if norm(w) in fiche]
    if forbidden:
        checks.append(check("content", "Contenu de la fiche", RED, "Contenu interdit : " + ", ".join(forbidden) + "."))
    elif suspicious or app.get("ageRating") == "18":
        checks.append(check("content", "Contenu de la fiche", ORANGE,
                            "À vérifier : " + (", ".join(suspicious) if suspicious else "appli 18+") + "."))
    elif len((app.get("description") or "").strip()) < 40:
        checks.append(check("content", "Contenu de la fiche", RED, "Description trop courte (40 caractères minimum)."))
    else:
        checks.append(check("content", "Contenu de la fiche", GREEN, "Fiche complète."))

    for f in {path, apk}:
        if f and os.path.exists(f):
            os.remove(f)
    return checks, info


REPORTS_LIMIT = 5  # signalements de personnes différentes avant retrait automatique


def moderate_reports(db):
    """Comme Google Play : une appli signalée par plusieurs utilisateurs est retirée
    en attendant que l'administrateur vérifie (onglet Signalements)."""
    ids = {a["id"] for a in json.load(open("catalog.json"))["apps"]}
    ids |= {d.id for d in db.collection("apps").stream()}
    for app_id in ids:
        items = list(db.collection("reports").document(app_id).collection("items").stream())
        if len(items) < REPORTS_LIMIT:
            continue
        mod = db.collection("moderation").document(app_id)
        current = mod.get()
        if current.exists and (current.to_dict().get("blocked") or current.to_dict().get("cleared")):
            continue  # déjà retirée, ou rétablie par l'administrateur après vérification
        reasons = {}
        for it in items:
            r = it.to_dict().get("reason", "Autre")
            reasons[r] = reasons.get(r, 0) + 1
        mod.set({
            "blocked": True,
            "reason": f"Signalée par {len(items)} utilisateurs",
            "reasons": reasons,
            "at": datetime.datetime.now(datetime.timezone.utc),
        })
        print("Retirée après signalements :", app_id, reasons)


def main():
    cred = credentials.Certificate(json.loads(os.environ["FIREBASE_SERVICE_ACCOUNT"]))
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    aapt = find_aapt()
    moderate_reports(db)

    pending = list(db.collection("submissions").where("status", "==", "pending").stream())
    print(len(pending), "appli(s) à contrôler")
    if not pending:
        return

    # Les applis déjà dans WouStore (catalogue GitHub + publiées par des développeurs).
    existing = {}
    for a in json.load(open("catalog.json"))["apps"]:
        existing[a["id"]] = {"name": a["name"], "owner": None}
    for d in db.collection("apps").stream():
        existing[d.id] = {**d.to_dict(), "owner": d.to_dict().get("owner")}
    for a in list(existing):
        meta = f"meta/{a}.json"
        if os.path.exists(meta):
            existing[a]["cert"] = existing[a].get("cert") or json.load(open(meta)).get("cert")

    published = False
    for sub in pending:
        data = sub.to_dict()
        data["id"] = sub.id
        app = data.get("app") or {}
        print("-", app.get("name"), app.get("id"))
        try:
            checks, info = run_checks(data, app, existing, aapt)
        except Exception as e:  # une erreur sur une appli ne bloque pas les autres
            checks, info = [check("file", "Fichier", ORANGE, f"Contrôle impossible : {e}")], {}

        levels = {c["level"] for c in checks}
        now = datetime.datetime.now(datetime.timezone.utc)
        update = {"checks": checks, "checkedAt": now}
        if info.get("scan"):
            update["checks_scan"] = info["scan"]
        if RED in levels:
            update["status"] = "rejected"
            update["reason"] = " ".join(c["message"] for c in checks if c["level"] == RED)
            update["decidedBy"] = "portique"
        elif WAIT in levels:
            # On attend la fin de l'analyse anti-virus (au plus 24 heures).
            created = data.get("createdAt")
            if created and (now - created).total_seconds() > 24 * 3600:
                update["status"] = "review"
        elif ORANGE in levels:
            update["status"] = "review"
        else:
            update["status"] = "approved"
            update["decidedBy"] = "portique"
            db.collection("apps").document(app["id"]).set({
                **app,
                "owner": data.get("uid"),
                "cert": info.get("cert"),
                "publishedAt": now,
            })
            existing[app["id"]] = {"name": app["name"], "owner": data.get("uid"), "cert": info.get("cert")}
            published = True
        sub.reference.update(update)
        print("  ->", update.get("status", "pending"), [c["id"] + ":" + c["level"] for c in checks])

    if published:
        # Préparer tout de suite le logo et les liens de téléchargement.
        subprocess.run(["gh", "workflow", "run", "icons.yml", "--ref", "main"], check=False)


if __name__ == "__main__":
    main()
