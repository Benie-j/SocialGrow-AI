#!/usr/bin/env python3
"""Régénère les images de marque JUN AI à partir de app/branding/jun_mark.svg.

Dépendances (poste de développement uniquement, pas la CI) :
    pip install cairosvg pillow

Sorties dans app/branding/ :
    icon_background.png      fond de l'icône adaptive (encre + halo citron)
    icon_foreground.png      marque seule, calque adaptive (zone sûre respectée)
    icon_monochrome.png      marque blanche, icône thématique Android 13+
    icon_legacy.png          icône complète aux coins arrondis (Android < 8)
    play_store_icon_512.png  icône 512 px pour la fiche Google Play
    splash_mark_android12.png  marque pour l'écran de démarrage Android 12+
    splash_mark.png          marque pour l'écran de démarrage Android < 12
    splash_blank.png         image transparente de l'écran natif (la marque est animée en Flutter)
"""
from pathlib import Path
import io
import re

import cairosvg
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "app" / "branding"
SRC = OUT / "jun_mark.svg"
INK = "#111611"
LIME = "#C8F23A"

inner = re.search(r"<svg[^>]*>(.*)</svg>", SRC.read_text(encoding="utf-8"), re.S).group(1)
inner = re.sub(r"<title>.*?</title>|<!--.*?-->", "", inner, flags=re.S)


def svg(body: str, size: int) -> Image.Image:
    doc = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">{body}</svg>'
    png = cairosvg.svg2png(bytestring=doc.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def scaled(body: str, factor: float) -> str:
    return f'<g transform="translate(54 54) scale({factor}) translate(-54 -54)">{body}</g>'


background = f"""
<defs><radialGradient id="g" cx="0.85" cy="0.12" r="0.75">
  <stop offset="0" stop-color="{LIME}" stop-opacity=".30"/>
  <stop offset="1" stop-color="{LIME}" stop-opacity="0"/>
</radialGradient></defs>
<rect width="108" height="108" fill="{INK}"/><rect width="108" height="108" fill="url(#g)"/>"""

mono = re.sub(r'(fill|stroke)="#[0-9A-Fa-f]{6}"', r'\1="#FFFFFF"', inner)

svg(background, 1024).save(OUT / "icon_background.png")
svg(inner, 1024).save(OUT / "icon_foreground.png")
svg(mono, 1024).save(OUT / "icon_monochrome.png")

# Icône complète (sans zone sûre imposée) : la marque est agrandie.
full = svg(background + scaled(inner, 1.22), 1024)
mask = Image.new("L", (1024, 1024), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=230, fill=255)
legacy = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
legacy.paste(full, (0, 0), mask)
legacy.save(OUT / "icon_legacy.png")

svg(background + scaled(inner, 1.15), 512).save(OUT / "play_store_icon_512.png")

svg(inner, 1152).save(OUT / "splash_mark_android12.png")
svg(inner, 800).save(OUT / "splash_mark.png")

Image.new("RGBA", (288, 288), (0, 0, 0, 0)).save(OUT / "splash_blank.png")

print("Images de marque régénérées dans", OUT)
