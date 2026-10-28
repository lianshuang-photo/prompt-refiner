#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
swift build -c release
task_preview="$task_root/.build/ReadmePreviews.app"
mkdir -p "$task_preview/Contents/MacOS" "$task_preview/Contents/Resources"
cat > "$task_preview/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.prompt-refiner.readme-previews</string>
<key>CFBundleExecutable</key><string>ReadmePreviews</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cp "$task_root/Assets/AppIcon.png" "$task_preview/Contents/Resources/Brandmark.png"
for task_resource in "$task_root"/.build/release/*.bundle(N); do
    ditto "$task_resource" "$task_preview/Contents/Resources/${task_resource:t}"
done
task_sources=("$task_root"/Sources/PromptRefiner/**/*.swift)
task_sources=(${task_sources:#*/Main.swift})
xcrun swiftc -parse-as-library -swift-version 5 -I "$task_root/.build/release/Modules" -I "$task_root/Sources/CSQLite" \
    "$task_root/Scripts/ReadmePreviews.swift" "${task_sources[@]}" \
    "$task_root"/.build/release/RefinerCore.build/*.swift.o -lsqlite3 \
    -o "$task_preview/Contents/MacOS/ReadmePreviews"
"$task_preview/Contents/MacOS/ReadmePreviews" "$task_root/docs/images"
