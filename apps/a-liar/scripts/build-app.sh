#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 2
fi

swift build -c "$configuration" --product ALIAR
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="build/APPLEPIE.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/ALIAR" "$app/Contents/MacOS/APPLEPIE"
cp Resources/Info.plist "$app/Contents/Info.plist"

# A persistent Developer ID / Apple Development signing identity is recommended.
# Ad-hoc signing is suitable for local iteration, but not stable TCC authorization.
identity="${APPLEPIE_SIGN_IDENTITY:-${ALIAR_SIGN_IDENTITY:--}}"
codesign --force --sign "$identity" --timestamp=none "$app"
codesign --verify --verbose=2 "$app"
echo "Built $app (signature: $identity)"
