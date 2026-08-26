#!/bin/bash
# ============================================================
# 构建 Android APK 并拷贝到项目根目录
#
# 生成的 apk 为 debug 签名版（含 debug 签名），可直接安装到
# Android 设备；无需额外签名步骤。
#
# 产物命名：stream-radio-<系统>-<版本>-<架构>-<构建号>.apk
# 版本号从 build.gradle.kts 读取；构建号自增（与 iOS 共享计数）。
#
# 用法:
#     ./build_android.sh
#
# 依赖:
#     Android SDK + Gradle（用系统 gradle，或设置 GRADLE 环境变量
#     指定其他 gradle 命令，例如 GRADLE=./gradlew）
# ============================================================

set -e

# 脚本所在目录（支持从任意位置调用）
cd "$(dirname "$0")"

GRADLE_CMD="${GRADLE:-gradle}"
SYSTEM="android"
ARCH="universal"

# 版本号：从 app/build.gradle.kts 读取 versionName
VERSION=$(grep -m1 'versionName' android/app/build.gradle.kts | sed 's/.*"\([^"]*\)".*/\1/')

# 自增构建号（与 iOS 共享 .build_number 计数）
BUILD_NUM_FILE=".build_number"
BUILD_NUM=$(( $(cat "$BUILD_NUM_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$BUILD_NUM" > "$BUILD_NUM_FILE"

APK_NAME="stream-radio-${SYSTEM}-${VERSION}-${ARCH}-${BUILD_NUM}.apk"

echo "============================================================"
echo "  1/2  构建 debug APK（版本 ${VERSION} / 构建 #${BUILD_NUM}）"
echo "============================================================"

cd android
# clean：Gradle 9.7.1 增量编译缓存不可靠，必须干净构建
"$GRADLE_CMD" clean assembleDebug --console=plain

APP="app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APP" ]; then
    echo "❌ 未找到构建产物: $APP" >&2
    exit 1
fi

echo
echo "============================================================"
echo "  2/2  拷贝到项目根目录（覆盖旧版）"
echo "============================================================"

cd ..
rm -f "stream-radio-${SYSTEM}-"*.apk
cp "android/$APP" "$APK_NAME"

echo
echo "✅ 完成：$APK_NAME（$(du -h "$APK_NAME" | cut -f1)）"
echo "   安装到设备：adb install $APK_NAME"
