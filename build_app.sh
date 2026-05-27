#!/bin/bash

# 退出遇到错误时停止
set -e

APP_NAME="LarkFlow"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🚀 开始编译 $APP_NAME..."
swift build -c release

echo "📦 正在打包 $APP_BUNDLE..."
# 清理旧的 App
rm -rf "$APP_BUNDLE"

# 创建目录结构
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# 复制 Info.plist
cp "Info.plist" "$CONTENTS_DIR/"

# 对整个 App Bundle 做本地签名，让 macOS 权限系统稳定识别这个应用
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
echo "🔏 正在签名 $APP_BUNDLE..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "✅ 打包完成！"
echo "👉 请在终端运行: open $APP_BUNDLE"