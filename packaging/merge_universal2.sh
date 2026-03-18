#!/bin/bash
# Merge arm64 and x86_64 .app bundles into a universal2 .app and create DMG
set -euo pipefail

trap 'echo "merge_universal2.sh failed at line $LINENO" >&2' ERR

ARM_APP="$1"
INTEL_APP="$2"
OUT_APP="$3"

if [ -z "$ARM_APP" ] || [ -z "$INTEL_APP" ] || [ -z "$OUT_APP" ]; then
    echo "Usage: $0 <arm64.app> <x86_64.app> <output.app>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="$(basename "$OUT_APP" .app)"
DMG_NAME="TgWsProxy"

echo "Starting universal2 merge"
echo "ARM_APP=$ARM_APP"
echo "INTEL_APP=$INTEL_APP"
echo "OUT_APP=$OUT_APP"
echo "DIST_DIR=$DIST_DIR"

if [ ! -d "$ARM_APP" ]; then
    echo "ARM app bundle not found: $ARM_APP" >&2
    exit 1
fi

if [ ! -d "$INTEL_APP" ]; then
    echo "Intel app bundle not found: $INTEL_APP" >&2
    exit 1
fi

has_arch() {
    local arches="$1"
    local target="$2"
    for arch in $arches; do
        if [ "$arch" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

is_subset() {
    local subset="$1"
    local superset="$2"
    for arch in $subset; do
        has_arch "$superset" "$arch" || return 1
    done
    return 0
}

# --- Merge ---

echo "Merging '$ARM_APP' + '$INTEL_APP' -> '$OUT_APP'"

rm -rf "$OUT_APP"
cp -R "$ARM_APP" "$OUT_APP"

find "$OUT_APP" -type f | while read -r file; do
    rel="${file#"$OUT_APP"/}"
    intel_file="$INTEL_APP/$rel"

    [ -f "$intel_file" ] || continue

    if file "$file" | grep -qE "Mach-O (64-bit )?executable|Mach-O (64-bit )?dynamically linked|Mach-O (64-bit )?bundle"; then
        arm_arch=$(lipo -archs "$file" 2>/dev/null || echo "")
        intel_arch=$(lipo -archs "$intel_file" 2>/dev/null || echo "")
        echo "Processing Mach-O: $rel"
        echo "  arm_arch=$arm_arch"
        echo "  intel_arch=$intel_arch"
        if [ -z "$arm_arch" ] || [ -z "$intel_arch" ]; then
            echo "  action=skip (unable to determine architecture)"
            continue
        fi
        if is_subset "$intel_arch" "$arm_arch"; then
            echo "  action=skip (arm binary already contains intel slices)"
            continue
        fi
        if is_subset "$arm_arch" "$intel_arch"; then
            echo "  action=copy-intel (intel binary is a superset)"
            cp "$intel_file" "$file"
            continue
        fi
        echo "  action=lipo-create"
        lipo -create "$file" "$intel_file" -output "$file"
        echo "  merged_arch=$(lipo -archs "$file" 2>/dev/null || echo "")"
    fi
done

echo "Merge done: $OUT_APP"

# --- Create DMG ---

DMG_TEMP="$DIST_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

cp -R "$OUT_APP" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME.dmg"

rm -rf "$DMG_TEMP"

echo "DMG created: $DIST_DIR/$DMG_NAME.dmg"
