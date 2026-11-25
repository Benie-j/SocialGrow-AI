#!/usr/bin/env python3
from pathlib import Path
import re
import sys

manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "app/android/app/src/main/AndroidManifest.xml"
)

if not manifest.exists():
    raise SystemExit(f"ERREUR : manifeste introuvable : {manifest}")

content = manifest.read_text(encoding="utf-8")

if "socialgrowai" in content and "login-callback" in content:
    print("Deep link déjà présent.")
    raise SystemExit(0)

pattern = r'(<activity\b[^>]*android:name="[^"]*MainActivity"[^>]*>)([\s\S]*?)(</activity>)'
match = re.search(pattern, content)

if not match:
    raise SystemExit("Activité MainActivity introuvable.")

intent_filter = """
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="socialgrowai"
                      android:host="login-callback" />
            </intent-filter>
"""

updated = (
    content[:match.start()]
    + match.group(1)
    + match.group(2)
    + intent_filter
    + match.group(3)
    + content[match.end():]
)

manifest.write_text(updated, encoding="utf-8")
print("Deep link Android ajouté avec succès.")
