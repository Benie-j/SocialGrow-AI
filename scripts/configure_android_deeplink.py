#!/usr/bin/env python3
"""Configure le manifeste Android généré par `flutter create` (idempotent).

- permission INTERNET (absente du manifeste release par défaut) ;
- désactive le gestionnaire de liens intégré de Flutter (>= 3.27), qui entre
  en conflit avec le plugin de liens utilisé par supabase_flutter ;
- déclare le retour de la connexion Facebook : socialgrowai://login-callback.

Échoue explicitement si la structure du manifeste n'est pas celle attendue.
"""
from pathlib import Path
import re
import sys

manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "app/android/app/src/main/AndroidManifest.xml"
)

if not manifest.exists():
    raise SystemExit(f"ERREUR : manifeste introuvable : {manifest}")

content = manifest.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in content:
    index = content.find("<application")
    if index == -1:
        raise SystemExit("Balise <application> introuvable.")
    content = (
        content[:index]
        + '<uses-permission android:name="android.permission.INTERNET" />\n    '
        + content[index:]
    )

pattern = (
    r'(<activity\b[^>]*android:name="[^"]*MainActivity"[^>]*>)'
    r"([\s\S]*?)(</activity>)"
)
match = re.search(pattern, content)
if not match:
    raise SystemExit("Activité MainActivity introuvable.")
head, body, tail = match.groups()

additions = ""
if "flutter_deeplinking_enabled" not in body:
    additions += (
        '\n            <meta-data android:name="flutter_deeplinking_enabled"'
        ' android:value="false" />\n'
    )
if not ("socialgrowai" in body and "login-callback" in body):
    additions += """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="socialgrowai"
                      android:host="login-callback" />
            </intent-filter>
        """

content = content[: match.start()] + head + body + additions + tail + content[match.end():]
manifest.write_text(content, encoding="utf-8")

missing = [
    needle
    for needle in (
        "android.permission.INTERNET",
        'flutter_deeplinking_enabled" android:value="false"',
        'android:scheme="socialgrowai"',
        'android:host="login-callback"',
    )
    if needle not in content.replace("\n", " ").replace("  ", " ")
    and needle not in content
]
if missing:
    raise SystemExit(f"ERREUR : éléments absents du manifeste : {missing}")

print("Manifeste Android configuré (Internet, deep link, liens Flutter désactivés).")
