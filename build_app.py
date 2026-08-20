#!/usr/bin/env python3
"""
构建 macOS .app 包（一体化脚本）

流程：安装依赖 → 打包 → [可选签名] → 清理临时文件
PyInstaller 会自动做 ad-hoc 签名，无需额外操作。
如需分发，可用 --sign / --sign-auto 用开发者证书重签。

用法:
    python3 build_app.py                    # 打包（PyInstaller 自动 ad-hoc 签名）
    python3 build_app.py --sign "Developer ID Application: ..."
    python3 build_app.py --sign-auto        # 自动查找钥匙串中的开发者证书
    python3 build_app.py --notarize         # 签名 + 公证（需开发者账号）
    python3 build_app.py --clean            # 只清理临时文件
    python3 build_app.py --no-clean         # 构建后不清理
"""

import os
import sys
import subprocess
import shutil
import argparse

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.path.join(PROJECT_DIR, "build_app")
DIST_DIR = os.path.join(PROJECT_DIR, "dist")
APP_NAME = "网络电台"
APP_BUNDLE = f"{APP_NAME}.app"


# ============================================================
# 工具函数
# ============================================================

def run(cmd, **kwargs):
    """运行命令，失败则抛出异常"""
    print(f"   $ {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    result = subprocess.run(cmd, **kwargs)
    if result.returncode != 0:
        raise RuntimeError(f"命令失败（退出码 {result.returncode}）")
    return result


# ============================================================
# 1. 安装依赖
# ============================================================

def step_install_deps():
    """安装必要的 Python 依赖"""
    print("\n" + "=" * 56)
    print("  1/4  安装依赖")
    print("=" * 56)

    deps = []

    # PyInstaller
    try:
        import PyInstaller
        print("  ✅ PyInstaller 已安装")
    except ImportError:
        deps.append("pyinstaller")

    # PyQt6
    try:
        import PyQt6
        print("  ✅ PyQt6 已安装")
    except ImportError:
        deps.append("PyQt6")

    # pyobjc（系统媒体集成，可选）
    has_pyobjc = False
    try:
        import MediaPlayer
        import AppKit
        has_pyobjc = True
        print("  ✅ pyobjc（媒体集成）已安装")
    except ImportError:
        print("  ℹ️  pyobjc 未安装（系统控制中心集成将不可用）")

    # pyobjc（系统通知，可选）
    has_notif = False
    try:
        import UserNotifications
        has_notif = True
        print("  ✅ pyobjc（系统通知）已安装")
    except ImportError:
        print("  ℹ️  pyobjc-framework-UserNotifications 未安装（换台通知将不可用）")

    if deps:
        print(f"\n  📦 正在安装：{', '.join(deps)}")
        run([sys.executable, "-m", "pip", "install"] + deps)
        print("  ✅ 依赖安装完成")

    return has_pyobjc, has_notif


# ============================================================
# 2. 打包
# ============================================================

def step_build(has_pyobjc, has_notif):
    """用 PyInstaller 打包"""
    print("\n" + "=" * 56)
    print("  2/4  打包（PyInstaller）")
    print("=" * 56)

    player_src = os.path.join(PROJECT_DIR, "Player.py")
    icon_src = os.path.join(PROJECT_DIR, "app_icon.icns")
    m3u_src = os.path.join(PROJECT_DIR, "radio.m3u")

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--windowed",
        "--name", APP_NAME,
        "--icon", icon_src,
        "--add-data", f"{m3u_src}:.",
        "--osx-bundle-identifier", "cn.zdeweb.app-stream-radio",
        "--target-arch", "arm64",
        "--distpath", DIST_DIR,
        "--workpath", os.path.join(BUILD_DIR, "work"),
        "--specpath", BUILD_DIR,
    ]

    if has_pyobjc:
        cmd += [
            "--hidden-import", "MediaPlayer",
            "--hidden-import", "AppKit",
            "--hidden-import", "Foundation",
            "--hidden-import", "objc",
        ]
    if has_notif:
        cmd += ["--hidden-import", "UserNotifications"]

    cmd.append(player_src)

    print("  运行 PyInstaller...")
    run(cmd, cwd=PROJECT_DIR)

    app_path = os.path.join(DIST_DIR, APP_BUNDLE)
    if not os.path.exists(app_path):
        raise RuntimeError(f"未找到生成的 app: {app_path}")

    # 计算大小
    size_mb = 0
    for root, dirs, files in os.walk(app_path):
        for f in files:
            try:
                size_mb += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    size_mb /= 1024 * 1024

    print(f"  ✅ 打包完成，大小：{size_mb:.1f} MB")
    return app_path


