#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
scratch_dir="$project_dir/.build"
bundle_dir="$project_dir/dist/PowerClue.app"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/powerclue-clang-cache"
export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/powerclue-swift-cache"

cd "$project_dir"
swift build --disable-sandbox --configuration release --scratch-path "$scratch_dir"
mkdir -p "$bundle_dir/Contents/MacOS"
cp "$scratch_dir/release/PowerClue" "$bundle_dir/Contents/MacOS/PowerClue"
cat > "$bundle_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>PowerClue</string>
  <key>CFBundleIdentifier</key><string>app.powerclue.monitor</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>PowerClue</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle_dir"
echo "Built $bundle_dir"
