#!/usr/bin/env python3
"""Transforme le secret GOOGLE_SERVICES_JSON en valeurs de build Flutter.

Lit le JSON dans la variable d'environnement GOOGLE_SERVICES_JSON (jamais en
argument, jamais dans un fichier du dépôt).

  firebase_dart_defines.py <build.gradle[.kts]>          -> --dart-define=...
  firebase_dart_defines.py <build.gradle[.kts]> --masks  -> ::add-mask::...

Vérifie que le nom de package déclaré dans Firebase est celui de l'application
Android générée : sinon les notifications ne seraient jamais reçues.
"""
import json
import os
import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"::error title=Firebase::{message}")
    raise SystemExit(1)


def application_id(gradle: Path) -> str:
    match = re.search(r'applicationId\s*=?\s*["\']([^"\']+)["\']', gradle.read_text(encoding="utf-8"))
    if not match:
        fail("applicationId introuvable dans le Gradle de l'application.")
    return match.group(1)


def values(gradle: Path) -> dict:
    raw = os.environ.get("GOOGLE_SERVICES_JSON", "").strip()
    if not raw:
        fail("GOOGLE_SERVICES_JSON est vide.")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        fail("GOOGLE_SERVICES_JSON n'est pas un JSON valide (colle tout le contenu du fichier).")

    expected = application_id(gradle)
    clients = data.get("client") or []
    declared = []
    for client in clients:
        package = (client.get("client_info", {}).get("android_client_info", {}) or {}).get("package_name")
        declared.append(package)
        if package == expected:
            try:
                return {
                    "FIREBASE_API_KEY": client["api_key"][0]["current_key"],
                    "FIREBASE_APP_ID": client["client_info"]["mobilesdk_app_id"],
                    "FIREBASE_PROJECT_ID": data["project_info"]["project_id"],
                    "FIREBASE_MESSAGING_SENDER_ID": data["project_info"]["project_number"],
                }
            except (KeyError, IndexError):
                fail("GOOGLE_SERVICES_JSON est incomplet (clé API, identifiant d'appli ou projet manquant).")

    shown = ", ".join(p for p in declared if p) or "aucun"
    fail(
        f"le package Firebase ({shown}) ne correspond pas à l'application Android "
        f"({expected}). Crée l'appli Android dans Firebase avec exactement : {expected}"
    )


def main() -> None:
    if len(sys.argv) < 2:
        fail("usage : firebase_dart_defines.py <build.gradle[.kts]> [--masks]")
    result = values(Path(sys.argv[1]))
    if "--masks" in sys.argv[2:]:
        for value in result.values():
            print(f"::add-mask::{value}")
    else:
        for key, value in result.items():
            print(f"--dart-define={key}={value}")


if __name__ == "__main__":
    main()
