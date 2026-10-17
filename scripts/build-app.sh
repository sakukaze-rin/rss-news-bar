#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/RSS NewsBar_0.2.2 beta.app"
icon_source="$project_dir/Resources/AppIcon.png"

cd "$project_dir"
if [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    CLANG_MODULE_CACHE_PATH="$build_dir/module-cache" \
    SWIFT_MODULECACHE_PATH="$build_dir/swift-module-cache" \
    swift build --disable-sandbox -c release --arch arm64 --arch x86_64
    executable="$build_dir/apple/Products/Release/RSSNewsBar"
else
    CLANG_MODULE_CACHE_PATH="$build_dir/module-cache" \
    SWIFT_MODULECACHE_PATH="$build_dir/swift-module-cache" \
    swift build --disable-sandbox -c release
    executable="$build_dir/release/RSSNewsBar"
fi

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$executable" "$app_dir/Contents/MacOS/RSSNewsBar"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

sips -s format icns "$icon_source" --out "$app_dir/Contents/Resources/AppIcon.icns" >/dev/null

codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
