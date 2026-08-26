#!/bin/bash
# ============================================================
# 构建 macOS 通用版（arm64 + x86_64）并打包成 .zip
#
# 生成的 zip 内含 网络电台.app，未签名，可直接在 macOS 上运行。
# 未签名版本首次打开可能需要右键 → 打开，或在系统设置 →
# 隐私与安全性 中允许运行。
#
# 用法:
#     ./build_macos.sh
#
# 依赖:
#     Xcode（含 macOS SDK）
# ============================================================

set -e

# 脚本所在目录（支持从任意位置调用）
cd "$(dirname "$0")"

PROJECT="ios/stream-radio/stream-radio.xcodeproj"
SCHEME="stream-radio"
CONFIG="Release"
SDK="macosx"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/macos-derived"
# 产物名来自 pbxproj 里 PRODUCT_NAME（macOS 为「网络电台」）
APP_NAME="网络电台"

SYSTEM="macOS"
ARCH="universal"
# 版本号：从 pbxproj 读取 MARKETING_VERSION
VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
# 自增构建号（与 iOS / Android 共享 .build_number 计数）
BUILD_NUM_FILE=".build_number"
BUILD_NUM=$(( $(cat "$BUILD_NUM_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$BUILD_NUM" > "$BUILD_NUM_FILE"
# 产物用英文前缀（与 ipa/apk 命名一致，也避免 GitHub release 中文文件名编码问题）；
# App 内部名称仍为「网络电台」（用户在 Dock / 菜单栏看到的是中文）
ZIP_NAME="stream-radio-${SYSTEM}-${VERSION}-${ARCH}-${BUILD_NUM}.zip"

echo "============================================================"
echo "  1/2  构建 macOS ${ARCH}（${SDK} / ${CONFIG}）"
echo "============================================================"

xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk "$SDK" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

APP="$DERIVED_DATA/Build/Products/${CONFIG}/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
    echo "❌ 未找到构建产物: $APP" >&2
    exit 1
fi

# 校验架构
ARCHS_FOUND=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || echo "")
echo
echo "  可执行文件架构: $ARCHS_FOUND"

echo
echo "============================================================"
echo "  2/2  打包 zip 并拷贝到项目根目录"
echo "============================================================"

# 清掉可能的 macOS 垃圾文件
find "$APP" -name ".DS_Store" -delete
# 清掉旧产物
rm -f "网络电台-${SYSTEM}-${VERSION}-"*.zip

# ditto 打 zip：保留资源分支和 Finder 信息，与 macOS 系统压缩一致
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_NAME"

echo
echo "✅ 完成：$ZIP_NAME（$(du -h "$ZIP_NAME" | cut -f1)）"
echo "   架构：$ARCHS_FOUND"
echo "   未签名版本首次打开：右键 → 打开，或在 系统设置 → 隐私与安全性 中允许"
