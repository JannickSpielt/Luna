#!/usr/bin/env bash
# Erzeugt den Immich-API-Code in Packages/LilithKit/Sources/ImmichAPI/Generated
# aus openapi.json und openapi-generator-config.yaml.
#
# Neue Immich-Version: openapi.json ersetzen, z. B.
#   curl -L -o Packages/LilithKit/Sources/ImmichAPI/openapi.json \
#     https://raw.githubusercontent.com/immich-app/immich/vX.Y.Z/open-api/immich-openapi-specs.json
set -euo pipefail

GENERATOR_VERSION="1.10.3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="$ROOT/Packages/LilithKit/Sources/ImmichAPI"
TOOLS="${HOME}/Library/Caches/lilith-tools/swift-openapi-generator"

if [ ! -d "$TOOLS" ]; then
  git clone -q --depth 1 --branch "$GENERATOR_VERSION" \
    https://github.com/apple/swift-openapi-generator.git "$TOOLS"
fi

swift run -c release --package-path "$TOOLS" swift-openapi-generator generate \
  --config "$API_DIR/openapi-generator-config.yaml" \
  --output-directory "$API_DIR/Generated" \
  "$API_DIR/openapi.json"

echo "Fertig: $API_DIR/Generated"
