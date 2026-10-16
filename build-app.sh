#!/bin/bash
# 构建 MonitorBar.app（菜单栏 App，需要 .app bundle 才能以 LSUIElement 方式运行）
#
#   ./build-app.sh              release 构建 + 打包
#   ./build-app.sh --debug      debug 构建
#   ./build-app.sh --run        打包后直接启动
#   ./build-app.sh --install    打包后安装到 /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="release"
ACTION="build"
for arg in "$@"; do
  case "$arg" in
    --debug)   CONFIG="debug" ;;
    --release) CONFIG="release" ;;
    --run)     ACTION="run" ;;
    --install) ACTION="install" ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

echo "▸ Swift 构建 ($CONFIG, universal)…"
swift build -c "$CONFIG" --product MonitorBar --arch x86_64 --arch arm64

BIN_DIR="$(swift build -c "$CONFIG" --arch x86_64 --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/MonitorBar"
[ -f "$BIN" ] || { echo "找不到可执行文件: $BIN"; exit 1; }

APP="$ROOT/build/MonitorBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 组装 App Bundle…"
cp "$BIN" "$APP/Contents/MacOS/MonitorBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ 生成图标…"
ICONSET="$ROOT/build/MonitorBar.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Tools/make-icon.swift" "$ICONSET" >/dev/null 2>&1 && \
   iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/MonitorBar.icns" 2>/dev/null; then
  rm -rf "$ICONSET"
  echo "  图标已生成"
  # 触碰 App 的 mtime，提示 Launchpad/Dock 图标缓存失效
  touch "$APP"
else
  echo "  图标生成失败（不影响运行）"
  rm -rf "$ICONSET"
fi

echo "▸ Ad-hoc 签名…"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "✓ 完成: $APP"

case "$ACTION" in
  run)
    # 先停掉旧实例，避免两个图标
    pkill -x MonitorBar 2>/dev/null || true
    open "$APP"
    echo "▸ 已启动，在菜单栏右侧找(cpu 图标)"
    # 提示刷新图标缓存（仅在 run 时主动触发一次）
    if command -v killall >/dev/null 2>&1; then
      killall Dock 2>/dev/null || true
    fi
    ;;
  install)
    pkill -x MonitorBar 2>/dev/null || true
    rm -rf "/Applications/MonitorBar.app"
    cp -R "$APP" /Applications/
    echo "✓ 已安装到 /Applications/MonitorBar.app"
    open "/Applications/MonitorBar.app"
    if command -v killall >/dev/null 2>&1; then
      killall Dock 2>/dev/null || true
    fi
    ;;
esac
