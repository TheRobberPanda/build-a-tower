#!/usr/bin/env python3
"""Compose a 1920x1080 store thumbnail from an in-game capture.
Usage: compose_thumbnail.py raw.png out.png "TITLE" ["TAG"]"""
import sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

def fit(img, w=1920, h=1080):
    s = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))

def vignette(img):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse((-300, -200, img.width + 300, img.height + 200), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(160))
    return Image.composite(img, Image.new("RGB", img.size, (10, 15, 35)), mask)

def text(draw, xy, s, size, fill, anchor):
    f = ImageFont.truetype(FONT, size)
    draw.text((xy[0] + 8, xy[1] + 10), s, font=f, fill=(0, 0, 0), anchor=anchor, stroke_width=size // 9, stroke_fill=(0, 0, 0))
    draw.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=size // 9, stroke_fill=(20, 20, 40))

raw, out, title = sys.argv[1], sys.argv[2], sys.argv[3]
tag = sys.argv[4] if len(sys.argv) > 4 else None
img = fit(Image.open(raw).convert("RGB"))
img = ImageEnhance.Color(img).enhance(1.25)
img = ImageEnhance.Contrast(img).enhance(1.08)
img = vignette(img)
d = ImageDraw.Draw(img)
text(d, (960, 70), title, 150, (255, 214, 64), "mt")
if tag:
    text(d, (960, 1010), tag, 80, (255, 255, 255), "mb")
img.save(out)
print("saved", out)
