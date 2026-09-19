"""Crop the published FASHN sample collage; no model inference is performed.

Usage: python scripts/prepare-tryon-assets.py path/to/hero_collage.webp
Requires Pillow. Source and attribution are recorded in docs/TRYON_DEMO.md.
"""
import hashlib
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


source = Path(sys.argv[1])
source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
if source_hash != "18a042c7ed7984bea8d36beed18d7397306260df297ab549c130ec7f263ca088":
    raise ValueError("Source changed; inspect the collage before updating its digest and crops")
target = Path(__file__).resolve().parents[1] / "entry/src/main/resources/base/media"
collage = Image.open(source).convert("RGB")
if collage.size != (3410, 2482):
    raise ValueError("Unexpected source dimensions; review the crop coordinates first")

scenes = {
    "denim": [(4, 830, 578, 1650), (585, 830, 1123, 1650), (1129, 830, 1701, 1650)],
    "navy": [(1708, 830, 2281, 1650), (2288, 830, 2826, 1650), (2832, 830, 3406, 1650)],
    "red": [(4, 4, 578, 826), (585, 4, 1123, 826), (1129, 4, 1701, 826)],
}
font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 15)
for scene, boxes in scenes.items():
    for role, box in zip(("person", "garment", "result"), boxes):
        output = Image.new("RGB", (560, 832), "#f6f6f6")
        photo = ImageOps.contain(collage.crop(box), (560, 800), Image.Resampling.LANCZOS)
        output.paste(photo, ((560 - photo.width) // 2, (800 - photo.height) // 2))
        caption = "DEMO" if role == "result" else ("ORIGINAL" if role == "person" else "REFERENCE")
        ImageDraw.Draw(output).text((12, 807), caption + " | FASHN VTON 1.5", font=font, fill="#43434a")
        output.save(target / ("tryon_" + scene + "_" + role + ".jpg"), quality=94, subsampling=0)
print("Source SHA256:", source_hash)
print("Wrote 9 matched demo assets to", target)
