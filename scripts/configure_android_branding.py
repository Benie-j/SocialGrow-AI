#!/usr/bin/env python3
"""Nomme l'application Android « JUN AI » dans le manifeste généré (idempotent).

`flutter create --project-name socialgrow_ai` nomme l'app d'après le projet :
on remplace ici le libellé visible (lanceur, multitâche, paramètres Android).
L'identifiant technique (applicationId, nom du package Dart) ne change pas.

Échoue explicitement si la structure du manifeste n'est pas celle attendue.
"""
from pathlib import Path
import re
import sys

LABEL = "JUN AI"

manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "app/android/app/src/main/AndroidManifest.xml"
)

if not manifest.exists():
    raise SystemExit(f"ERREUR : manifeste introuvable : {manifest}")

content = manifest.read_text(encoding="utf-8")

application = re.search(r"<application\b[^>]*>", content, re.S)
if not application:
    raise SystemExit("ERREUR : balise <application> introuvable.")

tag = application.group(0)
if re.search(r'android:label="[^"]*"', tag):
    new_tag = re.sub(r'android:label="[^"]*"', f'android:label="{LABEL}"', tag)
else:
    new_tag = tag.replace("<application", f'<application android:label="{LABEL}"', 1)

content = content.replace(tag, new_tag, 1)
manifest.write_text(content, encoding="utf-8")

if f'android:label="{LABEL}"' not in manifest.read_text(encoding="utf-8"):
    raise SystemExit("ERREUR : le libellé n'a pas été appliqué.")

print(f"Libellé de l'application : {LABEL}")
