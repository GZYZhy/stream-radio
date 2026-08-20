#!/bin/bash
# ============================================================
# 构建 iOS 未签名 .app 并打包成 .ipa
#
# 生成的 ipa 未签名，需用侧载工具（爱思助手 / Sideloadly /
# AltStore 等）配合 Apple ID 重新签名后安装到 iPhone / iPad。
# 免费 Apple ID 签名为 7 天有效期，到期需重新签名安装。
#
# 用法:
#     ./build_ios.sh
#
# 依赖:
#     Xcode（含 iPhone SDK）
# ============================================================

set -e

# 脚本所在目录（支持从任意位置调用）
cd "$(dirname "$0")"

PROJECT="ios/stream-radio/stream-radio.xcodeproj"
SCHEME="stream-radio"
CONFIG="Release"
SDK="iphoneos"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_NAME="stream-radio"
IPA_NAME="stream-radio.ipa"

echo "============================================================"
echo "  1/2  构建未签名 .app（${SDK} / ${CONFIG}）"
echo "============================================================"

xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk "$SDK" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

APP="$DERIVED_DATA/Build/Products/Release-iphoneos/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "❌ 未找到构建产物: $APP" >&2
    exit 1
fi

echo
echo "============================================================"
echo "  2/2  打包 .ipa"
echo "============================================================"

rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"
# 清掉可能的 macOS 垃圾文件
find "$BUILD_DIR/Payload" -name ".DS_Store" -delete

rm -f "$IPA_NAME"
# -X 去掉扩展属性，保证 ipa 干净（不被侧载工具误判）
(cd "$BUILD_DIR" && zip -r -X -q "../$IPA_NAME" Payload)

echo
echo "✅ 完成：$IPA_NAME（$(du -h "$IPA_NAME" | cut -f1)）"
echo "   该 ipa 未签名，请用爱思助手 / Sideloadly / AltStore 等工具"
echo "   配合你的 Apple ID 重新签名后安装。"
