from PIL import Image
import os

SRC = os.path.expanduser("~/Downloads")
DST = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "warrior_8dir")
SIZE = (64, 64)

sources = {
    "south":      "warrior_base_S.png",
    "south-east": "warrior_base_SE.png",
    "east":       "warrior_base_E.png",
    "north-east": "warrior_base_NE.png",
    "north":      "warrior_base_N.png",
}
mirrors = {
    "west":       "east",
    "south-west": "south-east",
    "north-west": "north-east",
}

os.makedirs(DST, exist_ok=True)
scaled = {}
for stem, src_name in sources.items():
    img = Image.open(os.path.join(SRC, src_name)).convert("RGBA")
    img = img.resize(SIZE, Image.NEAREST)
    img.save(os.path.join(DST, f"{stem}.png"))
    scaled[stem] = img
    print(f"  {stem}.png  ← {src_name}")

for stem, source_stem in mirrors.items():
    img = scaled[source_stem].transpose(Image.FLIP_LEFT_RIGHT)
    img.save(os.path.join(DST, f"{stem}.png"))
    print(f"  {stem}.png  ← {source_stem}.png (mirrored)")
