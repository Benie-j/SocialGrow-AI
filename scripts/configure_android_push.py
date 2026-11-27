#!/usr/bin/env python3
"""Prépare le projet Android généré pour les notifications push (idempotent).

Usage : configure_android_push.py <dossier android> <dossier icônes>

- Gradle : minSdk 24, Java 11, desugaring (requis par flutter_local_notifications) ;
- manifeste : permission POST_NOTIFICATIONS (Android 13+), icône, couleur et
  canal par défaut des notifications ;
- ressources : icône de statut (silhouette blanche du J) et couleur d'accent.

Gère Gradle Kotlin (.kts) et Groovy. Échoue explicitement si la structure du
projet n'est pas celle attendue.
"""
from pathlib import Path
import re
import shutil
import sys

DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"
MIN_SDK = 24
CHANNEL_ID = "jun_alerts"
ICON = "ic_stat_jun"


def fail(message: str) -> None:
    raise SystemExit(f"ERREUR : {message}")


def notice(message: str) -> None:
    print(f"::notice title=push android::{message}")


def patch_gradle(path: Path) -> None:
    kotlin = path.suffix == ".kts"
    text = path.read_text(encoding="utf-8")
    done = []

    # minSdk : au moins 24 (Firebase Messaging et notifications locales).
    pattern = re.compile(r"(minSdk(?:Version)?)(\s*=?\s*)flutter\.minSdkVersion")
    if pattern.search(text):
        text = pattern.sub(rf"\g<1>\g<2>{MIN_SDK}", text, count=1)
        done.append(f"minSdk {MIN_SDK}")
    else:
        numeric = re.search(r"(minSdk(?:Version)?)(\s*=?\s*)(\d+)", text)
        if not numeric:
            fail("minSdk introuvable dans le Gradle de l'application.")
        if int(numeric.group(3)) < MIN_SDK:
            text = text.replace(numeric.group(0), f"{numeric.group(1)}{numeric.group(2)}{MIN_SDK}", 1)
            done.append(f"minSdk relevé à {MIN_SDK}")

    # Java 11 minimum.
    if "VERSION_1_8" in text:
        text = text.replace("VERSION_1_8", "VERSION_11")
        done.append("Java 11")

    # Desugaring.
    flag = "isCoreLibraryDesugaringEnabled = true" if kotlin else "coreLibraryDesugaringEnabled true"
    if "oreLibraryDesugaringEnabled" not in text:
        compile_options = re.search(r"compileOptions\s*\{", text)
        if not compile_options:
            fail("bloc compileOptions introuvable dans le Gradle de l'application.")
        text = text[: compile_options.end()] + f"\n        {flag}" + text[compile_options.end():]
        done.append("desugaring activé")

    dep = f'coreLibraryDesugaring("{DESUGAR}")' if kotlin else f"coreLibraryDesugaring '{DESUGAR}'"
    if "coreLibraryDesugaring(" not in text and "coreLibraryDesugaring '" not in text:
        block = re.search(r"^dependencies\s*\{", text, re.M)
        if block:
            text = text[: block.end()] + f"\n    {dep}" + text[block.end():]
        else:
            text = text.rstrip() + f"\n\ndependencies {{\n    {dep}\n}}\n"
        done.append("bibliothèque de desugaring")

    path.write_text(text, encoding="utf-8")
    check = path.read_text(encoding="utf-8")
    if "oreLibraryDesugaringEnabled" not in check or "desugar_jdk_libs" not in check:
        fail("le desugaring n'a pas été appliqué.")
    notice(f"{path.name} : " + (", ".join(done) if done else "déjà configuré"))


def patch_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    if "android.permission.POST_NOTIFICATIONS" not in text:
        index = text.find("<application")
        if index == -1:
            fail("balise <application> introuvable.")
        text = (
            text[:index]
            + '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    '
            + text[index:]
        )

    metas = {
        "com.google.firebase.messaging.default_notification_icon":
            f'android:resource="@drawable/{ICON}"',
        "com.google.firebase.messaging.default_notification_color":
            'android:resource="@color/jun_notification_color"',
        "com.google.firebase.messaging.default_notification_channel_id":
            f'android:value="{CHANNEL_ID}"',
    }
    additions = ""
    for name, value in metas.items():
        if name not in text:
            additions += f'        <meta-data android:name="{name}"\n            {value} />\n'
    if additions:
        close = text.rfind("</application>")
        if close == -1:
            fail("balise </application> introuvable.")
        text = text[:close] + additions + "    " + text[close:]

    path.write_text(text, encoding="utf-8")
    final = path.read_text(encoding="utf-8")
    for needed in ("POST_NOTIFICATIONS", "default_notification_icon", "default_notification_channel_id"):
        if needed not in final:
            fail(f"manifeste : {needed} absent après modification.")
    notice("manifeste : permission, icône, couleur et canal par défaut")


def install_resources(res: Path, icons: Path) -> None:
    copied = 0
    for density in sorted(icons.glob("drawable-*")):
        source = density / f"{ICON}.png"
        if not source.exists():
            continue
        target = res / density.name
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target / source.name)
        copied += 1
    if copied == 0:
        fail(f"aucune icône de notification trouvée dans {icons}.")

    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "jun_notification.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="jun_notification_color">#0F6B45</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    notice(f"icône de statut installée ({copied} densités)")


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage : configure_android_push.py <dossier android> <dossier icônes>")
    android = Path(sys.argv[1])
    icons = Path(sys.argv[2])

    gradle = next(
        (p for p in (android / "app" / "build.gradle.kts", android / "app" / "build.gradle") if p.exists()),
        None,
    )
    if gradle is None:
        fail(f"Gradle de l'application introuvable dans {android / 'app'}.")

    patch_gradle(gradle)
    patch_manifest(android / "app" / "src" / "main" / "AndroidManifest.xml")
    install_resources(android / "app" / "src" / "main" / "res", icons)
    print("Projet Android prêt pour les notifications push.")


if __name__ == "__main__":
    main()
