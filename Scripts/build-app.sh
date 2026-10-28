#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
swift build -c release
task_app="$task_root/dist/PromptRefiner.app"
# Recreate only this generated bundle so stale resources/signatures cannot leak in.
rm -rf -- "$task_app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_root/.build/release/PromptRefiner" "$task_app/Contents/MacOS/PromptRefiner"
cp "$task_root/Resources/Info.plist" "$task_app/Contents/Info.plist"
cp "$task_root/Resources/StatusIcon.pdf" "$task_app/Contents/Resources/StatusIcon.pdf"
cp "$task_root/Assets/AppIcon.png" "$task_app/Contents/Resources/Brandmark.png"
for task_resource in "$task_root"/.build/release/*.bundle(N); do
    cp -R "$task_resource" "$task_app/Contents/Resources/"
done
xcrun actool "$task_root/Assets/AppIcon.icon" --compile "$task_app/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "$task_root/.build/app-icon-info.plist" \
    --output-format human-readable-text
python3 - "$task_app/Contents/Info.plist" "$task_root/.build/app-icon-info.plist" <<'PY'
from pathlib import Path
import plistlib, sys
destination = Path(sys.argv[1])
info = plistlib.loads(destination.read_bytes())
info.update(plistlib.loads(Path(sys.argv[2]).read_bytes()))
destination.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - --identifier local.cherryai.prompt-refiner "$task_app"
codesign --verify --strict "$task_app"
print -r -- "$task_app"
