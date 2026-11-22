"""Prépare le dossier Android généré par `flutter create` pour WouStore.
Appelé par le workflow GitHub."""
import pathlib
import re
import shutil

# 1. Manifeste : permissions, nom, fournisseur Shizuku.
path = pathlib.Path("android/app/src/main/AndroidManifest.xml")
xml = path.read_text()

perms = [
    "android.permission.INTERNET",
    "android.permission.REQUEST_INSTALL_PACKAGES",
    "android.permission.QUERY_ALL_PACKAGES",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.REQUEST_DELETE_PACKAGES",
]
lines = "".join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in xml
)
if lines:
    xml = xml.replace("<application", lines + "    <application", 1)

xml = xml.replace('android:label="woustore"', 'android:label="WouStore"')

provider = """        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="${applicationId}.shizuku"
            android:multiprocess="false"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
"""
if "ShizukuProvider" not in xml:
    xml = xml.replace("</application>", provider + "    </application>", 1)
path.write_text(xml)
print(xml)

# 2. Gradle : Android 13 comme cible (installateurs Tecno/HiOS), Android 7 minimum,
#    et la bibliothèque Shizuku.
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = pathlib.Path(name)
    if not g.exists():
        continue
    txt = g.read_text()
    txt = re.sub(r"targetSdk\s*=\s*flutter\.targetSdkVersion", "targetSdk = 33", txt)
    txt = re.sub(r"targetSdkVersion\s+flutter\.targetSdkVersion", "targetSdkVersion 33", txt)
    txt = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", txt)
    txt = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", txt)
    if "dev.rikka.shizuku" not in txt:
        if name.endswith(".kts"):
            txt += """
dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
"""
        else:
            txt += """
dependencies {
    implementation 'dev.rikka.shizuku:api:13.1.5'
    implementation 'dev.rikka.shizuku:provider:13.1.5'
}
"""
    g.write_text(txt)
    print(name, "->", [l.strip() for l in txt.splitlines() if "Sdk" in l or "shizuku" in l])

# 3. Règles R8 : garder Shizuku (méthode appelée par réflexion).
pathlib.Path("android/app/proguard-rules.pro").write_text(
    "-keep class rikka.shizuku.** { *; }\n-keep class moe.shizuku.** { *; }\n"
)

# 4. Code Kotlin (installation, Shizuku, notifications).
kt_dir = pathlib.Path("android/app/src/main/kotlin/com/woustore/woustore")
kt_dir.mkdir(parents=True, exist_ok=True)
for old in pathlib.Path("android/app/src/main").rglob("MainActivity.*"):
    old.unlink()
shutil.copy("android_src/MainActivity.kt", kt_dir / "MainActivity.kt")
print("Kotlin :", kt_dir / "MainActivity.kt")

# 5. Icône WouStore.
src = pathlib.Path("android_res")
dst = pathlib.Path("android/app/src/main/res")
for f in src.rglob("*.xml"):
    target = dst / f.relative_to(src)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(f, target)
    print("icône :", target)
