#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/dist/RSS NewsBar_0.2.1 beta.app"
dmg_path="$project_dir/dist/RSS-NewsBar-v0.2.1-beta.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/rssnewsbar-dmg.XXXXXX")

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

"$project_dir/scripts/build-app.sh"
cp -R "$app_dir" "$staging_dir/RSS NewsBar.app"
ln -s /Applications "$staging_dir/Applications"
cp "$project_dir/Resources/安装说明.txt" "$staging_dir/首次打开说明.txt"

hdiutil create \
    -volname "RSS NewsBar v0.2.1 beta" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

echo "$dmg_path"
