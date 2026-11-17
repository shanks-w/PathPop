#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build/tests build/TestModuleCache build/tmp
export TMPDIR="$project_root/build/tmp/"

xcrun swiftc -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$project_root/build/TestModuleCache" \
  -framework AppKit -framework Carbon \
  PathPop/PathExtractor.swift \
  PathPop/AccessibilityPermission.swift \
  PathPop/SelectedTextReader.swift \
  PathPop/AppDelegate.swift \
  PathPop/HotKeyShortcut.swift \
  PathPop/GlobalHotKey.swift \
  PathPop/ShortcutSettingsWindowController.swift \
  Tests/TestMain.swift \
  -o build/tests/PathPopTests

build/tests/PathPopTests "$@"
