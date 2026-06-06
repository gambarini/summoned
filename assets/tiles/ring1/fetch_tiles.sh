#!/usr/bin/env bash
# Fetch Ring 1 (The Pale Reaches) PixelLab tilesets into this folder.
# Run locally (Claude Code / your machine) — the Cowork sandbox cannot reach api.pixellab.ai.
#
#   cd assets/tiles/ring1 && bash fetch_tiles.sh
#
set -euo pipefail
cd "$(dirname "$0")"

# Ground -> Path (muted v2, KEEPER) — 16 Wang tiles, 32x32, high top-down
ID_GROUND_PATH="3769b303-59b4-4f70-945d-bfb58ea8a74c"
# Ground -> Flora (chained off same ground base) — 16 Wang tiles, 32x32, high top-down
ID_GROUND_FLORA="13fd8f44-82bd-4952-a431-d2ab0cabc728"
# Plateau/Cliff edges (plateau top reuses ground base) — 25 tiles, full-height transition
ID_CLIFF="30a69993-5a78-49ec-952f-3ffc3ae35a92"

base="https://api.pixellab.ai/mcp/tilesets"

echo "Downloading ground_path tileset ($ID_GROUND_PATH)..."
curl -fSL "$base/$ID_GROUND_PATH/image"    -o ground_path.png
curl -fSL "$base/$ID_GROUND_PATH/metadata" -o ground_path.metadata.json

echo "Downloading ground_flora tileset ($ID_GROUND_FLORA)..."
curl -fSL "$base/$ID_GROUND_FLORA/image"    -o ground_flora.png
curl -fSL "$base/$ID_GROUND_FLORA/metadata" -o ground_flora.metadata.json

echo "Downloading cliff tileset ($ID_CLIFF)..."
curl -fSL "$base/$ID_CLIFF/image"    -o cliff.png
curl -fSL "$base/$ID_CLIFF/metadata" -o cliff.metadata.json

echo "Done. Files:"
ls -la ground_path.png ground_path.metadata.json ground_flora.png ground_flora.metadata.json cliff.png cliff.metadata.json