# ============================================================
# 3. 签名
# ============================================================

def find_developer_cert():
    """在钥匙串中查找可用的 Developer ID Application 证书"""
    try:
        result = subprocess.run(
            ["security", "find-identity", "-v", "-p", "codesigning"],
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.splitlines():
            line = line.strip()
            if "Developer ID Application" in line:
                # 格式: 1) HASH "Developer ID Application: Name (TEAMID)"
                parts = line.split('"', 2)
                if len(parts) >= 2:
                    return parts[1]
    except Exception:
        pass
    return None


def step_sign(app_path, sign_mode):
    """
    签名 app
    sign_mode:
        None        -> 不签名
        "-"         -> ad-hoc
        "证书名"     -> 用指定证书
        "auto"      -> 自动查找开发者证书
    """
    print("\n" + "=" * 56)
    print("  3/4  代码签名")
    print("=" * 56)

    if sign_mode is None:
        print("  ⏭️  跳过（未指定签名）")
        return

    identity = sign_mode
    if identity == "auto":
        identity = find_developer_cert()
        if not identity:
            print("  ⚠️  未找到开发者证书，回退到 ad-hoc 签名")
            identity = "-"
        else:
            print(f"  🔍 找到证书：{identity}")

    if identity == "-":
        print("  🔑 Ad-hoc 签名（仅本机可用）")
    else:
        print(f"  🔑 使用证书签名：{identity}")

    # 彻底清理资源分叉 / Finder 信息（解决 detritus not allowed 错误）
    # 方法：ditto 打包再解压，会剥离所有资源分叉
    print("  🧹 清理资源分叉...")
    import tempfile
    tmp_dir = tempfile.mkdtemp(prefix="radio_sign_")
    try:
        # 用 ditto 拷贝一份（自动剥离资源分叉）
        run([
            "ditto", "-V", "--noqtn", "--noextattr",
            app_path,
            os.path.join(tmp_dir, os.path.basename(app_path))
        ], capture_output=True)

        # 用清理后的副本替换原文件
        shutil.rmtree(app_path)
        shutil.move(
            os.path.join(tmp_dir, os.path.basename(app_path)),
            app_path
        )
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

    # --deep 递归签名所有内嵌框架和插件
    # --options runtime 启用 Hardened Runtime（公证需要）
    cmd = ["codesign", "--force", "--deep", "--verbose=1"]
    if identity != "-":
        cmd += ["--options", "runtime", "--entitlements", _entitlements_path()]
    cmd += ["--sign", identity, app_path]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        # 如果还是失败，尝试先签名所有内部的 dylib 和 framework，再签 app
        print("  ⚠️  首次签名失败，尝试分步签名...")
        _sign_nested(app_path, identity)
        run(cmd)
    else:
        # 输出简要信息
        for line in result.stderr.strip().splitlines()[-3:]:
            if line.strip():
                print(f"     {line.strip()}")

    # 验证签名
    verify_cmd = ["codesign", "-vvv", app_path]
    result = subprocess.run(verify_cmd, capture_output=True, text=True)
    if result.returncode == 0:
        print("  ✅ 签名验证通过")
    else:
        print(f"  ⚠️  签名验证输出：{result.stderr.strip()[:300]}")

    return identity


def _entitlements_path():
    """生成 entitlements 文件（Hardened Runtime 权限声明）"""
    path = os.path.join(BUILD_DIR, "RadioPlayer.entitlements")
    os.makedirs(BUILD_DIR, exist_ok=True)
    if os.path.exists(path):
        return path
    content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <false/>
    <key>CFBundleIdentifier</key>
    <string>cn.zdeweb.app-stream-radio</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
</dict>
</plist>
"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def _sign_nested(app_path, identity):
    """分步签名：先签所有内部二进制，再签外层 app"""
    # 找到所有 dylib、framework、插件，从内到外签名
    contents_dir = os.path.join(app_path, "Contents")

    # 收集所有需要签名的二进制
    binaries = []
    for root, dirs, files in os.walk(contents_dir):
        for f in files:
            fp = os.path.join(root, f)
            # .dylib、.so（Python 扩展）、插件
            if f.endswith((".dylib", ".so")):
                binaries.append(fp)
            # Unix 可执行文件（无扩展名）
            elif not f.startswith(".") and "." not in f:
                try:
                    with open(fp, "rb") as fh:
                        magic = fh.read(4)
                        # Mach-O 魔法数
                        if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
                                     b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
                            binaries.append(fp)
                except Exception:
                    pass

    # 逐个签名
    for bp in binaries:
        subprocess.run(
            ["codesign", "--force", "--sign", identity, bp],
            capture_output=True
        )


# ============================================================
# 4. 清理
# ============================================================

def step_clean():
    """清理临时构建文件"""
    print("\n" + "=" * 56)
    print("  4/4  清理临时文件")
    print("=" * 56)

    removed = []

    # build_app/work 工作目录
    work_dir = os.path.join(BUILD_DIR, "work")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
        removed.append("build_app/work/")

    # build_app 下的 .spec 和其他临时文件
    for f in os.listdir(BUILD_DIR) if os.path.isdir(BUILD_DIR) else []:
        fp = os.path.join(BUILD_DIR, f)
        if f.endswith(".spec"):
            os.remove(fp)
            removed.append(f"build_app/{f}")
        elif f == "Player.py":
            # 旧版脚本生成的副本
            os.remove(fp)
            removed.append(f"build_app/{f}")

    # __pycache__
    for root, dirs, files in os.walk(PROJECT_DIR):
        if "__pycache__" in dirs:
            pyc_dir = os.path.join(root, "__pycache__")
            # 只清顶层的，不动 site-packages
            if "site-packages" not in pyc_dir and "Frameworks" not in pyc_dir:
                shutil.rmtree(pyc_dir, ignore_errors=True)
                removed.append(os.path.relpath(pyc_dir, PROJECT_DIR) + "/")
            dirs.remove("__pycache__")

    if removed:
        for r in removed:
            print(f"  🗑  {r}")
        print(f"  ✅ 已清理 {len(removed)} 项")
    else:
        print("  ✅ 没有需要清理的临时文件")


# ============================================================
# 公证（可选高级功能）
# ============================================================

def step_notarize(app_path, apple_id, password, team_id):
    """提交 app 到 Apple 公证（需要开发者账号）"""
    print("\n" + "=" * 56)
    print("  附加  公证（Notarization）")
    print("=" * 56)

    # 先打包成 zip（公证需要 zip 或 dmg）
    zip_path = os.path.join(DIST_DIR, f"{APP_NAME}.zip")
    print("  📦 打包 zip...")
    if os.path.exists(zip_path):
        os.remove(zip_path)
    run([
        "ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
        app_path, zip_path
    ])

    # 提交公证
    print("  🔼 提交到 Apple 公证服务...")
    result = subprocess.run([
        "xcrun", "notarytool", "submit", zip_path,
        "--apple-id", apple_id,
        "--password", password,
        "--team-id", team_id,
        "--wait",
    ], capture_output=True, text=True, timeout=600)

    if result.returncode != 0:
        print(f"  ❌ 公证失败：{result.stderr}")
        return False

    print("  ✅ 公证通过")

    # staple 公证信息
    print("  📎 Stapling...")
    run(["xcrun", "stapler", "staple", app_path])
    print("  ✅ Staple 完成")

    # 清理 zip
    os.remove(zip_path)

    return True


# ============================================================
# 主流程
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="网络电台 - macOS App 一体化构建脚本",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python3 build_app.py                     打包（默认含 ad-hoc 签名）
  python3 build_app.py --sign-auto         用开发者证书重新签名
  python3 build_app.py --sign "Developer ID Application: ..."
  python3 build_app.py --clean             只清理临时文件
  python3 build_app.py --no-clean          构建完不清理
        """,
    )
    parser.add_argument("--no-sign", action="store_true",
                        help="不额外签名（PyInstaller 默认已做 ad-hoc，此参数无效但保留兼容）")
    parser.add_argument("--sign", metavar="IDENTITY",
                        help="用指定证书重新签名（开发者证书名，或 '-' 强制 ad-hoc）")
    parser.add_argument("--sign-auto", action="store_true",
                        help="自动查找钥匙串中的开发者证书重新签名")
    parser.add_argument("--notarize", action="store_true",
                        help="签名后提交公证（需 --apple-id 等参数）")
    parser.add_argument("--apple-id", metavar="EMAIL",
                        help="Apple ID 邮箱（公证用）")
    parser.add_argument("--password", metavar="PASSWORD",
                        help="App 专用密码（公证用）")
    parser.add_argument("--team-id", metavar="TEAMID",
                        help="团队 ID（公证用）")
    parser.add_argument("--clean", action="store_true",
                        help="只清理临时文件，不构建")
    parser.add_argument("--no-clean", action="store_true",
                        help="构建后不清理临时文件")
    args = parser.parse_args()

    # 纯清理模式
    if args.clean:
        step_clean()
        print()
        return

    print("=" * 56)
    print(f"  📻  {APP_NAME} - macOS App 构建")
    print("=" * 56)

    # 确定签名模式
    # 注意：PyInstaller 打包时会自动做 ad-hoc 签名，所以默认不重复签名
    if args.no_sign:
        sign_mode = None
    elif args.sign:
        sign_mode = args.sign
    elif args.sign_auto:
        sign_mode = "auto"
    else:
        # 默认跳过：PyInstaller 已经自动做过 ad-hoc 签名了
        sign_mode = None
        print("ℹ️  PyInstaller 会自动做 ad-hoc 签名，跳过额外签名步骤")
        print("   如需用开发者证书签名，请使用 --sign 或 --sign-auto")

    try:
        # 1. 依赖
        has_pyobjc, has_notif = step_install_deps()

        # 2. 打包（PyInstaller 会自动做 ad-hoc 签名）
        app_path = step_build(has_pyobjc, has_notif)

        # 3. 签名（仅当指定了签名模式时执行）
        identity = None
        if sign_mode is not None:
            identity = step_sign(app_path, sign_mode)

            # 公证（只有用开发者证书签名后才能公证）
            if args.notarize:
                if not args.apple_id or not args.password or not args.team_id:
                    print("\n⚠️  公证需要 --apple-id --password --team-id 参数，跳过")
                elif identity == "-" or identity is None:
                    print("\n⚠️  公证需要开发者证书签名（不能是 ad-hoc），跳过")
                else:
                    step_notarize(app_path, args.apple_id, args.password, args.team_id)

        # 4. 清理
        if not args.no_clean:
            step_clean()

        # 总结
        print("\n" + "=" * 56)
        print("  🎉 构建完成！")
        print("=" * 56)
        print(f"  App: {app_path}")

        import re
        size_mb = 0
        for root, dirs, files in os.walk(app_path):
            for f in files:
                try:
                    size_mb += os.path.getsize(os.path.join(root, f))
                except OSError:
                    pass
        print(f"  大小: {size_mb / 1024 / 1024:.1f} MB")

        if sign_mode is None:
            print("  签名: PyInstaller 自动 ad-hoc（本机可用）")
        elif identity == "-":
            print("  签名: Ad-hoc（本机可用，已重签）")
        else:
            print(f"  签名: {identity}")

        print()

    except RuntimeError as e:
        print(f"\n❌ 构建失败：{e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n⏹️  已取消", file=sys.stderr)
        sys.exit(130)


if __name__ == "__main__":
    main()
