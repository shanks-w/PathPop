#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' PathPop/Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a three-part version in PathPop/Info.plist" >&2
    exit 1
fi

output="$project_root/build/releases/v$version"
mkdir -p "$output"
work=$(mktemp -d "$output/package.XXXXXX")
stage="$work/stage"
mkdir -p "$stage"
app="$stage/PathPop.app"
cleanup() {
    # Xcode may register the temporary build with Launch Services.
    local lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$lsregister" -u "$work/derived/Build/Products/Release/PathPop.app" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

xcodebuild -project PathPop.xcodeproj -scheme PathPop \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work/derived" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    GCC_GENERATE_DEBUGGING_SYMBOLS=NO SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
    build > "$output/build.log" 2>&1 || {
        tail -n 80 "$output/build.log"
        exit 1
    }

ditto "$work/derived/Build/Products/Release/PathPop.app" "$app"
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/PathPop" -verify_arch arm64 x86_64

ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE"
cat > "$stage/安装说明.txt" <<'EOF'
PathPop — Agent 给出路径，你一键找到文件。

要求：macOS 14.0 或更新版本，支持 Apple 芯片和 Intel Mac。

1. 把 PathPop.app 拖到 Applications（应用程序）文件夹。
2. 从“应用程序”启动 PathPop；它只显示菜单栏图标，没有主窗口或 Dock 图标。
3. 按提示开启辅助功能权限，选中本机路径后按 Control + Option + Command + R。

此版本使用 ad-hoc 签名，尚未使用 Apple Developer ID 签名或经过 Apple 公证。
如果 macOS 提示无法验证开发者，在确认下载来源是官方 GitHub Releases 后，
按 Apple 指引前往“系统设置 → 隐私与安全”，使用“仍要打开”并确认。
https://support.apple.com/zh-cn/102445
无需关闭系统安全功能。请安装到“应用程序”后再授权，不要从磁盘映像内长期运行。

更新前先从菜单栏退出旧版本。若更新后权限失效，在辅助功能列表中移除旧条目，
重新添加“应用程序”中的 PathPop 并启动。请只运行一个实例。

源码、使用说明和反馈：https://github.com/shanks-w/PathPop
许可证：MIT（应用内和本安装包均附 LICENSE）。
EOF

name="PathPop-$version-universal.dmg"
hdiutil create -volname "PathPop $version" -srcfolder "$stage" \
    -format UDZO -ov "$output/$name"
hdiutil verify "$output/$name"
(cd "$output" && shasum -a 256 "$name" > SHA256SUMS)
echo "Created: $output/$name"
