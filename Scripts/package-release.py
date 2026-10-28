#!/usr/bin/env python3
"""Build a distributable app archive without including local settings or logs."""

import hashlib
import json
import plistlib
import subprocess
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent.parent
    subprocess.run(["zsh", str(root / "Scripts/build-app.sh")], cwd=root, check=True)
    app = root / "dist/PromptRefiner.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    architecture = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip()
    if architecture != "arm64":
        raise SystemExit("This release package is for Apple Silicon (arm64).")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    if (app / "Contents/Resources/LICENSE.txt").read_bytes() != (root / "LICENSE").read_bytes():
        raise SystemExit("The app must contain its MIT license.")

    output = root / "dist/releases" / ("v" + version)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ("PromptRefiner-v" + version + "-macOS-arm64.zip")
    if archive.exists():
        archive.unlink()  # Replace only this generated versioned archive.
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(digest + "  " + archive.name + "\n")
    print(json.dumps({"version": version, "architecture": architecture, "archive": str(archive),
                      "bytes": archive.stat().st_size, "sha256": digest}, indent=2))


if __name__ == "__main__":
    main()
