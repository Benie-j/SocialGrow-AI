#!/usr/bin/env python3
"""Génère l'icône de notification Android (silhouette blanche) de JUN AI.

Android impose une petite icône blanche sur fond transparent : une icône
colorée s'afficherait en carré gris. On part de app/branding/icon_monochrome.png
(marque blanche), recadrée au plus juste, puis redimensionnée par densité.

Sorties : app/branding/notification/drawable-<densité>/ic_stat_jun.png
Dépendance : pillow uniquement.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "app" / "branding"
SRC = ROOT / "icon_monochrome.png"

# Taille de l'icône de notification : 24 dp.
DENSITIES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
PADDING = 0.10  # marge autour de la marque

mark = Image.open(SRC).convert("RGBA")
bbox = mark.getchannel("A").getbbox()
if bbox is None:
    raise SystemExit("ERREUR : icon_monochrome.png est vide.")
mark = mark.crop(bbox)

side = max(mark.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2))

for name, px in DENSITIES.items():
    inner = round(px * (1 - 2 * PADDING))
    icon = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    scaled = square.resize((inner, inner), Image.LANCZOS)
    icon.paste(scaled, ((px - inner) // 2, (px - inner) // 2), scaled)
    out = ROOT / "notification" / f"drawable-{name}"
    out.mkdir(parents=True, exist_ok=True)
    icon.save(out / "ic_stat_jun.png")

print("Icônes de notification générées dans", ROOT / "notification")
