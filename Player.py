#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
轻量网络电台播放器
- 界面 + 播放：PyQt6 (QtMultimedia)
- 电台来源：radio.m3u（可在界面中增删改）
- 时钟（精确到 0.1 秒）
- 电台录制（MP3，需系统安装 ffmpeg），可自定义保存目录
- 菜单栏、系统媒体控制中心集成（macOS）
- 单文件，依赖缺失时自动安装
- 跨平台：macOS / Windows / Linux
"""

import os
import sys
import re
import subprocess
import time
import json
import shutil
import logging
from datetime import datetime


# ============================================================
# 日志（已停用：所有 log.xxx 调用均为空操作，不写文件、不输出控制台）
# ============================================================

log = logging.getLogger("radio")
log.addHandler(logging.NullHandler())
log.propagate = False


def _enum_info(v):
    """把 PyQt6 枚举转成「名称 (数值)」字符串，普通对象则直接 str()。

    注意：PyQt6 的枚举（如 QMediaPlayer.PlaybackState）不是 int 的子类，
    不能直接 int()，否则会抛 TypeError；用 .value 取数值最稳妥。
    """
    try:
        return f"{v} ({v.value})"
    except Exception:
        return str(v)


# ============================================================
# 自动安装依赖
# ============================================================

def _ensure_pyqt6():
    """确保 PyQt6 可用，否则自动通过 pip 安装"""
    try:
        import PyQt6  # noqa: F401
        log.info("PyQt6 已就绪")
        return
    except ImportError:
        log.warning("未检测到 PyQt6，准备自动安装")

    print("正在安装依赖：PyQt6（首次运行需要几分钟）...", flush=True)
    try:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "PyQt6"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        print(f"自动安装失败：{e}", file=sys.stderr)
        print("请手动运行：pip install PyQt6", file=sys.stderr)
        sys.exit(1)


_ensure_pyqt6()

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QListWidget, QListWidgetItem, QPushButton, QLabel, QSlider,
    QGroupBox, QMessageBox, QInputDialog, QFileDialog, QMenuBar,
    QMenu, QDialog, QTabWidget, QCheckBox, QSpinBox, QProgressBar,
    QSystemTrayIcon, QLineEdit, QComboBox, QFrame,
    QDialogButtonBox, QFormLayout,
)
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput
from PyQt6.QtGui import QAction, QKeySequence, QIcon, QShortcut, QColor
from PyQt6.QtCore import QUrl, Qt, QTimer, QSettings


# ============================================================
# 系统媒体集成（macOS NowPlaying / 媒体键）
# ============================================================

class SystemMediaIntegration:
    """
    macOS 系统媒体控制集成：
    - 同步"正在播放"信息到控制中心
    - 响应系统播放/暂停/上下曲按键
    需要 pyobjc（MediaPlayer / AppKit），不可用时静默降级
    """

    def __init__(self, window):
        self.window = window
        self.enabled = False
        self._info_center = None
        self._cmd_center = None
        self._notif_center = None
        self._setup()

    def _setup(self):
        if sys.platform != "darwin":
            log.info("系统媒体集成: 非 macOS（%s），跳过", sys.platform)
            return
        log.info("系统媒体集成: 开始初始化（macOS）")
        try:
            from MediaPlayer import (
                MPNowPlayingInfoCenter,
                MPNowPlayingInfoPropertyPlaybackRate,
                MPNowPlayingInfoPropertyElapsedPlaybackTime,
                MPMediaItemPropertyTitle,
                MPMediaItemPropertyArtist,
                MPMediaItemPropertyPlaybackDuration,
                MPRemoteCommandCenter,
                MPRemoteCommandHandlerStatusSuccess,
            )
            from AppKit import NSApplication, NSImage
            from MediaPlayer import MPMediaItemPropertyArtwork, MPMediaItemArtwork

            self._MPNowPlayingInfoCenter = MPNowPlayingInfoCenter
            self._MPMediaItemPropertyTitle = MPMediaItemPropertyTitle
            self._MPMediaItemPropertyArtist = MPMediaItemPropertyArtist
            self._MPMediaItemPropertyPlaybackDuration = MPMediaItemPropertyPlaybackDuration
            self._MPMediaItemPropertyArtwork = MPMediaItemPropertyArtwork
            self._MPNowPlayingInfoPropertyPlaybackRate = MPNowPlayingInfoPropertyPlaybackRate
            self._MPNowPlayingInfoPropertyElapsedPlaybackTime = MPNowPlayingInfoPropertyElapsedPlaybackTime
            self._MPMediaItemArtwork = MPMediaItemArtwork
            self._NSImage = NSImage

            # 生成封面（用 app 图标）
            self._artwork = self._create_artwork()

            info_center = MPNowPlayingInfoCenter.defaultCenter()
            cmd_center = MPRemoteCommandCenter.sharedCommandCenter()

            # 绑定系统命令
            def play_handler(_event):
                self.window._toggle_play()
                return 0  # MPRemoteCommandHandlerStatusSuccess

            def pause_handler(_event):
                self.window._toggle_play()
                return 0

            def stop_handler(_event):
                self.window.stop()
                return 0

            def next_handler(_event):
                self.window.next()
                return 0

            def prev_handler(_event):
                self.window.prev()
                return 0

            cmd_center.playCommand().addTargetWithHandler_(play_handler)
            cmd_center.pauseCommand().addTargetWithHandler_(pause_handler)
            cmd_center.stopCommand().addTargetWithHandler_(stop_handler)
            cmd_center.nextTrackCommand().addTargetWithHandler_(next_handler)
            cmd_center.previousTrackCommand().addTargetWithHandler_(prev_handler)

            self._info_center = info_center
            self.enabled = True
            log.info("系统媒体集成: 初始化成功")
        except Exception as e:
            log.warning("系统媒体集成不可用（跳过）: %s", e)
            print(f"系统媒体集成不可用（跳过）：{e}", file=sys.stderr)
            self.enabled = False

        # 系统通知（换台提示），独立于媒体集成，失败不影响播放
        try:
            import UserNotifications
            center = UserNotifications.UNUserNotificationCenter.currentNotificationCenter()

            def _auth_done(granted, _error):
                log.info("系统通知授权结果: granted=%s", granted)

            center.requestAuthorizationWithOptions_completionHandler_(
                UserNotifications.UNAuthorizationOptionAlert | UserNotifications.UNAuthorizationOptionSound,
                _auth_done,
            )
            self._notif_center = center
            log.info("系统通知: 初始化成功")
        except Exception as e:
            log.warning("系统通知不可用（跳过）: %s", e)
            self._notif_center = None

    def _create_artwork(self):
        """用 app 图标生成控制中心显示的封面"""
        try:
            from PyQt6.QtGui import QPixmap, QImage
            from PyQt6.QtCore import QSize

            # 优先用 app 的窗口图标
            icon = self.window.windowIcon()
            if icon.isNull():
                # 没有的话画一个简单的蓝色圆形图标
                pix = QPixmap(512, 512)
                pix.fill(Qt.GlobalColor.transparent)
                from PyQt6.QtGui import QPainter, QColor, QBrush, QPen
                from PyQt6.QtCore import Qt as QtCoreQt
                p = QPainter(pix)
                p.setRenderHint(QPainter.RenderHint.Antialiasing)
                p.setBrush(QColor("#007AFF"))
                p.setPen(QtCoreQt.PenStyle.NoPen)
                p.drawEllipse(10, 10, 492, 492)
                p.setPen(QPen(QColor("white"), 6))
                f = p.font()
                f.setPointSize(200)
                f.setBold(True)
                p.setFont(f)
                p.drawText(pix.rect(), QtCoreQt.AlignmentFlag.AlignCenter, "📻")
                p.end()
                icon = QIcon(pix)

            # QIcon → QPixmap → NSImage → MPMediaItemArtwork
            pixmap = icon.pixmap(QSize(512, 512))
            qimg = pixmap.toImage()

            # 转成 NSImage（通过 PNG 数据中转）
            from PyQt6.QtCore import QByteArray, QBuffer
            ba = QByteArray()
            buf = QBuffer(ba)
            buf.open(QBuffer.OpenModeFlag.WriteOnly)
            qimg.save(buf, "PNG")
            buf.close()

            import Foundation

            data = bytes(ba.data())
            nsdata = Foundation.NSData.dataWithBytes_length_(data, len(data))
            if nsdata is None:
                return None

            nsimage = self._NSImage.alloc().initWithData_(nsdata)
            if nsimage is None:
                return None

            # 创建 MPMediaItemArtwork
            try:
                import Quartz.CoreGraphics as CG

                def _handler(size):
                    return nsimage

                size = CG.CGSizeMake(512, 512)
                artwork = self._MPMediaItemArtwork.alloc().initWithBoundsSize_requestHandler_(
                    size,
                    _handler,
                )
                return artwork
            except ImportError:
                print("[封面] 缺少 Quartz 框架（pip install pyobjc-framework-Quartz），跳过封面", file=sys.stderr)
                return None
        except Exception as e:
            print(f"[封面] 生成失败: {e}", file=sys.stderr)
            return None

    def update_now_playing(self, title, artist=None, duration=None, is_playing=False, position=0):
        """更新系统控制中心的播放信息"""
        if not self.enabled or not self._info_center:
            return
        try:
            import Foundation
            info = Foundation.NSMutableDictionary.dictionary()

            if title:
                info[self._MPMediaItemPropertyTitle] = title
            if artist:
                info[self._MPMediaItemPropertyArtist] = artist
            if duration and duration > 0:
                info[self._MPMediaItemPropertyPlaybackDuration] = duration

            info[self._MPNowPlayingInfoPropertyPlaybackRate] = 1.0 if is_playing else 0.0
            info[self._MPNowPlayingInfoPropertyElapsedPlaybackTime] = position

            # 封面
            if hasattr(self, '_artwork') and self._artwork is not None:
                info[self._MPMediaItemPropertyArtwork] = self._artwork

            self._info_center.setNowPlayingInfo_(info)
        except Exception:
            pass

    def notify(self, title, body):
        """推送一条系统通知（换台提示，类似 Apple Music）"""
        if not self._notif_center:
            return
        try:
            import UserNotifications
            content = UserNotifications.UNMutableNotificationContent.alloc().init()
            content.setTitle_(title)
            content.setBody_(body)
            # 固定标识：换台时替换旧通知，避免通知中心堆积
            request = UserNotifications.UNNotificationRequest.requestWithIdentifier_content_trigger_(
                "now-playing", content, None
            )
            self._notif_center.addNotificationRequest_withCompletionHandler_(request, None)
        except Exception:
            log.exception("推送系统通知失败")

    def clear(self):
        """清除正在播放信息"""
        if not self.enabled or not self._info_center:
            return
        try:
            self._info_center.setNowPlayingInfo_(None)
        except Exception:
            pass


# ============================================================
# 电台数据（m3u 读写）
# ============================================================

def load_radios(m3u_path):
    """从 m3u 文件加载电台列表，返回 [(名称, URL), ...]

    兼容常见的「脏」M3U 格式：
    - #EXTINF 行中间带 tvg-id / tvg-name / tvg-logo / group-title 等扩展属性
      （频道名在最后一个逗号之后）
    - #EXTGRP / #EXTLOGO / #EXTBYT 等不认识的扩展行直接忽略
    - 空行、注释行、#EXTM3U 头部自动跳过
    - Windows/macOS/Unix 换行都支持
    """
    log.debug("load_radios 开始: %s", m3u_path)
    if not os.path.exists(m3u_path):
        log.warning("load_radios: 文件不存在 %s", m3u_path)
        return []
    radios = []
    try:
        with open(m3u_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        log.exception("load_radios: 读取文件失败 %s", m3u_path)
        return []
    log.debug("load_radios: 读取到 %d 行", len(lines))

    name = None
    for line in lines:
        line = line.strip()
        # 跳过空行和常见头行
        if not line:
            continue
        if line.upper() in ("#EXTM3U",) or line.startswith("#Update:"):
            continue

        if line.startswith("#EXTINF:"):
            # 频道名在最后一个逗号之后（前面可能有 tvg-id / group-title 等扩展属性）
            idx = line.rfind(",")
            if idx >= 0 and idx + 1 < len(line):
                name = line[idx + 1:].strip()
            else:
                name = None
        elif line.startswith("#"):
            # 其他注释/扩展行（#EXTGRP、#EXTLOGO 等）直接忽略
            continue
        else:
            url = line.strip()
            if url:
                if not name:
                    name = os.path.basename(url) or url
                radios.append((name, url))
                name = None
    log.info("load_radios: 从 %s 解析出 %d 个电台", m3u_path, len(radios))
    return radios


def save_radios(m3u_path, radios):
    """将电台列表保存为 m3u 文件"""
    os.makedirs(os.path.dirname(os.path.abspath(m3u_path)), exist_ok=True)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(m3u_path, "w", encoding="utf-8") as f:
        f.write("#EXTM3U\n")
        f.write(f"#Update: {now}\n")
        for name, url in radios:
            f.write(f"#EXTINF:-1,{name}\n")
            f.write(f"{url}\n")


def download_m3u(url, timeout=15):
    """从 URL 下载 m3u 内容并解析，返回 [(名称, URL), ...]
    使用 urllib（最稳定，不会触发 Qt 网络事件循环问题）"""
    import urllib.request
    import tempfile

    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 RadioPlayer/1.0",
        "Accept": "*/*",
    })
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()

    # 尝试检测编码
    text = data.decode("utf-8", errors="replace")

    tmpfd, tmppath = tempfile.mkstemp(suffix=".m3u")
    with os.fdopen(tmpfd, "w", encoding="utf-8") as f:
        f.write(text)
    try:
        result = load_radios(tmppath)
    finally:
        os.unlink(tmppath)
    return result


# ============================================================
# 导入对话框
# ============================================================

class ImportDialog(QDialog):
    """
    导入电台对话框：
    - 本地文件导入
    - 网络链接导入（可设置定时更新）
    - 多选勾选，按 URL 自动去重并标记
    """

    def __init__(self, existing_urls=None, parent=None):
        log.info("ImportDialog.__init__ 开始")
        super().__init__(parent)
        self.setWindowTitle("导入电台")
        self.resize(520, 560)
        self.existing_urls = set(existing_urls or [])
        self.current_radios = []  # [(name, url)]
        self._is_loading = False
        log.info("ImportDialog.__init__: 开始 _build_ui")
        self._build_ui()
        log.info("ImportDialog.__init__: _build_ui 完成")

    def _build_ui(self):
        log.info("ImportDialog._build_ui 开始")
        layout = QVBoxLayout(self)
        layout.setSpacing(10)

        # Tab 切换
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)

        # ---- 本地文件 Tab ----
        local_tab = QWidget()
        local_layout = QVBoxLayout(local_tab)
        local_layout.setSpacing(8)

        file_row = QHBoxLayout()
        log.info("ImportDialog._build_ui: 创建 QLineEdit（本地文件输入框）")
        self.file_edit = QLineEdit()
        self.file_edit.setPlaceholderText("选择或拖入 m3u 文件…")
        file_row.addWidget(self.file_edit, 1)

        browse_btn = QPushButton("浏览…")
        browse_btn.clicked.connect(self._browse_file)
        file_row.addWidget(browse_btn)

        load_file_btn = QPushButton("解析")
        load_file_btn.clicked.connect(self._load_from_file)
        file_row.addWidget(load_file_btn)

        local_layout.addLayout(file_row)

        self.tabs.addTab(local_tab, "本地文件")

        # ---- 网络链接 Tab ----
        net_tab = QWidget()
        net_layout = QVBoxLayout(net_tab)
        net_layout.setSpacing(8)

        url_row = QHBoxLayout()
        log.info("ImportDialog._build_ui: 创建 QLineEdit（网络链接输入框）")
        self.url_edit = QLineEdit()
        self.url_edit.setPlaceholderText("粘贴 m3u 链接，例如 https://example.com/radio.m3u")
        url_row.addWidget(self.url_edit, 1)

        load_url_btn = QPushButton("解析")
        load_url_btn.clicked.connect(self._load_from_url)
        url_row.addWidget(load_url_btn)

        net_layout.addLayout(url_row)

        # 定时更新选项
        self.auto_update_cb = QCheckBox("定时更新此列表（后台自动刷新）")
        self.auto_update_cb.setChecked(False)
        net_layout.addWidget(self.auto_update_cb)

        interval_row = QHBoxLayout()
        interval_row.addWidget(QLabel("更新间隔："))
        self.interval_spin = QSpinBox()
        self.interval_spin.setRange(5, 10080)  # 5 分钟 ~ 7 天
        self.interval_spin.setValue(60)  # 默认 60 分钟
        self.interval_spin.setSuffix(" 分钟")
        self.interval_spin.setEnabled(False)
        interval_row.addWidget(self.interval_spin)
        interval_row.addStretch(1)

        self.auto_update_cb.toggled.connect(self.interval_spin.setEnabled)
        net_layout.addLayout(interval_row)

        net_layout.addStretch(0)
        self.tabs.addTab(net_tab, "网络链接")

        # ---- 候选列表 ----
        list_label = QLabel("选择要导入的电台（按地址去重，重复项已取消勾选）：")
        layout.addWidget(list_label)

        self.list_widget = QListWidget()
        self.list_widget.setStyleSheet("""
            QListWidget { font-size: 13px; }
            QListWidget::item { padding: 4px 6px; }
        """)
        layout.addWidget(self.list_widget, stretch=1)

        # 全选/反选
        sel_row = QHBoxLayout()
        select_all_btn = QPushButton("全选")
        select_all_btn.clicked.connect(self._select_all)
        sel_row.addWidget(select_all_btn)

        deselect_all_btn = QPushButton("全不选")
        deselect_all_btn.clicked.connect(self._deselect_all)
        sel_row.addWidget(deselect_all_btn)

        invert_btn = QPushButton("反选")
        invert_btn.clicked.connect(self._invert_selection)
        sel_row.addWidget(invert_btn)

        sel_row.addStretch(1)
        layout.addLayout(sel_row)

        # 统计
        self.stat_label = QLabel("尚未加载")
        self.stat_label.setStyleSheet("color: #666; font-size: 12px;")
        layout.addWidget(self.stat_label)

        # 按钮
        btn_row = QHBoxLayout()
        btn_row.addStretch(1)

        cancel_btn = QPushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        btn_row.addWidget(cancel_btn)

        self.import_btn = QPushButton("导入")
        self.import_btn.setDefault(True)
        self.import_btn.clicked.connect(self.accept)
        self.import_btn.setEnabled(False)
        btn_row.addWidget(self.import_btn)

        layout.addLayout(btn_row)

    # ---- 操作 ----
    def _browse_file(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "选择 m3u 文件", "",
            "播放列表 (*.m3u *.m3u8);;所有文件 (*.*)"
        )
        if path:
            self.file_edit.setText(path)
            self._load_from_file()

    def _load_from_file(self):
        path = self.file_edit.text().strip()
        if not path or not os.path.exists(path):
            QMessageBox.warning(self, "提示", "请选择有效的 m3u 文件")
            return
        try:
            radios = load_radios(path)
        except Exception as e:
            QMessageBox.critical(self, "错误", f"解析失败：{e}")
            return
        self._populate_list(radios)

    def _load_from_url(self):
        url = self.url_edit.text().strip()
        if not url.startswith(("http://", "https://")):
            QMessageBox.warning(self, "提示", "请输入有效的 http(s) 链接")
            return

        self.import_btn.setEnabled(False)
        self.list_widget.clear()
        self.stat_label.setText("⏳ 正在下载并解析…")
        QApplication.processEvents()

        try:
            radios = download_m3u(url)
        except Exception as e:
            QMessageBox.critical(self, "错误", f"下载失败：{e}")
            self.stat_label.setText("❌ 下载失败")
            return

        self._populate_list(radios)

    def _populate_list(self, radios):
        self.list_widget.clear()
        self.current_radios = radios

        dup_count = 0
        for name, url in radios:
            item = QListWidgetItem(f"{name}")
            item.setToolTip(url)
            is_dup = url in self.existing_urls
            if is_dup:
                dup_count += 1
                item.setCheckState(Qt.CheckState.Unchecked)
                item.setForeground(Qt.GlobalColor.gray)
                item.setText(f"{name}  （已存在，跳过）")
            else:
                item.setCheckState(Qt.CheckState.Checked)

            self.list_widget.addItem(item)

        self.import_btn.setEnabled(len(radios) > 0)
        self.stat_label.setText(
            f"共 {len(radios)} 个电台，"
            f"已选 {self._checked_count()} 个，"
            f"重复 {dup_count} 个（默认跳过）"
        )

    def _checked_count(self):
        count = 0
        for i in range(self.list_widget.count()):
            if self.list_widget.item(i).checkState() == Qt.CheckState.Checked:
                count += 1
        return count

    def _select_all(self):
        for i in range(self.list_widget.count()):
            self.list_widget.item(i).setCheckState(Qt.CheckState.Checked)
        self._update_stat()

    def _deselect_all(self):
        for i in range(self.list_widget.count()):
            self.list_widget.item(i).setCheckState(Qt.CheckState.Unchecked)
        self._update_stat()

    def _invert_selection(self):
        for i in range(self.list_widget.count()):
            item = self.list_widget.item(i)
            if item.checkState() == Qt.CheckState.Checked:
                item.setCheckState(Qt.CheckState.Unchecked)
            else:
                item.setCheckState(Qt.CheckState.Checked)
        self._update_stat()

    def _update_stat(self):
        checked = self._checked_count()
        total = self.list_widget.count()
        self.stat_label.setText(f"共 {total} 个电台，已选 {checked} 个")

    # ---- 结果 ----
    def get_selected_radios(self):
        """返回用户勾选的 [(name, url)]"""
        selected = []
        for i in range(self.list_widget.count()):
            item = self.list_widget.item(i)
            if item.checkState() == Qt.CheckState.Checked:
                selected.append(self.current_radios[i])
        return selected

    def get_subscription_info(self):
        """返回订阅信息（URL 和间隔分钟），如果没开启定时更新返回 None"""
        if self.tabs.currentIndex() != 1:  # 不在网络链接 Tab
            return None
        if not self.auto_update_cb.isChecked():
            return None
        url = self.url_edit.text().strip()
        if not url:
            return None
        return {
            "url": url,
            "interval_minutes": self.interval_spin.value(),
        }


def find_m3u_file():
    """查找 radio.m3u：app 同目录 > 当前目录 > 脚本目录"""
    log.info("find_m3u_file: 开始查找 radio.m3u")
    log.info("    frozen=%s", getattr(sys, "frozen", False))
    log.info("    sys.executable=%s", sys.executable)
    log.info("    os.getcwd()=%s", os.getcwd())
    log.info("    __file__=%s", __file__)
    log.info("    sys._MEIPASS=%s", getattr(sys, "_MEIPASS", None))

    if getattr(sys, "frozen", False):
        app_dir = os.path.dirname(sys.executable)
        app_sibling_dir = os.path.dirname(os.path.dirname(os.path.dirname(app_dir)))
        script_dir = app_sibling_dir
        log.info("    frozen 分支: app_dir=%s, app_sibling_dir=%s", app_dir, app_sibling_dir)
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        app_sibling_dir = script_dir
        log.info("    脚本分支: script_dir=%s", script_dir)

    candidates = [
        os.path.join(app_sibling_dir, "radio.m3u"),
        os.path.join(os.getcwd(), "radio.m3u"),
        os.path.join(script_dir, "radio.m3u"),
    ]
    # 打包后的资源目录（PyInstaller 把 --add-data 的文件放这里）
    if getattr(sys, "_MEIPASS", None):
        candidates.insert(0, os.path.join(sys._MEIPASS, "radio.m3u"))

    log.info("find_m3u_file: 候选路径共 %d 个：", len(candidates))
    for p in candidates:
        log.info("    %s  存在=%s", p, os.path.exists(p))

    for p in candidates:
        if os.path.exists(p):
            log.info("find_m3u_file: 命中 %s", p)
            return p
    log.warning("find_m3u_file: 未找到任何 radio.m3u，返回 None")
    return None


def find_ffmpeg():
    """查找 ffmpeg 可执行文件，返回路径或 None"""
    candidates = ["ffmpeg"]
    if sys.platform == "darwin":
        candidates += ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    for c in candidates:
        try:
            subprocess.run([c, "-version"], capture_output=True,
                           timeout=3, check=False)
            return c
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    return None


# ============================================================
# 主窗口
# ============================================================

class ConnectivityCheckDialog(QDialog):
    """
    连通性检查对话框
    - 批量检查电台 URL 是否可连通
    - 显示状态、耗时、错误信息
    - 支持一键删除失败的电台
    """

    def __init__(self, radios, parent=None):
        super().__init__(parent)
        self.setWindowTitle("连通性检查")
        self.resize(480, 520)
        self.radios = list(radios)
        self.results = []  # [(ok, duration_ms, error_msg)]
        self._is_running = False

        self._build_ui()

    def _build_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(8)

        # 顶部说明
        top_row = QHBoxLayout()
        top_label = QLabel(f"共 {len(self.radios)} 个电台")
        top_row.addWidget(top_label)
        top_row.addStretch(1)

        self.start_btn = QPushButton("▶ 开始检查")
        self.start_btn.clicked.connect(self.start_check)
        top_row.addWidget(self.start_btn)

        layout.addLayout(top_row)

        # 列表
        self.list_widget = QListWidget()
        self.list_widget.itemClicked.connect(self._on_item_clicked)
        layout.addWidget(self.list_widget, stretch=1)

        # 底部按钮
        bottom_row = QHBoxLayout()
        bottom_row.addStretch(1)

        self.del_failed_btn = QPushButton("删除所有失败的")
        self.del_failed_btn.clicked.connect(self._delete_failed)
        self.del_failed_btn.setEnabled(False)
        bottom_row.addWidget(self.del_failed_btn)

        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.accept)
        bottom_row.addWidget(close_btn)

        layout.addLayout(bottom_row)

        # 状态栏
        self.status_label = QLabel("点击「开始检查」以检测电台连通性")
        self.status_label.setStyleSheet("color: #888; font-size: 12px;")
        layout.addWidget(self.status_label)

        # 初始化列表
        for name, url in self.radios:
            item = QListWidgetItem(f"⏳  {name}")
            item.setToolTip(url)
            item.setData(Qt.ItemDataRole.UserRole, url)
            self.list_widget.addItem(item)

        # 检查用的线程（通过 QTimer 串行检查，避免多线程复杂度）
        self._check_index = 0
        self._check_timer = QTimer()
        self._check_timer.timeout.connect(self._check_next)

    def start_check(self):
        """开始检查"""
        if self._is_running:
            return

        self._is_running = True
        self._check_index = 0
        self.results = [None] * len(self.radios)
        self.start_btn.setEnabled(False)
        self.del_failed_btn.setEnabled(False)
        self.status_label.setText("检查中...")

        # 重置所有项
        for i in range(self.list_widget.count()):
            item = self.list_widget.item(i)
            item.setText(f"⏳  {self.radios[i][0]}")
            item.setForeground(Qt.GlobalColor.gray)

        # 每 50ms 检查下一个（串行，避免阻塞 UI 太久）
        self._check_timer.start(10)

    def _check_next(self):
        """检查下一个电台"""
        if self._check_index >= len(self.radios):
            self._check_timer.stop()
            self._is_running = False
            self.start_btn.setEnabled(True)
            self.del_failed_btn.setEnabled(True)
            failed = sum(1 for r in self.results if r and not r[0])
            ok = sum(1 for r in self.results if r and r[0])
            self.status_label.setText(
                f"检查完成：✅ {ok} 个正常，❌ {failed} 个失败"
            )
            return

        idx = self._check_index
        name, url = self.radios[idx]

        # 检查连通性（用 socket 或 urllib 简单探测）
        ok, duration, err = self._check_url(url)
        self.results[idx] = (ok, duration, err)

        item = self.list_widget.item(idx)
        if ok:
            item.setText(f"✅  {name}  ({duration}ms)")
            item.setForeground(QColor("#007AFF") if False else Qt.GlobalColor.darkGreen)
        else:
            item.setText(f"❌  {name}  —  点击查看详情")
            item.setForeground(QColor("#d04545"))

        self._check_index += 1
        self.status_label.setText(f"检查中... {idx + 1}/{len(self.radios)}")

    def _check_url(self, url, timeout=5):
        """检查 URL 是否可连通，返回 (ok, duration_ms, error_msg)"""
        import urllib.request
        import urllib.error
        import ssl
        import time

        # 连通性检查不校验证书（很多电台使用自签名证书）
        ctx = ssl._create_unverified_context()

        start = time.time()
        try:
            req = urllib.request.Request(url, method="HEAD", headers={
                "User-Agent": "Mozilla/5.0 RadioPlayer/1.0",
                "Icy-MetaData": "1",  # 兼容流媒体
            })
            urllib.request.urlopen(req, timeout=timeout, context=ctx)
            duration = int((time.time() - start) * 1000)
            return True, duration, ""
        except urllib.error.HTTPError as e:
            # 403/404 等 HTTP 错误也算连通（服务器有响应）
            duration = int((time.time() - start) * 1000)
            if e.code in (401, 403, 404, 405, 416):
                # 有响应但状态异常，认为连通
                return True, duration, f"HTTP {e.code}: {e.reason}"
            return False, duration, f"HTTP 错误：{e.code} {e.reason}"
        except Exception as e:
            duration = int((time.time() - start) * 1000)
            # 可能 HEAD 不支持，试一下 GET 只读少量数据
            try:
                req = urllib.request.Request(url, headers={
                    "User-Agent": "Mozilla/5.0 RadioPlayer/1.0",
                })
                resp = urllib.request.urlopen(req, timeout=timeout, context=ctx)
                resp.read(1024)  # 只读 1KB
                resp.close()
                duration = int((time.time() - start) * 1000)
                return True, duration, ""
            except Exception as e2:
                return False, duration, str(e2)

    def _on_item_clicked(self, item):
        """点击查看详情"""
        idx = self.list_widget.row(item)
        if not self.results or idx >= len(self.results) or self.results[idx] is None:
            return
        ok, duration, err = self.results[idx]
        name, url = self.radios[idx]

        status = "✅ 连通" if ok else "❌ 失败"
        detail = f"电台：{name}\n地址：{url}\n\n状态：{status}\n耗时：{duration} ms\n"
        if err:
            detail += f"\n错误信息：\n{err}"

        QMessageBox.information(self, "检查详情", detail)

    def _delete_failed(self):
        """删除所有检查失败的电台（返回失败索引列表，由主窗口处理）"""
        failed_indices = [i for i, r in enumerate(self.results)
                          if r and not r[0]]
        if not failed_indices:
            return

        reply = QMessageBox.question(
            self, "确认删除",
            f"确定删除 {len(failed_indices)} 个连通性检查失败的电台吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return

        # 通知主窗口删除（用结果属性）
        self._failed_indices = sorted(failed_indices, reverse=True)
        self.accept()

    def get_failed_indices(self):
        """获取失败的索引（从大到小排好序，方便从后往前删除）"""
        return getattr(self, '_failed_indices', [])


class RadioWindow(QMainWindow):
    def __init__(self, radios, m3u_path):
        super().__init__()
        log.info("RadioWindow.__init__ 开始，电台数量=%d，m3u=%s", len(radios), m3u_path)
        self.radios = list(radios)        # 当前电台列表
        self.m3u_path = m3u_path          # 电台列表文件路径
        self.current_index = -1
        self.current_pool = "all"         # 当前换台范围："all"=全部电台，"starred"=星标台
        self.is_playing = False

        # 录制相关
        self.record_proc = None
        self.record_start_time = None
        self.record_name = None
        self.record_url = None

        # 设置/偏好
        self.settings = QSettings("RadioPlayer", "网络电台")
        # 录制目录无默认值，由用户首次录制（或在录制页手动）选择
        self.record_dir = self.settings.value("record_dir", "")
        self.volume = int(self.settings.value("volume", 80))

        # 星标电台（按 URL 记录，存在 QSettings，不写进 m3u 文件）
        star_val = self.settings.value("starred_urls", [])
        self._starred_urls = set(star_val) if isinstance(star_val, list) else set()
        log.info("RadioWindow.__init__: 设置读取完成，录制目录=%s，音量=%d", self.record_dir, self.volume)

        # 系统媒体集成
        log.info("RadioWindow.__init__: 开始初始化系统媒体集成")
        self.media_int = SystemMediaIntegration(self)
        log.info("RadioWindow.__init__: 系统媒体集成完成，enabled=%s", self.media_int.enabled)

        log.info("RadioWindow.__init__: 开始构建 UI")
        self._build_ui()
        log.info("RadioWindow.__init__: UI 构建完成")
        self._build_menu()
        self._init_player()
        self._start_clock()
        self._refresh_list()
        log.info("RadioWindow.__init__: 列表刷新完成，当前 %d 个电台", len(self.radios))

        # 恢复音量
        self.vol_slider.setValue(self.volume)

        # 启动订阅定时器
        self._sub_last_update = {}
        self._setup_subscription_timer()

        # 托盘图标
        self.tray_icon = None
        log.info("RadioWindow.__init__: 开始设置托盘图标")
        self._setup_tray()
        log.info("RadioWindow.__init__: 托盘图标设置完成，tray_icon=%s", self.tray_icon)

        # 标记：是否真正退出（防止 closeEvent 重复触发）
        self._really_quit = False
        log.info("RadioWindow.__init__ 完成")

    # ---- UI ----
    def _build_ui(self):
        self.setWindowTitle("📻 网络电台")
        self.resize(480, 850)
        # 最小尺寸：保证设置页所有卡片完整显示，不允许缩到文字不全
        self.setMinimumSize(478, 827)

        # 应用主题（优先用户设置，否则跟随系统）
        self._apply_theme_forced()

        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(18, 16, 18, 16)
        layout.setSpacing(12)

        # 时钟 + 标题（顶部）
        header = QHBoxLayout()
        header.setSpacing(8)

        self.clock_label = QLabel()
        self.clock_label.setTextFormat(Qt.TextFormat.RichText)
        self.clock_label.setText(
            '<span style="font-size:22px; font-family:Menlo; font-weight:bold;">--:--</span>'
            '<span style="font-size:13px; color:#888; font-family:Menlo;">:--.-</span>'
        )
        header.addWidget(self.clock_label)
        header.addStretch(1)

        title = QLabel("📻 网络电台")
        f = title.font()
        f.setPointSize(13)
        f.setBold(True)
        title.setFont(f)
        title.setStyleSheet("color: #007AFF;")
        header.addWidget(title)

        layout.addLayout(header)

        # 正在播放
        now_layout = self._make_card("正在播放", layout)
        now_layout.setSpacing(2)
        self.now_label = QLabel("未播放")
        self.now_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.now_label.setStyleSheet("color: #007AFF; font-size: 14px; font-weight: 600;")
        now_layout.addWidget(self.now_label)

        self.now_program_label = QLabel("")
        self.now_program_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.now_program_label.setWordWrap(True)
        self.now_program_label.setStyleSheet("font-size: 12px; opacity: 0.7;")
        self.now_program_label.setObjectName("cardTitle")
        self.now_program_label.setMinimumHeight(16)
        now_layout.addWidget(self.now_program_label)

        # Tab 分页（电台 / 录制 / 设置）
        self.tabs = QTabWidget()
        self.tabs.setDocumentMode(True)

        # ---- Tab 1：电台 ----
        radio_tab = QWidget()
        radio_layout = QVBoxLayout(radio_tab)
        radio_layout.setContentsMargins(6, 8, 6, 6)
        radio_layout.setSpacing(8)

        # 内层分页：全部电台 / 星标台（决定换台范围）
        self.inner_tabs = QTabWidget()
        self.inner_tabs.setDocumentMode(True)
        self.inner_tabs.setStyleSheet("QTabWidget::pane { border: none; }")

        # —— 全部电台 ——
        all_page = QWidget()
        all_layout = QVBoxLayout(all_page)
        all_layout.setContentsMargins(0, 4, 0, 0)
        all_layout.setSpacing(6)
        self.list_widget = QListWidget()
        self.list_widget.setStyleSheet("QListWidget { font-size: 13px; }")
        self.list_widget.itemDoubleClicked.connect(lambda _: self.play_selected())
        self.list_widget.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.list_widget.customContextMenuRequested.connect(self._show_list_menu)
        all_layout.addWidget(self.list_widget)
        self.inner_tabs.addTab(all_page, "全部")

        # —— 星标台 ——
        star_page = QWidget()
        star_layout = QVBoxLayout(star_page)
        star_layout.setContentsMargins(0, 4, 0, 0)
        star_layout.setSpacing(6)
        self.star_list_widget = QListWidget()
        self.star_list_widget.setStyleSheet("QListWidget { font-size: 13px; }")
        self.star_list_widget.itemDoubleClicked.connect(lambda _: self.play_selected())
        self.star_list_widget.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.star_list_widget.customContextMenuRequested.connect(self._show_list_menu)
        star_layout.addWidget(self.star_list_widget)
        self.inner_tabs.addTab(star_page, "⭐ 星标台")

        radio_layout.addWidget(self.inner_tabs, stretch=1)

        # 电台管理按钮
        # 注意：clicked 信号会带一个 checked 布尔参数，必须用 lambda 吞掉，
        # 否则会误传给有默认参数的方法（如 move_up(row=None) → row=False 导致失灵）。
        btn_row1 = QHBoxLayout()
        btn_row1.setSpacing(8)
        for text, slot in [("＋ 添加", self.add_station),
                           ("📥 导入", self.import_stations),
                           ("🔔 订阅", self.manage_subscriptions)]:
            btn = QPushButton(text)
            btn.clicked.connect(lambda _checked=False, s=slot: s())
            btn_row1.addWidget(btn)
        radio_layout.addLayout(btn_row1)

        btn_row2 = QHBoxLayout()
        btn_row2.setSpacing(8)
        for text, slot in [("－ 删除", self.remove_station),
                           ("★ 标星", self.toggle_star),
                           ("↑ 上移", self.move_up),
                           ("↓ 下移", self.move_down)]:
            btn = QPushButton(text)
            btn.clicked.connect(lambda _checked=False, s=slot: s())
            btn_row2.addWidget(btn)
        radio_layout.addLayout(btn_row2)

        self.tabs.addTab(radio_tab, "📻 电台")

        # ---- Tab 2：录制 ----
        rec_tab = QWidget()
        rec_layout = QVBoxLayout(rec_tab)
        rec_layout.setContentsMargins(6, 8, 6, 6)
        rec_layout.setSpacing(12)

        # 录制控制
        rec_ctrl_row = QHBoxLayout()
        self.rec_btn = QPushButton("● 开始录制")
        self.rec_btn.setStyleSheet("QPushButton { color: #d04545; font-weight: bold; }")
        self.rec_btn.clicked.connect(self._toggle_record)
        rec_ctrl_row.addWidget(self.rec_btn, 1)
        rec_layout.addLayout(rec_ctrl_row)

        # 录制计时器
        self.rec_timer_label = QLabel("未录制")
        self.rec_timer_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.rec_timer_label.setStyleSheet("color: #888; font-size: 14px;")
        rec_layout.addWidget(self.rec_timer_label)

        # 保存目录
        dir_layout = self._make_card("保存设置", rec_layout)

        dir_btn_row = QHBoxLayout()
        dir_label = QLabel("保存目录：")
        dir_btn_row.addWidget(dir_label)
        dir_btn_row.addStretch(1)
        rec_dir_btn = QPushButton("更改…")
        rec_dir_btn.clicked.connect(self.choose_record_dir)
        dir_btn_row.addWidget(rec_dir_btn)
        dir_layout.addLayout(dir_btn_row)

        self.rec_dir_label = QLabel()
        self.rec_dir_label.setStyleSheet("font-size: 12px;")
        self.rec_dir_label.setObjectName("cardTitle")
        self.rec_dir_label.setWordWrap(True)
        self._update_rec_dir_label()
        dir_layout.addWidget(self.rec_dir_label)

        reveal_btn = QPushButton("在访达中显示")
        reveal_btn.clicked.connect(self.reveal_record_dir)
        dir_layout.addWidget(reveal_btn)

        rec_layout.addStretch(1)

        self.tabs.addTab(rec_tab, "● 录制")

        # ---- Tab 3：设置 ----
        set_tab = QWidget()
        set_layout = QVBoxLayout(set_tab)
        set_layout.setContentsMargins(6, 8, 6, 6)
        set_layout.setSpacing(12)

        # 音量（卡片标题已说明，无需重复标签）
        vol_layout = self._make_card("音量", set_layout)
        self.vol_slider = QSlider(Qt.Orientation.Horizontal)
        self.vol_slider.setRange(0, 100)
        self.vol_slider.setValue(80)
        self.vol_slider.valueChanged.connect(self._on_volume)
        vol_layout.addWidget(self.vol_slider)

        # 音频输出设备（解决“首次无声/外接音响不响”问题）
        dev_layout = self._make_card("音频输出设备", set_layout)
        self.device_combo = QComboBox()
        self.device_combo.setToolTip("选择声音从哪个设备输出；「跟随系统默认」会随系统自动切换")
        self.device_combo.currentIndexChanged.connect(self._on_device_changed)
        dev_layout.addWidget(self.device_combo)

        # 外观
        appear_layout = self._make_card("外观", set_layout)

        theme_row = QHBoxLayout()
        theme_row.setSpacing(8)
        theme_row.addWidget(QLabel("主题"))
        theme_row.addStretch(1)
        _mode = self.settings.value("theme_mode", "auto")
        _mode_text = {"auto": "跟随系统", "light": "浅色模式", "dark": "深色模式"}.get(_mode, "跟随系统")
        self.theme_btn = QPushButton(_mode_text)
        self.theme_btn.setMinimumWidth(96)
        self.theme_btn.clicked.connect(self._toggle_theme_force)
        theme_row.addWidget(self.theme_btn)
        appear_layout.addLayout(theme_row)

        tray_row = QHBoxLayout()
        tray_row.setSpacing(8)
        tray_row.addWidget(QLabel("托盘图标"))
        tray_row.addStretch(1)
        self.tray_cb = QCheckBox()
        self.tray_cb.setChecked(True)
        self.tray_cb.toggled.connect(self.toggle_tray)
        tray_row.addWidget(self.tray_cb)
        appear_layout.addLayout(tray_row)

        # 关闭行为
        close_layout = self._make_card("关闭窗口", set_layout)
        close_btn = QPushButton("修改关闭行为…")
        close_btn.clicked.connect(self.change_close_behavior)
        close_layout.addWidget(close_btn)

        # 电台维护（连通性检查入口）
        maint_layout = self._make_card("电台维护", set_layout)
        check_btn = QPushButton("检查连通性…")
        check_btn.clicked.connect(self.check_connectivity)
        maint_layout.addWidget(check_btn)

        set_layout.addStretch(1)
        self.tabs.addTab(set_tab, "⚙️ 设置")

        # ---- Tab 4：关于 ----
        about_tab = QWidget()
        about_layout = QVBoxLayout(about_tab)
        about_layout.setContentsMargins(20, 24, 20, 20)
        about_layout.setSpacing(8)

        about_title = QLabel("📻 网络电台")
        about_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        about_title.setStyleSheet("font-size: 22px; font-weight: 600;")
        about_layout.addWidget(about_title)

        about_sub = QLabel("一款极简网络电台播放器")
        about_sub.setAlignment(Qt.AlignmentFlag.AlignCenter)
        about_sub.setStyleSheet("font-size: 13px;")
        about_layout.addWidget(about_sub)

        about_layout.addSpacing(12)

        about_desc = QLabel(
            "电台内容、音质和连通性由电台来源决定，播放效果与网络环境有关。\n"
            "录制所得内容请遵守相关版权要求，仅供个人学习使用。"
        )
        about_desc.setWordWrap(True)
        about_desc.setStyleSheet("font-size: 12px;")
        about_layout.addWidget(about_desc)

        about_layout.addSpacing(12)

        about_info = QLabel("开发者：GZYZhy\n开源协议：MIT License")
        about_info.setStyleSheet("font-size: 12px;")
        about_layout.addWidget(about_info)

        about_link = QLabel(
            "<a href='https://github.com/GZYZhy/stream-radio' "
            "style='color:#007AFF;'>github.com/GZYZhy/stream-radio</a>"
        )
        about_link.setOpenExternalLinks(True)
        about_layout.addWidget(about_link)

        about_layout.addStretch(1)

        about_base = QLabel("基于 PyQt6")
        about_base.setAlignment(Qt.AlignmentFlag.AlignRight)
        about_layout.addWidget(about_base)

        self.about_tab = about_tab
        self.tabs.addTab(about_tab, "关于")

        layout.addWidget(self.tabs, stretch=1)

        # 底部：迷你播放控制（始终可见）
        mini_ctrl = QHBoxLayout()
        mini_ctrl.setSpacing(8)
        mini_prev = QPushButton("⏮")
        mini_prev.setFixedSize(42, 34)
        mini_prev.clicked.connect(self.prev)
        mini_ctrl.addWidget(mini_prev)

        self.mini_play_btn = QPushButton("▶")
        self.mini_play_btn.setObjectName("miniPlayBtn")  # 实心主按钮样式
        self.mini_play_btn.setFixedSize(58, 34)
        self.mini_play_btn.clicked.connect(self._toggle_play)
        mini_ctrl.addWidget(self.mini_play_btn)

        mini_next = QPushButton("⏭")
        mini_next.setFixedSize(42, 34)
        mini_next.clicked.connect(self.next)
        mini_ctrl.addWidget(mini_next)

        mini_ctrl.addStretch(1)

        mini_vol_label = QLabel("🔊")
        mini_ctrl.addWidget(mini_vol_label)

        self.mini_vol = QSlider(Qt.Orientation.Horizontal)
        self.mini_vol.setRange(0, 100)
        self.mini_vol.setValue(80)
        self.mini_vol.setFixedWidth(110)
        self.mini_vol.valueChanged.connect(self._on_volume)
        mini_ctrl.addWidget(self.mini_vol)

        layout.addLayout(mini_ctrl)

        # 同步音量滑块
        self.vol_slider.valueChanged.connect(self.mini_vol.setValue)
        self.mini_vol.valueChanged.connect(self.vol_slider.setValue)

        # 快捷键
        self._install_shortcuts()

        # 监听系统主题变化
        self._theme_timer = QTimer(self)
        self._theme_timer.timeout.connect(self._check_theme_change)
        self._theme_timer.start(2000)  # 每 2 秒检查一次
        self._last_is_dark = self._is_dark_mode()

    def _make_card(self, title, parent_layout):
        """创建一个带标题的卡片（QFrame），返回卡片的内容布局（QVBoxLayout）。

        标题显示在卡片上方（小字、淡色），卡片是圆角矩形内容区。
        注意：不要用 QGroupBox 做卡片——Qt 样式表给 QGroupBox 设 padding
        在 macOS 上会算错内容区高度，导致子控件被压扁。
        """
        wrap = QVBoxLayout()
        wrap.setSpacing(4)  # 标题与卡片之间紧凑一些
        cap = QLabel(title)
        cap.setObjectName("cardTitle")
        wrap.addWidget(cap)

        card = QFrame()
        card.setObjectName("card")
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(12, 10, 12, 12)
        card_layout.setSpacing(8)
        wrap.addWidget(card)

        parent_layout.addLayout(wrap)
        return card_layout

    def _update_rec_dir_label(self):
        if not self.record_dir:
            self.rec_dir_label.setText("未设置（首次录制时会要求选择）")
            self.rec_dir_label.setToolTip("")
            return
        # 缩短路径显示
        path = self.record_dir
        if len(path) > 40:
            path = "…" + path[-38:]
        self.rec_dir_label.setText(path)
        self.rec_dir_label.setToolTip(self.record_dir)

    # ---- 主题（跟随系统深色/浅色） ----
    def _is_dark_mode(self):
        """检测系统是否为深色模式"""
        if sys.platform == "darwin":
            try:
                result = subprocess.run(
                    ["defaults", "read", "-g", "AppleInterfaceStyle"],
                    capture_output=True, text=True, timeout=1
                )
                return "Dark" in result.stdout
            except Exception:
                return False
        else:
            # Windows/Linux 用 Qt 的 palette 判断
            from PyQt6.QtGui import QGuiApplication
            palette = QGuiApplication.palette()
            window = palette.color(palette.ColorGroup.Active, palette.ColorRole.Window)
            return window.lightness() < 128

    def _apply_theme(self):
        """应用主题（卡片化设计 + 蓝色主色 + 深色/浅色模式）"""
        is_dark = self._is_dark_mode()

        if is_dark:
            bg = "#17181c"        # 窗口底色（最深）
            card = "#232529"      # 卡片底色
            bg_alt = "#2e3036"    # 按钮/输入框底色
            hover = "#363840"     # 悬停底色
            text = "#e8e8ea"
            text_mute = "#8e8e93"
            border = "#3a3c42"
        else:
            bg = "#f3f4f6"        # 窗口底色（微灰，衬出白色卡片）
            card = "#ffffff"
            bg_alt = "#eceef1"
            hover = "#e2e5e9"
            text = "#1d1d1f"
            text_mute = "#86868b"
            border = "#dfe2e6"

        accent = "#007AFF"  # macOS 系统蓝

        app = QApplication.instance()
        app.setStyleSheet(f"""
            QMainWindow, QWidget {{
                background-color: {bg};
                color: {text};
            }}
            QFrame#card {{
                background-color: {card};
                border: 1px solid {border};
                border-radius: 10px;
            }}
            QLabel#cardTitle {{
                color: {text_mute};
                font-size: 12px;
                padding-left: 4px;
            }}
            QPushButton {{
                background-color: {bg_alt};
                color: {text};
                border: none;
                border-radius: 8px;
                padding: 7px 14px;
                font-size: 13px;
            }}
            QPushButton:hover {{
                background-color: {hover};
            }}
            QPushButton:pressed {{
                background-color: {accent};
                color: white;
            }}
            QPushButton:disabled {{
                color: {text_mute};
                background-color: {bg_alt};
            }}
            QPushButton#miniPlayBtn {{
                background-color: {accent};
                color: white;
                border-radius: 9px;
                font-size: 15px;
                font-weight: 600;
            }}
            QPushButton#miniPlayBtn:hover {{
                background-color: #0a84ff;
            }}
            QPushButton#miniPlayBtn:pressed {{
                background-color: #0066d6;
            }}
            QListWidget {{
                background-color: {card};
                color: {text};
                border: 1px solid {border};
                border-radius: 10px;
                padding: 4px;
                outline: none;
            }}
            QListWidget::item {{
                padding: 7px 10px;
                border-radius: 6px;
            }}
            QListWidget::item:selected {{
                background: {accent};
                color: white;
            }}
            QListWidget::item:hover:!selected {{
                background-color: {hover};
            }}
            QTabWidget::pane {{
                background-color: transparent;
                border: none;
            }}
            QTabBar::tab {{
                background-color: transparent;
                color: {text_mute};
                padding: 6px 18px;
                margin: 2px 3px;
                font-size: 13px;
                border: none;
                border-radius: 8px;
            }}
            QTabBar::tab:selected {{
                background-color: {card};
                color: {text};
                font-weight: 600;
            }}
            QTabBar::tab:hover:!selected {{
                color: {text};
                background-color: {hover};
            }}
            QLabel {{
                color: {text};
                background-color: transparent;
            }}
            QLineEdit, QSpinBox {{
                background-color: {bg_alt};
                color: {text};
                border: 1px solid transparent;
                border-radius: 8px;
                padding: 6px 10px;
                selection-background-color: {accent};
            }}
            QLineEdit:focus, QSpinBox:focus {{
                border-color: {accent};
            }}
            QComboBox {{
                background-color: {bg_alt};
                color: {text};
                border: none;
                border-radius: 8px;
                padding: 6px 10px;
            }}
            QComboBox:hover {{
                background-color: {hover};
            }}
            QComboBox::drop-down {{
                border: none;
                width: 26px;
            }}
            QComboBox QAbstractItemView {{
                background-color: {card};
                border: 1px solid {border};
                border-radius: 8px;
                padding: 4px;
                selection-background-color: {accent};
                selection-color: white;
                outline: none;
            }}
            QCheckBox {{
                spacing: 6px;
                background-color: transparent;
            }}
            QCheckBox::indicator {{
                width: 17px;
                height: 17px;
                border-radius: 5px;
                border: 1px solid {border};
                background-color: {bg_alt};
            }}
            QCheckBox::indicator:checked {{
                background-color: {accent};
                border-color: {accent};
            }}
            QSlider::groove:horizontal {{
                height: 5px;
                background: {border};
                border-radius: 3px;
            }}
            QSlider::handle:horizontal {{
                width: 16px;
                height: 16px;
                margin: -6px 0;
                background: {accent};
                border-radius: 8px;
            }}
            QSlider::handle:horizontal:hover {{
                background: #0a84ff;
            }}
            QSlider::sub-page:horizontal {{
                background: {accent}60;
                border-radius: 3px;
            }}
            QScrollBar:vertical {{
                background: transparent;
                width: 10px;
                margin: 3px 2px 3px 2px;
            }}
            QScrollBar::handle:vertical {{
                background: {border};
                border-radius: 5px;
                min-height: 32px;
            }}
            QScrollBar::handle:vertical:hover {{
                background: {text_mute};
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
                height: 0;
            }}
            QScrollBar:horizontal {{
                background: transparent;
                height: 10px;
                margin: 2px 3px 2px 3px;
            }}
            QScrollBar::handle:horizontal {{
                background: {border};
                border-radius: 5px;
                min-width: 32px;
            }}
            QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
                width: 0;
            }}
            QMenu {{
                background-color: {card};
                color: {text};
                border: 1px solid {border};
                border-radius: 9px;
                padding: 5px;
            }}
            QMenu::item {{
                padding: 6px 28px 6px 14px;
                border-radius: 6px;
            }}
            QMenu::item:selected {{
                background-color: {accent};
                color: white;
            }}
            QMenu::separator {{
                height: 1px;
                background: {border};
                margin: 5px 10px;
            }}
            QToolTip {{
                background-color: {card};
                color: {text};
                border: 1px solid {border};
                border-radius: 6px;
                padding: 5px 8px;
            }}
            QProgressBar {{
                background-color: {bg_alt};
                border: none;
                border-radius: 5px;
                text-align: center;
                color: {text_mute};
                font-size: 11px;
            }}
            QProgressBar::chunk {{
                background-color: {accent};
                border-radius: 5px;
            }}
        """)

    def _check_theme_change(self):
        """定时检查系统主题是否变化"""
        # 用户手动强制深浅色时，不跟随系统
        if self.settings.value("theme_mode", "auto") != "auto":
            return
        is_dark = self._is_dark_mode()
        if hasattr(self, '_last_is_dark') and is_dark != self._last_is_dark:
            self._last_is_dark = is_dark
            self._apply_theme()
            # 重新应用特殊颜色
            self.now_label.setStyleSheet(f"color: #007AFF; font-size: 14px; font-weight: 500;")

    def _toggle_theme_force(self):
        """切换主题按钮（跟随系统 / 强制浅色 / 强制深色）"""
        from PyQt6.QtWidgets import QMessageBox

        current = self.settings.value("theme_mode", "auto")

        dlg = QMessageBox(self)
        dlg.setWindowTitle("主题")
        dlg.setText("选择主题模式：")

        btn_auto = dlg.addButton("跟随系统", QMessageBox.ButtonRole.ActionRole)
        btn_light = dlg.addButton("浅色模式", QMessageBox.ButtonRole.ActionRole)
        btn_dark = dlg.addButton("深色模式", QMessageBox.ButtonRole.ActionRole)
        dlg.addButton("取消", QMessageBox.ButtonRole.RejectRole)

        dlg.exec()
        clicked = dlg.clickedButton()

        if clicked == btn_auto:
            self.settings.setValue("theme_mode", "auto")
            self.theme_btn.setText("跟随系统")
        elif clicked == btn_light:
            self.settings.setValue("theme_mode", "light")
            self.theme_btn.setText("浅色模式")
        elif clicked == btn_dark:
            self.settings.setValue("theme_mode", "dark")
            self.theme_btn.setText("深色模式")
        else:
            return

        # 立即刷新显示
        self._apply_theme_forced()

    def _apply_theme_forced(self):
        """根据用户设置应用主题（覆盖系统设置）"""
        mode = self.settings.value("theme_mode", "auto")
        if mode == "auto":
            self._apply_theme()
            self._last_is_dark = self._is_dark_mode()
            return

        is_dark = mode == "dark"

        # 临时覆盖检测结果
        # 这里简化处理：直接修改系统检测方法的返回
        original = self._is_dark_mode
        self._is_dark_mode = lambda: is_dark
        self._apply_theme()
        self._is_dark_mode = original
        self._last_is_dark = is_dark

    def _install_shortcuts(self):
        """键盘快捷键"""
        QShortcut(QKeySequence(Qt.Key.Key_Up), self, activated=self.prev)
        QShortcut(QKeySequence(Qt.Key.Key_Down), self, activated=self.next)
        QShortcut(QKeySequence(Qt.Key.Key_Space), self, activated=self._toggle_play)
        QShortcut(QKeySequence(Qt.Key.Key_Return), self, activated=self.play_selected)
        QShortcut(QKeySequence(Qt.Key.Key_Enter), self, activated=self.play_selected)
        QShortcut(QKeySequence("Ctrl+R"), self, activated=self._toggle_record)
        QShortcut(QKeySequence("Ctrl+N"), self, activated=self.add_station)
        QShortcut(QKeySequence("Ctrl+O"), self, activated=self.import_stations)
        QShortcut(QKeySequence("Delete"), self, activated=self.remove_station)

    # ---- 托盘图标 ----
    def _setup_tray(self):
        """设置状态栏托盘图标（macOS 菜单栏右上角）"""
        log.info("_setup_tray 开始")
        from PyQt6.QtGui import QIcon, QAction, QPixmap, QPainter, QColor, QFont
        from PyQt6.QtWidgets import QSystemTrayIcon, QMenu, QApplication

        available = QSystemTrayIcon.isSystemTrayAvailable()
        log.info("_setup_tray: 系统托盘可用=%s", available)
        if not available:
            log.warning("_setup_tray: 系统托盘不可用，跳过托盘图标")
            self.tray_icon = None
            return

        # 绘制一个简单的托盘图标（收音机图案用 emoji 文字代替）
        log.info("_setup_tray: 开始绘制托盘图标")
        icon = self._create_tray_icon()
        log.info("_setup_tray: 托盘图标绘制完成，isNull=%s", icon.isNull())

        self.tray_icon = QSystemTrayIcon(icon, self)
        self.tray_icon.setToolTip("📻 网络电台")
        log.info("_setup_tray: QSystemTrayIcon 创建成功")

        # 注意：macOS 上不要调用 setContextMenu()。新版系统状态栏（macOS 15+）
        # 会因此走 NSStatusItem popUpStatusItemMenu 路径，触发
        # NSInternalInconsistencyException 崩溃（Qt 官方 Won't Do）。
        # 改为把菜单挂在 self 上，在 activated 信号里手动弹出。
        self.tray_menu = self._build_tray_menu()
        log.info("_setup_tray: 托盘菜单构建完成")

        self.tray_icon.activated.connect(self._on_tray_activated)
        log.info("_setup_tray: 信号绑定完成")

        self.tray_icon.show()
        log.info("_setup_tray: show() 已调用，完成")

    def _build_tray_menu(self):
        """构建托盘菜单（返回 QMenu，由 self.tray_menu 持有引用）"""
        from PyQt6.QtGui import QAction
        from PyQt6.QtWidgets import QMenu

        menu = QMenu()

        show_act = QAction("显示主窗口", self)
        show_act.triggered.connect(self._show_window)
        menu.addAction(show_act)

        menu.addSeparator()

        play_act = QAction("▶/⏸ 播放/暂停", self)
        play_act.triggered.connect(self._toggle_play)
        menu.addAction(play_act)

        prev_act = QAction("↑ 上一台", self)
        prev_act.triggered.connect(self.prev)
        menu.addAction(prev_act)

        next_act = QAction("↓ 下一台", self)
        next_act.triggered.connect(self.next)
        menu.addAction(next_act)

        menu.addSeparator()

        rec_act = QAction("● 开始/停止录制", self)
        rec_act.triggered.connect(self._toggle_record)
        menu.addAction(rec_act)

        menu.addSeparator()

        quit_act = QAction("退出", self)
        quit_act.triggered.connect(self._quit_app)
        menu.addAction(quit_act)

        return menu

    def _show_tray_menu(self):
        """在鼠标当前位置弹出托盘菜单（延迟到事件循环，避开状态栏事件）"""
        from PyQt6.QtGui import QCursor

        def _popup():
            try:
                self.tray_menu.popup(QCursor.pos())
            except Exception:
                log.exception("托盘菜单弹出失败")

        # 延迟一帧执行，避免在状态栏事件回调里同步弹菜单导致原生崩溃
        QTimer.singleShot(0, _popup)

    def _create_tray_icon(self):
        """生成托盘图标（简单的绿色圆形 + 白色音符）"""
        log.info("_create_tray_icon 开始")
        try:
            from PyQt6.QtGui import QIcon, QPixmap, QPainter, QColor, QFont, QBrush, QPen
            from PyQt6.QtCore import Qt, QRectF

            pix = QPixmap(32, 32)
            pix.fill(Qt.GlobalColor.transparent)

            p = QPainter(pix)
            p.setRenderHint(QPainter.RenderHint.Antialiasing)

            # 绿色圆形背景
            p.setBrush(QColor("#007AFF"))
            p.setPen(Qt.PenStyle.NoPen)
            p.drawEllipse(1, 1, 30, 30)

            # 白色天线/音符（简化的收音机符号：两道弧）
            p.setPen(QPen(QColor("white"), 2.5, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
            p.drawArc(6, 10, 20, 16, 45 * 16, 90 * 16)
            p.drawArc(10, 14, 12, 8, 45 * 16, 90 * 16)

            # 底部小圆（电台）
            p.setBrush(QColor("white"))
            p.drawEllipse(14, 21, 4, 4)

            p.end()
            log.info("_create_tray_icon 完成，图标正常")
            return QIcon(pix)
        except Exception:
            log.exception("_create_tray_icon 绘制失败，使用纯色占位图标")
            from PyQt6.QtGui import QIcon, QPixmap, QColor
            pix = QPixmap(32, 32)
            pix.fill(QColor("#007AFF"))
            return QIcon(pix)

    def _on_tray_activated(self, reason):
        """点击托盘图标"""
        log.info("_on_tray_activated: 托盘被点击，reason=%s", _enum_info(reason))
        from PyQt6.QtWidgets import QSystemTrayIcon
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            log.info("_on_tray_activated: 左键单击，当前可见=%s", self.isVisible())
            # 左键单击：切换显示/隐藏
            if self.isVisible():
                self.hide()
            else:
                self._show_window()
        elif reason == QSystemTrayIcon.ActivationReason.Context:
            # 右键：手动弹出菜单（macOS 下不用 setContextMenu，避免崩溃）
            log.info("_on_tray_activated: 右键单击，弹出菜单")
            self._show_tray_menu()

    def _show_window(self):
        """显示窗口并前置"""
        self.show()
        self.raise_()
        self.activateWindow()

    def _quit_app(self):
        """完全退出程序"""
        from PyQt6.QtWidgets import QApplication
        if self.record_proc:
            self._stop_record()
        self.player.stop()
        self.media_int.clear()
        if hasattr(self, 'tray_icon') and self.tray_icon:
            self.tray_icon.hide()
        QApplication.quit()

    # ---- 菜单栏 ----
    def _build_menu(self):
        menubar = self.menuBar()

        # 文件菜单
        file_menu = menubar.addMenu("文件")

        add_act = QAction("添加电台…", self)
        add_act.setShortcut(QKeySequence("Cmd+N"))
        add_act.triggered.connect(self.add_station)
        file_menu.addAction(add_act)

        import_act = QAction("导入电台…", self)
        import_act.setShortcut(QKeySequence("Cmd+O"))
        import_act.triggered.connect(self.import_stations)
        file_menu.addAction(import_act)

        file_menu.addSeparator()

        # 订阅子菜单
        self.sub_menu = file_menu.addMenu("订阅管理")
        self.sub_list_act = QAction("管理订阅…", self)
        self.sub_list_act.triggered.connect(self.manage_subscriptions)
        self.sub_menu.addAction(self.sub_list_act)
        self.sub_refresh_act = QAction("立即刷新所有订阅", self)
        self.sub_refresh_act.triggered.connect(self.refresh_all_subscriptions)
        self.sub_menu.addAction(self.sub_refresh_act)

        file_menu.addSeparator()

        del_act = QAction("删除当前电台", self)
        del_act.setShortcut(QKeySequence("Delete"))
        del_act.triggered.connect(self.remove_station)
        file_menu.addAction(del_act)

        file_menu.addSeparator()

        save_act = QAction("保存列表", self)
        save_act.setShortcut(QKeySequence("Cmd+S"))
        save_act.triggered.connect(self.save_list)
        file_menu.addAction(save_act)

        open_dir_act = QAction("在访达中显示 radio.m3u", self)
        open_dir_act.triggered.connect(self.reveal_m3u)
        file_menu.addAction(open_dir_act)

        file_menu.addSeparator()

        quit_act = QAction("退出", self)
        quit_act.setShortcut(QKeySequence("Cmd+Q"))
        quit_act.triggered.connect(self.close)
        file_menu.addAction(quit_act)

        # 编辑菜单
        edit_menu = menubar.addMenu("编辑")

        up_act = QAction("上移电台", self)
        up_act.setShortcut(QKeySequence("Cmd+Up"))
        up_act.triggered.connect(self.move_up)
        edit_menu.addAction(up_act)

        down_act = QAction("下移电台", self)
        down_act.setShortcut(QKeySequence("Cmd+Down"))
        down_act.triggered.connect(self.move_down)
        edit_menu.addAction(down_act)

        edit_menu.addSeparator()

        rename_act = QAction("重命名电台…", self)
        rename_act.triggered.connect(self.rename_station)
        edit_menu.addAction(rename_act)

        edit_url_act = QAction("修改电台地址…", self)
        edit_url_act.triggered.connect(self.edit_station_url)
        edit_menu.addAction(edit_url_act)

        edit_menu.addSeparator()

        check_act = QAction("检查连通性…", self)
        check_act.setShortcut(QKeySequence("Ctrl+Shift+C"))
        check_act.triggered.connect(self.check_connectivity)
        edit_menu.addAction(check_act)

        # 播放菜单
        play_menu = menubar.addMenu("播放")

        play_toggle_act = QAction("播放/暂停", self)
        play_toggle_act.setShortcut(QKeySequence(" "))
        play_toggle_act.triggered.connect(self._toggle_play)
        play_menu.addAction(play_toggle_act)

        stop_act = QAction("停止", self)
        stop_act.setShortcut(QKeySequence("."))
        stop_act.triggered.connect(self.stop)
        play_menu.addAction(stop_act)

        play_menu.addSeparator()

        prev_act = QAction("上一台", self)
        prev_act.setShortcut(QKeySequence("↑"))
        prev_act.triggered.connect(self.prev)
        play_menu.addAction(prev_act)

        next_act = QAction("下一台", self)
        next_act.setShortcut(QKeySequence("↓"))
        next_act.triggered.connect(self.next)
        play_menu.addAction(next_act)

        play_menu.addSeparator()

        rec_act = QAction("开始/停止录制", self)
        rec_act.setShortcut(QKeySequence("Cmd+R"))
        rec_act.triggered.connect(self._toggle_record)
        play_menu.addAction(rec_act)

        play_menu.addSeparator()

        vol_up_act = QAction("音量增大", self)
        vol_up_act.setShortcut(QKeySequence("Cmd+="))
        vol_up_act.triggered.connect(lambda: self.vol_slider.setValue(self.vol_slider.value() + 5))
        play_menu.addAction(vol_up_act)

        vol_down_act = QAction("音量减小", self)
        vol_down_act.setShortcut(QKeySequence("Cmd+-"))
        vol_down_act.triggered.connect(lambda: self.vol_slider.setValue(self.vol_slider.value() - 5))
        play_menu.addAction(vol_down_act)

        # 设置菜单
        settings_menu = menubar.addMenu("设置")

        rec_dir_act = QAction("录制保存目录…", self)
        rec_dir_act.triggered.connect(self.choose_record_dir)
        settings_menu.addAction(rec_dir_act)

        reveal_rec_act = QAction("在访达中显示录制目录", self)
        reveal_rec_act.triggered.connect(self.reveal_record_dir)
        settings_menu.addAction(reveal_rec_act)

        settings_menu.addSeparator()

        close_behavior_act = QAction("关闭窗口行为…", self)
        close_behavior_act.triggered.connect(self.change_close_behavior)
        settings_menu.addAction(close_behavior_act)

        tray_toggle_act = QAction("显示托盘图标", self)
        tray_toggle_act.setCheckable(True)
        tray_toggle_act.setChecked(True)
        tray_toggle_act.triggered.connect(self.toggle_tray)
        settings_menu.addAction(tray_toggle_act)
        self.tray_toggle_act = tray_toggle_act

        # 帮助菜单
        help_menu = menubar.addMenu("帮助")

        about_act = QAction("关于 网络电台", self)
        about_act.triggered.connect(self.show_about)
        help_menu.addAction(about_act)

    # ---- 播放器 ----
    def _init_player(self):
        log.info("_init_player: 创建 QMediaPlayer / QAudioOutput")
        self.player = QMediaPlayer()
        self.audio_output = QAudioOutput()
        self.player.setAudioOutput(self.audio_output)
        self.audio_output.setVolume(self.vol_slider.value() / 100.0)
        log.info("_init_player: 音量设为 %.2f", self.vol_slider.value() / 100.0)

        # 订阅“系统音频设备列表变化”，并在外接音响接入/断开时自动刷新
        try:
            from PyQt6.QtMultimedia import QMediaDevices
            QMediaDevices.audioOutputsChanged.connect(self._on_audio_devices_changed)
        except Exception as e:
            log.warning("_init_player: 无法订阅音频设备变化: %s", e)

        # 填充设备下拉框，并应用保存（或默认）的输出设备
        self._populate_devices()
        self._apply_audio_device()

        self.player.errorOccurred.connect(self._on_error)
        self.player.mediaStatusChanged.connect(self._on_media_status)
        self.player.metaDataChanged.connect(self._on_meta_data_changed)
        log.info("_init_player 完成")

    def _populate_devices(self):
        """刷新音频输出设备下拉框，选中上次保存（或系统默认）的设备（不切换设备）"""
        from PyQt6.QtMultimedia import QMediaDevices

        devices = QMediaDevices.audioOutputs()
        log.info("_populate_devices: 共 %d 个音频输出设备", len(devices))
        for d in devices:
            log.info("    输出设备: %s", d.description())

        self.device_combo.blockSignals(True)
        self.device_combo.clear()
        self.device_combo.addItem("跟随系统默认", "")  # data 为空字符串表示跟随系统
        for d in devices:
            self.device_combo.addItem(d.description(), d.description())

        saved = self.settings.value("audio_device", "") or ""
        idx = self.device_combo.findData(saved)
        if idx < 0:
            idx = 0  # 找不到则回退「跟随系统默认」
        self.device_combo.setCurrentIndex(idx)
        self.device_combo.blockSignals(False)

    def _apply_audio_device(self):
        """把下拉框当前选中的设备应用到 QAudioOutput，并重设音量"""
        from PyQt6.QtMultimedia import QMediaDevices

        data = self.device_combo.currentData()
        target = None
        if data:
            for d in QMediaDevices.audioOutputs():
                if d.description() == data:
                    target = d
                    break
            if target is None:
                log.warning("_apply_audio_device: 找不到设备「%s」，回退系统默认", data)

        if target is None:
            target = QMediaDevices.defaultAudioOutput()

        if target is not None:
            self.audio_output.setDevice(target)
            log.info("_apply_audio_device: 已应用设备「%s」", target.description())
        else:
            log.warning("_apply_audio_device: 没有可用输出设备")

        # 切换设备后音量可能被重置，重新应用
        self.audio_output.setVolume(self.vol_slider.value() / 100.0)

    def _on_device_changed(self, _index):
        """用户手动选择音频输出设备"""
        data = self.device_combo.currentData() or ""
        self.settings.setValue("audio_device", data)
        log.info("_on_device_changed: 用户选择「%s」", data or "跟随系统默认")
        self._apply_audio_device()

    def _on_audio_devices_changed(self):
        """系统音频设备列表变化（如耳机插拔）时，仅刷新下拉框、不切换设备。
        避免 setDevice 打断 macOS 摘下耳机时的自动暂停。"""
        log.info("_on_audio_devices_changed: 系统音频设备列表变化，仅刷新下拉框")
        self._populate_devices()

    # ---- 时钟 ----
    def _start_clock(self):
        self._update_clock()
        self.clock_timer = QTimer(self)
        self.clock_timer.timeout.connect(self._update_clock)
        self.clock_timer.start(100)

    def _update_clock(self):
        now = datetime.now()
        hhmm = now.strftime("%H:%M")
        sec = now.strftime(":%S")
        tenth = now.microsecond // 100000

        # 农历 + 日期 + BJT 标志（每秒更新一次即可，不用每 100ms）
        if not hasattr(self, '_last_date_str') or now.second == 0:
            lunar = self._lunar_date(now.year, now.month, now.day)
            weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            date_str = now.strftime("%m月%d日 ") + weekdays[now.weekday()]
            self._date_str = (
                f'<div style="font-size:11px; color:#888; font-family:Menlo;">'
                f'{date_str} · {lunar}'
                f' &nbsp; BJT (UTC+8)'
                f'</div>'
            )

        self.clock_label.setText(
            self._date_str +
            f'<div style="font-size:22px; font-family:Menlo; font-weight:bold; margin-top:2px;">{hhmm}'
            f'<span style="font-size:14px; color:#888; font-family:Menlo; font-weight:normal;">{sec}.{tenth}</span>'
            f'</div>'
        )

    @staticmethod
    def _lunar_date(year, month, day):
        """
        公历转农历（1900-2100 年有效）
        返回形如 "丙午年七月初八" 的字符串

        数据格式：lunar_info 每项 20 bit：
          bit 0-3   闰月月份（0 表示无闰月）
          bit 4-15  第 1-12 月大小（1=大月30天，0=小月29天）
          bit 16    闰月大小（1=大月30天，0=小月29天，无闰月时忽略）
          bit 17-19 保留（该年总天数的高位，未使用）
        """
        # 1900-2100 年农历数据
        lunar_info = [
            0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
            0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
            0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
            0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
            0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
            0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
            0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
            0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
            0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
            0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
            0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
            0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
            0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
            0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
            0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
            0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
            0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
            0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
            0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
            0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04af8, 0x049d0, 0x0db00, 0x1ebd6, 0x0d520,
            0x0daa0,
        ]

        if year < 1900 or year > 2100:
            return ""

        def _year_days(info):
            """返回该农历年的总天数"""
            days = 348  # 12 × 29
            for i in range(4, 16):
                if info & (1 << i):
                    days += 1
            # 加上闰月
            leap = info & 0xf
            if leap:
                days += 30 if (info & 0x10000) else 29
            return days

        def _month_days(info, month, is_leap=False):
            """返回指定月份的天数（month 1-12，is_leap 表示是否闰月）"""
            if is_leap:
                return 30 if (info & 0x10000) else 29
            return 30 if (info & (1 << (month + 3))) else 29

        # 1900 年正月初一 = 1900-01-31
        base = datetime(1900, 1, 31)
        target = datetime(year, month, day)
        offset = (target - base).days

        if offset < 0:
            return ""

        # 1. 定位农历年
        lunar_year = 1900
        idx = 0
        for i, info in enumerate(lunar_info):
            yd = _year_days(info)
            if offset < yd:
                lunar_year = 1900 + i
                idx = i
                break
            offset -= yd
        else:
            return ""

        info = lunar_info[idx]
        leap = info & 0xf  # 闰月月份，0 表示无闰月

        # 2. 定位农历月、日（注意闰月插在对应月份之后）
        is_leap = False
        lunar_month = 0
        for m in range(1, 13):
            # 正常月
            md = _month_days(info, m)
            if offset < md:
                lunar_month = m
                break
            offset -= md
            # 如果该月之后有闰月
            if leap and m == leap:
                md_leap = _month_days(info, m, is_leap=True)
                if offset < md_leap:
                    lunar_month = m
                    is_leap = True
                    break
                offset -= md_leap
        else:
            return ""

        lunar_day = offset + 1

        # 3. 天干地支年
        tian_gan = "甲乙丙丁戊己庚辛壬癸"
        di_zhi = "子丑寅卯辰巳午未申酉戌亥"
        gan_idx = (lunar_year - 4) % 10
        zhi_idx = (lunar_year - 4) % 12
        year_name = tian_gan[gan_idx] + di_zhi[zhi_idx] + "年"

        # 4. 月份中文名
        month_names = ["正月", "二月", "三月", "四月", "五月", "六月",
                       "七月", "八月", "九月", "十月", "冬月", "腊月"]
        month_str = month_names[lunar_month - 1]
        if is_leap:
            month_str = "闰" + month_str

        # 5. 日中文名
        day_tens = ["初", "十", "廿", "三"]
        day_ones = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if lunar_day == 10:
            day_str = "初十"
        elif lunar_day == 20:
            day_str = "二十"
        elif lunar_day == 30:
            day_str = "三十"
        else:
            day_str = day_tens[(lunar_day - 1) // 10] + day_ones[(lunar_day - 1) % 10]

        return f"{year_name}{month_str}{day_str}"

    # ---- 列表管理 ----
    def _refresh_list(self):
        """刷新列表显示（全部 + 星标台）：带序号，星标的电台带 ★ 前缀"""
        current = self.current_index
        self.list_widget.clear()
        self.star_list_widget.clear()
        for i, (name, url) in enumerate(self.radios):
            starred = url in self._starred_urls
            item = QListWidgetItem(f"{i + 1}. " + ("★ " if starred else "") + name)
            item.setToolTip(url)
            self.list_widget.addItem(item)
            if starred:
                # 星标台内按自身顺序标号
                star_no = self.star_list_widget.count() + 1
                self.star_list_widget.addItem(QListWidgetItem(f"{star_no}. ★ " + name))
        log.info("_refresh_list: 已刷新，全部 %d 个，星标 %d 个",
                 self.list_widget.count(), self.star_list_widget.count())
        if 0 <= current < len(self.radios):
            self.list_widget.setCurrentRow(current)
            si = self._starred_indices()
            if current in si:
                self.star_list_widget.setCurrentRow(si.index(current))

    # ---- 星标功能 ----
    def _starred_indices(self):
        """返回星标电台在 self.radios 中的索引列表（保持原顺序）"""
        return [i for i, (_, url) in enumerate(self.radios) if url in self._starred_urls]

    def _save_stars(self):
        """保存星标列表到 QSettings"""
        self.settings.setValue("starred_urls", sorted(self._starred_urls))

    def _active_list_widget(self):
        """当前内层子列表控件（全部 或 星标台）"""
        return self.star_list_widget if self.inner_tabs.currentIndex() == 1 else self.list_widget

    def _current_active_index(self):
        """当前激活列表选中项对应的 radios 索引；无选中返回 -1"""
        lw = self._active_list_widget()
        row = lw.currentRow()
        if row < 0:
            return -1
        if self.inner_tabs.currentIndex() == 1:
            si = self._starred_indices()
            return si[row] if row < len(si) else -1
        return row

    def _focus_active_row(self, radios_index):
        """让当前激活列表高亮 radios_index 对应的行"""
        if self.inner_tabs.currentIndex() == 1:
            si = self._starred_indices()
            if radios_index in si:
                self.star_list_widget.setCurrentRow(si.index(radios_index))
        else:
            self.list_widget.setCurrentRow(radios_index)

    def toggle_star(self):
        """标星/取消标星当前选中项"""
        lw = self._active_list_widget()
        if self.inner_tabs.currentIndex() == 1:
            si = self._starred_indices()
            row = lw.currentRow()
            if 0 <= row < len(si):
                index = si[row]
            else:
                return
        else:
            index = lw.currentRow()
            if index < 0:
                return
        _, url = self.radios[index]
        if url in self._starred_urls:
            self._starred_urls.discard(url)
        else:
            self._starred_urls.add(url)
        self._save_stars()
        self._refresh_list()
        # 恢复选中
        if self.inner_tabs.currentIndex() == 1:
            if url in self._starred_urls:
                self.star_list_widget.setCurrentRow(self._starred_indices().index(index))
        else:
            self.list_widget.setCurrentRow(index)

    def _show_list_menu(self, pos):
        """列表右键菜单：播放 / 标星 / 编辑 / 上移 / 下移 / 删除"""
        lw = self._active_list_widget()
        item = lw.itemAt(pos)
        if item is None:
            return
        lw.setCurrentItem(item)  # 右键位置即目标项
        index = self._current_active_index()
        if index < 0:
            return
        _, url = self.radios[index]
        starred = url in self._starred_urls
        in_star = self.inner_tabs.currentIndex() == 1

        menu = QMenu(self)
        play_act = menu.addAction("▶ 播放")
        star_act = menu.addAction("★ 取消标星" if starred else "☆ 标星")
        menu.addSeparator()
        edit_act = menu.addAction("✏️ 编辑…")
        up_act = menu.addAction("↑ 上移")
        down_act = menu.addAction("↓ 下移")
        menu.addSeparator()
        del_act = menu.addAction("🗑 删除")

        chosen = menu.exec(lw.mapToGlobal(pos))
        if chosen is None:
            return
        if chosen is play_act:
            # 播放来源决定换台范围
            self.current_pool = "starred" if in_star else "all"
            self.play(index)
        elif chosen is star_act:
            self.toggle_star()
        elif chosen is edit_act:
            self.edit_station_at(index)
        elif chosen is up_act:
            self.move_up(index)
        elif chosen is down_act:
            self.move_down(index)
        elif chosen is del_act:
            self.remove_station(index)

    def add_station(self):
        """添加新电台"""
        name, ok = QInputDialog.getText(self, "添加电台", "电台名称：")
        if not ok or not name.strip():
            return
        name = name.strip()

        url, ok = QInputDialog.getText(self, "添加电台", "电台地址 (URL)：")
        if not ok or not url.strip():
            return
        url = url.strip()

        self.radios.append((name, url))
        self._refresh_list()
        self.list_widget.setCurrentRow(len(self.radios) - 1)
        self.save_list()

    def remove_station(self, row=None):
        """删除电台；row 省略时删除当前激活列表选中的电台"""
        if row is None:
            row = self._current_active_index()
        if row < 0:
            return

        name, url = self.radios[row]
        reply = QMessageBox.question(
            self, "确认删除",
            f"确定要删除电台「{name}」吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return

        # 如果正在播放被删的电台，先停止
        if row == self.current_index:
            self.stop()
            self.current_index = -1
            self.now_label.setText("未播放")
        elif row < self.current_index:
            self.current_index -= 1

        del self.radios[row]
        # 若被删电台是星标，同步清理星标记录
        if url in self._starred_urls:
            self._starred_urls.discard(url)
            self._save_stars()
        self._refresh_list()
        self.save_list()

    def _swap_radios(self, a, b):
        """交换 radios 中两个电台的位置，并同步当前播放索引"""
        self.radios[a], self.radios[b] = self.radios[b], self.radios[a]
        if self.current_index == a:
            self.current_index = b
        elif self.current_index == b:
            self.current_index = a

    def move_up(self, row=None):
        """电台上移；row 省略时操作当前激活列表选中项。
        星标台视图下在星标台内部上移（与上一个星标电台交换），
        全部视图下与相邻电台交换。"""
        if row is None:
            row = self._current_active_index()
        if row < 0:
            return
        if self.inner_tabs.currentIndex() == 1:
            # 星标台内部上移
            si = self._starred_indices()
            if row not in si:
                return
            pos = si.index(row)
            if pos <= 0:
                return
            self._swap_radios(si[pos - 1], row)
            self._refresh_list()
            self._focus_active_row(si[pos - 1])  # 被移动的电台现在在这
            self.save_list()
            return
        if row <= 0:
            return
        self._swap_radios(row - 1, row)
        self._refresh_list()
        self._focus_active_row(row - 1)
        self.save_list()

    def move_down(self, row=None):
        """电台下移；row 省略时操作当前激活列表选中项。
        星标台视图下在星标台内部下移（与下一个星标电台交换），
        全部视图下与相邻电台交换。"""
        if row is None:
            row = self._current_active_index()
        if row < 0:
            return
        if self.inner_tabs.currentIndex() == 1:
            # 星标台内部下移
            si = self._starred_indices()
            if row not in si:
                return
            pos = si.index(row)
            if pos >= len(si) - 1:
                return
            self._swap_radios(row, si[pos + 1])
            self._refresh_list()
            self._focus_active_row(si[pos + 1])  # 被移动的电台现在在这
            self.save_list()
            return
        if row >= len(self.radios) - 1:
            return
        self._swap_radios(row, row + 1)
        self._refresh_list()
        self._focus_active_row(row + 1)
        self.save_list()

    def rename_station(self):
        """重命名电台（当前激活列表选中项）"""
        row = self._current_active_index()
        if row < 0:
            return
        old_name, url = self.radios[row]
        new_name, ok = QInputDialog.getText(self, "重命名电台", "新名称：", text=old_name)
        if ok and new_name.strip() and new_name.strip() != old_name:
            self.radios[row] = (new_name.strip(), url)
            self._refresh_list()
            self._focus_active_row(row)
            self.save_list()
            # 如果正在播放，更新显示
            if row == self.current_index and self.is_playing:
                self.now_label.setText(f"🔊 {new_name.strip()}")
                self._update_system_media()

    def edit_station_url(self):
        """修改电台地址（当前激活列表选中项）"""
        row = self._current_active_index()
        if row < 0:
            return
        name, old_url = self.radios[row]
        new_url, ok = QInputDialog.getText(self, "修改电台地址", "新地址 (URL)：", text=old_url)
        if ok and new_url.strip() and new_url.strip() != old_url:
            self.radios[row] = (name, new_url.strip())
            self._refresh_list()
            self._focus_active_row(row)
            self.save_list()

    def edit_station_at(self, index):
        """编辑电台（一个对话框同时改名称和地址）"""
        if index < 0 or index >= len(self.radios):
            return
        name, url = self.radios[index]
        dlg = QDialog(self)
        dlg.setWindowTitle("编辑电台")
        form = QFormLayout(dlg)
        form.setContentsMargins(20, 20, 20, 20)
        form.setSpacing(10)
        name_edit = QLineEdit(name)
        url_edit = QLineEdit(url)
        form.addRow("名称：", name_edit)
        form.addRow("地址 (URL)：", url_edit)
        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(dlg.accept)
        btns.rejected.connect(dlg.reject)
        form.addRow(btns)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return
        new_name = name_edit.text().strip()
        new_url = url_edit.text().strip()
        if not new_name or not new_url:
            return
        if (new_name, new_url) == (name, url):
            return
        self.radios[index] = (new_name, new_url)
        self._refresh_list()
        self._focus_active_row(index)
        self.save_list()
        # 如果正在播放，更新显示
        if index == self.current_index and self.is_playing:
            self.now_label.setText(f"🔊 {new_name}")
            self._update_system_media()

    def save_list(self):
        """保存电台列表到 m3u"""
        try:
            save_radios(self.m3u_path, self.radios)
        except Exception as e:
            QMessageBox.warning(self, "保存失败", f"无法保存 radio.m3u：\n{e}")

    def reveal_m3u(self):
        """在访达中显示 radio.m3u"""
        if sys.platform == "darwin":
            subprocess.run(["open", "-R", self.m3u_path])
        elif sys.platform == "win32":
            subprocess.run(["explorer", "/select,", self.m3u_path])

    # ---- 导入电台 ----
    def import_stations(self):
        """打开导入对话框"""
        log.info("import_stations: 点击「导入电台」，当前已有电台 %d 个", len(self.radios))
        existing_urls = {url for _, url in self.radios}
        log.debug("import_stations: 现有 URL %d 个", len(existing_urls))
        log.info("import_stations: 开始创建 ImportDialog")
        dlg = ImportDialog(existing_urls=existing_urls, parent=self)
        log.info("import_stations: ImportDialog 创建成功，开始 exec")
        result = dlg.exec()
        log.info("import_stations: 对话框结果=%s（Accepted=%s）", result, QDialog.DialogCode.Accepted)
        if result != QDialog.DialogCode.Accepted:
            return

        selected = dlg.get_selected_radios()
        log.info("import_stations: 用户勾选 %d 个电台", len(selected))
        if not selected:
            return

        # 去重（再保险一次）
        new_count = 0
        for name, url in selected:
            if url not in {u for _, u in self.radios}:
                self.radios.append((name, url))
                new_count += 1
        log.info("import_stations: 去重后新增 %d 个电台", new_count)

        if new_count == 0:
            QMessageBox.information(self, "导入", "没有新的电台被导入（全部已存在）")
            return

        self._refresh_list()
        self.save_list()

        # 处理订阅
        sub_info = dlg.get_subscription_info()
        if sub_info:
            self._add_subscription(sub_info["url"], sub_info["interval_minutes"])
            sub_count = len(self._get_subscriptions())
            QMessageBox.information(
                self, "导入完成",
                f"成功导入 {new_count} 个电台\n"
                f"已添加定时更新订阅（每 {sub_info['interval_minutes']} 分钟自动刷新）"
            )
        else:
            QMessageBox.information(self, "导入完成", f"成功导入 {new_count} 个电台")

    # ---- 订阅管理 ----
    def _get_subscriptions(self):
        """从设置中读取订阅列表，返回 [{'url':..., 'interval':..., 'name':...}]"""
        raw = self.settings.value("subscriptions", "[]")
        try:
            return json.loads(raw) if isinstance(raw, str) else list(raw)
        except Exception:
            return []

    def _save_subscriptions(self, subs):
        self.settings.setValue("subscriptions", json.dumps(subs, ensure_ascii=False))

    def _add_subscription(self, url, interval_minutes, name=None):
        subs = self._get_subscriptions()
        # 同一个 URL 只保留一个
        for s in subs:
            if s.get("url") == url:
                s["interval"] = interval_minutes
                if name:
                    s["name"] = name
                self._save_subscriptions(subs)
                self._setup_subscription_timer()
                return
        subs.append({
            "url": url,
            "interval": interval_minutes,
            "name": name or url[:50],
        })
        self._save_subscriptions(subs)
        self._setup_subscription_timer()

    def _setup_subscription_timer(self):
        """设置订阅更新定时器（每 5 分钟检查一次是否到了更新时间）"""
        if not hasattr(self, '_sub_timer'):
            self._sub_timer = QTimer(self)
            self._sub_timer.timeout.connect(self._check_subscriptions)
            self._sub_timer.start(60 * 1000)  # 每分钟检查一次

        subs = self._get_subscriptions()
        if not subs:
            self._sub_timer.stop()
            return
        self._sub_timer.start(60 * 1000)

        # 初始化上次更新时间
        if not hasattr(self, '_sub_last_update'):
            self._sub_last_update = {}

    def _check_subscriptions(self):
        """检查每个订阅是否到了更新时间"""
        subs = self._get_subscriptions()
        now = time.time()

        for sub in subs:
            url = sub.get("url")
            interval = sub.get("interval", 60) * 60  # 转秒
            last = self._sub_last_update.get(url, 0)

            if now - last >= interval:
                self._sub_last_update[url] = now
                # 后台更新，不阻塞 UI
                self._refresh_subscription(url)

    def _refresh_subscription(self, url):
        """刷新一个订阅，把新电台去重加入"""
        try:
            radios = download_m3u(url)
        except Exception as e:
            print(f"[订阅更新] 失败 {url}: {e}", file=sys.stderr)
            return

        existing_urls = {u for _, u in self.radios}
        added = 0
        for name, rurl in radios:
            if rurl not in existing_urls:
                self.radios.append((name, rurl))
                existing_urls.add(rurl)
                added += 1

        if added > 0:
            self._refresh_list()
            self.save_list()
            print(f"[订阅更新] 新增 {added} 个电台: {url}", file=sys.stderr)

    def refresh_all_subscriptions(self):
        """手动立即刷新所有订阅"""
        subs = self._get_subscriptions()
        if not subs:
            QMessageBox.information(self, "订阅", "当前没有订阅")
            return

        count = len(subs)
        added_total = 0
        for sub in subs:
            before = len(self.radios)
            self._refresh_subscription(sub.get("url"))
            added_total += len(self.radios) - before
            # 记录这次更新时间
            self._sub_last_update[sub.get("url")] = time.time()

        QMessageBox.information(
            self, "刷新完成",
            f"已刷新 {count} 个订阅，新增 {added_total} 个电台"
        )

    def check_connectivity(self):
        """打开连通性检查对话框"""
        dlg = ConnectivityCheckDialog(self.radios, self)
        if dlg.exec() != QDialog.DialogCode.Accepted:
            return

        failed = dlg.get_failed_indices()
        if not failed:
            return

        # 从后往前删除（避免索引错乱）
        for idx in failed:
            if idx == self.current_index:
                self.stop()
                self.current_index = -1
                self.now_label.setText("未播放")
            elif idx < self.current_index:
                self.current_index -= 1
            del self.radios[idx]

        self._refresh_list()
        self.save_list()
        QMessageBox.information(self, "已删除", f"已删除 {len(failed)} 个无法连通的电台")

    def manage_subscriptions(self):
        """管理订阅对话框（简单版：列表 + 删除 + 修改间隔）"""
        subs = self._get_subscriptions()
        if not subs:
            QMessageBox.information(self, "订阅管理", "当前没有订阅\n\n导入网络 m3u 时勾选「定时更新」即可添加订阅")
            return

        # 用简单的输入对话框管理：列出订阅，可选择删除
        from PyQt6.QtWidgets import QInputDialog
        items = [f"{s.get('name', s['url'][:40])}  (每 {s.get('interval', 60)} 分钟)"
                 for s in subs]
        items.append("---")
        items.append("+ 添加订阅…")

        choice, ok = QInputDialog.getItem(
            self, "订阅管理",
            f"共 {len(subs)} 个订阅\n选择一个删除，或选择「添加订阅」：",
            items, 0, False
        )
        if not ok:
            return

        if choice.startswith("+ 添加"):
            url, ok2 = QInputDialog.getText(self, "添加订阅", "m3u 链接：")
            if not ok2 or not url.strip():
                return
            url = url.strip()
            interval, ok3 = QInputDialog.getInt(
                self, "添加订阅", "更新间隔（分钟）：", 60, 5, 10080
            )
            if not ok3:
                return
            self._add_subscription(url, interval)
            QMessageBox.information(self, "订阅管理", "订阅已添加")
            return

        # 删除选中的订阅
        idx = items.index(choice)
        if idx < len(subs):
            reply = QMessageBox.question(
                self, "删除订阅",
                f"确定删除订阅「{subs[idx].get('name', subs[idx]['url'][:40])}」吗？\n"
                f"（已导入的电台不会被删除）",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if reply == QMessageBox.StandardButton.Yes:
                del subs[idx]
                self._save_subscriptions(subs)
                self._setup_subscription_timer()
                QMessageBox.information(self, "订阅管理", "已删除")

    # ---- 录制目录设置 ----
    def choose_record_dir(self):
        """让用户选择录制保存目录，返回是否已设置"""
        new_dir = QFileDialog.getExistingDirectory(
            self, "选择录制保存目录", self.record_dir or ""
        )
        if new_dir:
            self.record_dir = new_dir
            self.settings.setValue("record_dir", new_dir)
            self._update_rec_dir_label()
        return bool(self.record_dir)

    def reveal_record_dir(self):
        """在访达中显示录制目录"""
        if not self.record_dir:
            QMessageBox.information(self, "提示", "尚未设置录制目录，请先点击「更改…」选择")
            return
        os.makedirs(self.record_dir, exist_ok=True)
        if sys.platform == "darwin":
            subprocess.run(["open", self.record_dir])
        elif sys.platform == "win32":
            subprocess.run(["explorer", self.record_dir])

    def change_close_behavior(self):
        """修改关闭窗口行为设置"""
        from PyQt6.QtWidgets import QMessageBox

        current = self.settings.value("close_behavior", "ask")

        dlg = QMessageBox(self)
        dlg.setWindowTitle("关闭窗口行为")
        dlg.setText("点击窗口关闭按钮时：")
        dlg.setInformativeText(
            "• 每次询问\n"
            "• 最小化到托盘（继续后台播放）\n"
            "• 完全退出程序"
        )

        btn_ask = dlg.addButton("每次询问", QMessageBox.ButtonRole.ActionRole)
        btn_min = dlg.addButton("最小化到托盘", QMessageBox.ButtonRole.ActionRole)
        btn_quit = dlg.addButton("完全退出", QMessageBox.ButtonRole.ActionRole)
        dlg.addButton("取消", QMessageBox.ButtonRole.RejectRole)

        dlg.exec()
        clicked = dlg.clickedButton()

        if clicked == btn_ask:
            self.settings.remove("close_behavior")
        elif clicked == btn_min:
            self.settings.setValue("close_behavior", "minimize")
        elif clicked == btn_quit:
            self.settings.setValue("close_behavior", "quit")

    def toggle_tray(self, checked):
        """切换托盘图标显示"""
        from PyQt6.QtWidgets import QSystemTrayIcon

        if checked:
            self._setup_tray()
        else:
            if self.tray_icon:
                self.tray_icon.hide()
                self.tray_icon = None

    # ---- 关于 ----
    def show_about(self):
        """切换到「关于」标签页"""
        self.tabs.setCurrentWidget(self.about_tab)

    # ---- 播放控制 ----
    def play_selected(self):
        """播放当前列表选中项；播放来源决定之后的换台范围"""
        if self.inner_tabs.currentIndex() == 1:
            # 从星标台开播：换台只在星标台之间
            self.current_pool = "starred"
            si = self._starred_indices()
            row = self.star_list_widget.currentRow()
            if 0 <= row < len(si):
                self.play(si[row])
        else:
            # 从全部列表开播：正常换台
            self.current_pool = "all"
            row = self.list_widget.currentRow()
            if row >= 0:
                self.play(row)

    def play(self, index):
        log.info("play 调用: index=%d", index)
        if index < 0 or index >= len(self.radios):
            log.warning("play: 非法索引 %d（电台数量 %d）", index, len(self.radios))
            return

        name, url = self.radios[index]
        self.current_index = index
        log.info("play: 播放电台 [%d] 「%s」 URL=%s", index, name, url)

        self.list_widget.setCurrentRow(index)
        # 星标列表同步高亮（若该电台是星标）
        si = self._starred_indices()
        if index in si:
            self.star_list_widget.setCurrentRow(si.index(index))

        # 如果正在录制，先停止
        if self.record_proc:
            log.info("play: 正在录制，先停止录制")
            self._stop_record()
            self.rec_timer_label.setText(self.rec_timer_label.text() + "\n（换台已停止录制）")

        self.player.stop()
        self.player.setSource(QUrl(url))
        self.player.play()
        log.info("play: 已调用 setSource + play，当前 playbackState=%s", self.player.playbackState())

        self.is_playing = True
        self.now_label.setText(f"🔊 {name}")
        self.mini_play_btn.setText("⏸")

        self._update_system_media()

        # 换台推送系统通知（类似 Apple Music）
        # 有节目信息：标题=节目，副标题=电台；没有节目信息：标题=电台，副标题=正在播放
        from PyQt6.QtMultimedia import QMediaMetaData
        md = self.player.metaData()
        t = md.stringValue(QMediaMetaData.Key.Title)
        a = md.stringValue(QMediaMetaData.Key.ContributingArtist)
        if t or a:
            notif_title = t or a
            if t and a and t != a:
                notif_title = f"{a} — {t}"
            self.media_int.notify(name, f"在播：{notif_title}")
        else:
            self.media_int.notify(name, "正在播放")

        # 延迟 1.5 秒后复查播放状态（排查“首次无声”）
        QTimer.singleShot(1500, lambda: self._log_playback_health(url))

    def _log_playback_health(self, url):
        """播放 1.5 秒后复查媒体/播放状态，用于排查无声问题"""
        try:
            log.info("播放状态复查: URL=%s", url)
            log.info("    playbackState=%s", _enum_info(self.player.playbackState()))
            log.info("    mediaStatus=%s", _enum_info(self.player.mediaStatus()))
            log.info("    error=%s", _enum_info(self.player.error()))
            log.info("    errorString=%s", self.player.errorString())
            log.info("    hasAudio=%s", self.player.hasAudio())
            log.info("    audioOutput volume=%.2f，muted=%s", self.audio_output.volume(), self.audio_output.isMuted())
        except Exception:
            log.exception("播放状态复查失败")

    def stop(self):
        self.player.stop()
        self.is_playing = False
        self.now_label.setText("已停止")
        self.now_program_label.setText("")
        self.now_program_label.setToolTip("")
        self.mini_play_btn.setText("▶")

        if self.record_proc:
            self._stop_record()
            self.rec_timer_label.setText(self.rec_timer_label.text() + "\n（停止播放已结束录制）")

        self.media_int.clear()

    def _pool_indices(self):
        """当前换台范围内的索引列表（全部电台 或 星标台）"""
        if self.current_pool == "starred":
            return self._starred_indices()
        return list(range(len(self.radios)))

    def prev(self):
        """上一台：在「当前播放来源」的范围内循环换台"""
        pool = self._pool_indices()
        if not pool:
            return
        try:
            pos = pool.index(self.current_index)
        except ValueError:
            pos = -1  # 当前电台不在池内，从最后一个开始
        self.play(pool[pos - 1])

    def next(self):
        """下一台：在「当前播放来源」的范围内循环换台"""
        pool = self._pool_indices()
        if not pool:
            return
        try:
            pos = pool.index(self.current_index)
        except ValueError:
            pos = -1  # 当前电台不在池内，从第一个开始
        idx = pool[pos + 1] if pos < len(pool) - 1 else pool[0]
        self.play(idx)

    def _toggle_play(self):
        log.info("_toggle_play 调用，当前 is_playing=%s，current_index=%d", self.is_playing, self.current_index)
        if self.is_playing:
            self.player.pause()
            self.is_playing = False
            self.mini_play_btn.setText("▶")
            self.now_label.setText("已暂停")
            # 暂停时保留节目信息，用户想看到刚才在播什么
            if self.record_proc:
                self._was_recording = True
                self._stop_record()
                self.rec_timer_label.setText(self.rec_timer_label.text() + "\n（播放暂停，录制已暂停）")
            else:
                self._was_recording = False
            self._update_system_media()
        else:
            if self.current_index < 0:
                log.info("_toggle_play: 尚未选择电台，调用 play_selected")
                self.play_selected()
            else:
                self.player.play()
                self.is_playing = True
                self.mini_play_btn.setText("⏸")
                name = self.radios[self.current_index][0]
                self.now_label.setText(f"🔊 {name}")
                if getattr(self, '_was_recording', False):
                    self._start_record()
                    self._was_recording = False
                self._update_system_media()

    def _update_system_media(self):
        """更新系统媒体中心 + 现在播放行。
        - 有节目信息时：title=节目，artist=电台名
        - 没有节目信息时：title=电台名，artist=「网络电台」（维持原状）
        """
        if not self.media_int.enabled or self.current_index < 0:
            return
        name, url = self.radios[self.current_index]

        # 从元数据里取当前节目
        from PyQt6.QtMultimedia import QMediaMetaData
        md = self.player.metaData()
        title = md.stringValue(QMediaMetaData.Key.Title)
        artist = md.stringValue(QMediaMetaData.Key.ContributingArtist)

        if title or artist:
            # 有节目信息：标题 = 歌手 - 曲目（或单个），艺人 = 电台名
            parts = []
            if artist:
                parts.append(artist)
            if title and title != artist:
                parts.append(title)
            display_title = " — ".join(parts) if parts else (title or artist)
            display_artist = name
        else:
            # 没有节目信息：维持原状，电台名作为标题
            display_title = name
            display_artist = "网络电台"

        self.media_int.update_now_playing(
            title=display_title,
            artist=display_artist,
            duration=None,
            is_playing=self.is_playing,
            position=0,
        )

    def _on_volume(self, val):
        log.debug("音量调整: %d", val)
        self.audio_output.setVolume(val / 100.0)
        self.settings.setValue("volume", val)

    def _on_error(self, error, error_string):
        log.error("播放出错: error=%s，errorString=%s", _enum_info(error), error_string)
        self.now_label.setText("⚠ 播放出错")
        self.now_label.setStyleSheet("color: #d04545; font-size: 14px;")
        QTimer.singleShot(3000, self._reset_now_style)

    def _on_media_status(self, status):
        """媒体状态变化（用于更新系统媒体信息）"""
        log.info("媒体状态变化: %s，当前源=%s", _enum_info(status), self.player.source().toString())
        self._update_system_media()

    def _on_meta_data_changed(self):
        """流媒体元数据更新（ICY 等），提取当前播放的节目信息并显示。"""
        from PyQt6.QtMultimedia import QMediaMetaData
        md = self.player.metaData()

        # 常见的 ICY / Shoutcast 元数据字段：Title（节目/曲目名）、Artist（艺人/频率）、Description
        title = md.stringValue(QMediaMetaData.Key.Title)
        artist = md.stringValue(QMediaMetaData.Key.ContributingArtist)
        description = md.stringValue(QMediaMetaData.Key.Description)
        comment = md.stringValue(QMediaMetaData.Key.Comment)

        # 组合显示：优先「歌手 - 曲目」，否则单个标题，再其次用描述/备注
        parts = []
        if artist:
            parts.append(artist)
        if title and title != artist:
            parts.append(title)

        program_text = " — ".join(parts) if parts else ""
        if not program_text and description:
            program_text = description
        if not program_text and comment:
            program_text = comment

        # 超长截断（工具提示放完整内容）
        display = program_text
        if len(display) > 60:
            display = display[:58] + "…"
        self.now_program_label.setText(display)
        self.now_program_label.setToolTip(program_text)

        # 把节目信息也同步到系统媒体中心（控制中心通知）
        if self.is_playing and self.current_index >= 0:
            self._update_system_media()

    def _reset_now_style(self):
        self.now_label.setStyleSheet("color: #007AFF; font-size: 14px;")

    # ---- 录制 ----
    def _toggle_record(self):
        if self.record_proc:
            self._stop_record()
        else:
            self._start_record()

    def _start_record(self):
        if self.current_index < 0:
            QMessageBox.information(self, "提示", "请先选择并播放一个电台")
            return

        ffmpeg_path = find_ffmpeg()
        if not ffmpeg_path:
            QMessageBox.warning(
                self, "缺少 ffmpeg",
                "录制功能需要 ffmpeg。\n\n"
                "macOS:  brew install ffmpeg\n"
                "Windows:  winget install ffmpeg\n"
                "或从 https://ffmpeg.org 下载"
            )
            return

        # 未设置录制目录时，先让用户选择；取消则不录制
        if not self.record_dir:
            if not self.choose_record_dir():
                return

        name, url = self.radios[self.current_index]
        self.record_name = name
        self.record_url = url

        rec_dir = self.record_dir
        os.makedirs(rec_dir, exist_ok=True)

        # 文件名压缩：电台名最多16字符 + 短时间戳
        safe_name = re.sub(r'[\\/:*?"<>|]', '_', name)
        if len(safe_name) > 16:
            safe_name = safe_name[:14] + "~"
        self._rec_safe_name = safe_name
        self._rec_start_date = datetime.now().strftime("%m%d")
        self._rec_start_time = datetime.now().strftime("%H%M%S")
        self._rec_dir = rec_dir

        tmp_file = os.path.join(rec_dir, f"{safe_name}_{self._rec_start_time}.mp3")

        cmd = [
            ffmpeg_path, "-y",
            "-i", url,
            "-vn",
            "-acodec", "libmp3lame",
            "-ab", "128k",
            "-f", "mp3",
            tmp_file
        ]

        try:
            self.record_proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            QMessageBox.critical(self, "录制失败", f"启动 ffmpeg 失败：{e}")
            self.record_proc = None
            return

        time.sleep(0.5)
        if self.record_proc.poll() is not None:
            exit_code = self.record_proc.returncode
            self.record_proc = None
            QMessageBox.critical(self, "录制失败", f"ffmpeg 启动失败（退出码 {exit_code}）")
            try:
                os.remove(tmp_file)
            except Exception:
                pass
            return

        self.record_start_time = time.time()
        self.rec_btn.setText("■ 停止录制")
        self.rec_btn.setStyleSheet("QPushButton { color: #007AFF; font-weight: bold; }")

        self.rec_timer_label.setStyleSheet("color: #d04545; font-size: 13px; font-weight: bold;")
        self._rec_timer = QTimer(self)
        self._rec_timer.timeout.connect(self._update_rec_timer)
        self._rec_timer.start(100)

        self._update_rec_timer()

    def _update_rec_timer(self):
        if not self.record_start_time:
            return
        elapsed = time.time() - self.record_start_time
        hours = int(elapsed // 3600)
        mins = int((elapsed % 3600) // 60)
        secs = int(elapsed % 60)
        tenths = int((elapsed * 10) % 10)
        if hours > 0:
            t = f"● 录制中  {hours:02d}:{mins:02d}:{secs:02d}.{tenths}"
        else:
            t = f"● 录制中  {mins:02d}:{secs:02d}.{tenths}"
        self.rec_timer_label.setText(t)

    def _stop_record(self):
        if not self.record_proc:
            return

        if self.record_proc.poll() is not None:
            self.record_proc = None
        else:
            import signal
            try:
                self.record_proc.send_signal(signal.SIGINT)
                try:
                    self.record_proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.record_proc.kill()
                    self.record_proc.wait()
            except Exception:
                try:
                    self.record_proc.kill()
                    self.record_proc.wait()
                except Exception:
                    pass
            self.record_proc = None

        if hasattr(self, '_rec_timer'):
            self._rec_timer.stop()

        # 文件名：电台名_开始时间-结束时间.mp3（同一天不加日期）
        end_time = datetime.now().strftime("%H%M%S")
        end_date = datetime.now().strftime("%m%d")
        tmp_file = os.path.join(self._rec_dir, f"{self._rec_safe_name}_{self._rec_start_time}.mp3")

        if end_date == self._rec_start_date:
            final_file = os.path.join(
                self._rec_dir,
                f"{self._rec_safe_name}_{self._rec_start_time}-{end_time}.mp3"
            )
        else:
            final_file = os.path.join(
                self._rec_dir,
                f"{self._rec_safe_name}_{self._rec_start_date}{self._rec_start_time}-{end_date}{end_time}.mp3"
            )

        if os.path.exists(tmp_file):
            try:
                os.rename(tmp_file, final_file)
                size_mb = os.path.getsize(final_file) / 1024 / 1024
                self.rec_timer_label.setText(f"已保存：{os.path.basename(final_file)}\n({size_mb:.1f} MB)")
            except Exception as e:
                self.rec_timer_label.setText(f"保存失败：{e}")
        else:
            self.rec_timer_label.setText("录制文件未生成（可能流不可用）")

        self.rec_timer_label.setStyleSheet("color: #888; font-size: 13px;")
        self.rec_btn.setText("● 开始录制")
        self.rec_btn.setStyleSheet("QPushButton { color: #d04545; font-weight: bold; }")

        self.record_start_time = None
        self.record_name = None
        self.record_url = None

    # ---- 关闭窗口 ----
    def closeEvent(self, event):
        if self._really_quit:
            # 真正退出
            if self.record_proc:
                self._stop_record()
            self.player.stop()
            self.media_int.clear()
            if hasattr(self, 'tray_icon') and self.tray_icon:
                self.tray_icon.hide()
            event.accept()
            return

        # 如果没有托盘，直接退出
        if not self.tray_icon or not self.tray_icon.isVisible():
            self._really_quit = True
            if self.record_proc:
                self._stop_record()
            self.player.stop()
            self.media_int.clear()
            event.accept()
            return

        # 检查是否有记住的选择
        remembered = self.settings.value("close_behavior", None)
        if remembered in ("quit", "minimize"):
            reply = remembered
        else:
            reply = self._ask_close_behavior()
        if reply == "quit":
            self._really_quit = True
            if self.record_proc:
                self._stop_record()
            self.player.stop()
            self.media_int.clear()
            self.tray_icon.hide()
            event.accept()
        elif reply == "minimize":
            # 最小化到托盘
            event.ignore()
            self.hide()
            # 气泡提示
            self.tray_icon.showMessage(
                "📻 网络电台",
                "已最小化到状态栏，点击图标可恢复",
                QSystemTrayIcon.MessageIcon.Information,
                2000
            )
        else:
            # 取消
            event.ignore()

    def _ask_close_behavior(self):
        """询问关闭行为，返回 'quit' / 'minimize' / 'cancel'"""
        from PyQt6.QtWidgets import QMessageBox, QCheckBox

        dlg = QMessageBox(self)
        dlg.setWindowTitle("关闭")
        dlg.setText("关闭窗口后，要让电台继续在后台播放吗？")
        dlg.setInformativeText(
            "• 最小化到托盘：继续播放，可从状态栏图标控制\n"
            "• 完全退出：停止播放并退出程序"
        )

        btn_min = dlg.addButton("最小化到托盘", QMessageBox.ButtonRole.AcceptRole)
        btn_quit = dlg.addButton("完全退出", QMessageBox.ButtonRole.DestructiveRole)
        btn_cancel = dlg.addButton("取消", QMessageBox.ButtonRole.RejectRole)
        dlg.setDefaultButton(btn_min)

        # 记住选择复选框
        remember_cb = QCheckBox("记住我的选择，下次不再询问")
        dlg.setCheckBox(remember_cb)

        dlg.exec()

        clicked = dlg.clickedButton()
        choice = "cancel"
        if clicked == btn_min:
            choice = "minimize"
        elif clicked == btn_quit:
            choice = "quit"

        if remember_cb.isChecked() and choice != "cancel":
            self.settings.setValue("close_behavior", choice)

        return choice


# ============================================================
# 入口
# ============================================================

def _user_m3u_path():
    """返回用户可写的 radio.m3u 路径。

    打包成 .app 后，内置列表在只读的 app 包内，增删电台必须另存到可写目录，
    否则 save_radios 会因无写权限失败。
    """
    if sys.platform == "darwin":
        base = os.path.join(os.path.expanduser("~"), "Library", "Application Support", "网络电台")
    elif sys.platform == "win32":
        base = os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "网络电台")
    else:
        base = os.path.join(os.path.expanduser("~"), ".local", "share", "网络电台")
    try:
        os.makedirs(base, exist_ok=True)
    except Exception:
        base = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base, "radio.m3u")


def _resolve_m3u_path():
    """确定本次应使用的 radio.m3u 路径。

    - 脚本模式：用脚本同目录的 radio.m3u（找不到则稍后创建）。
    - 打包模式：内置列表在 sys._MEIPASS（只读），用户列表在可写目录；
      首次启动把内置列表复制到可写目录，之后增删都保存到那里。
    """
    if not getattr(sys, "frozen", False):
        p = find_m3u_file()
        log.info("_resolve_m3u_path(脚本): 找到 %s", p)
        if p:
            return p
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "radio.m3u")
        log.info("_resolve_m3u_path(脚本): 未找到，改用脚本目录 %s", p)
        return p

    bundled = None
    if getattr(sys, "_MEIPASS", None):
        bundled = os.path.join(sys._MEIPASS, "radio.m3u")
    log.info("_resolve_m3u_path(打包): 内置列表=%s，存在=%s", bundled, bool(bundled and os.path.exists(bundled)))

    user_path = _user_m3u_path()
    log.info("_resolve_m3u_path(打包): 用户列表=%s，存在=%s", user_path, os.path.exists(user_path))

    if os.path.exists(user_path):
        log.info("_resolve_m3u_path(打包): 使用已有用户列表 %s", user_path)
        return user_path

    if bundled and os.path.exists(bundled):
        # 首次启动：把内置列表复制到可写目录，方便后续保存
        try:
            shutil.copyfile(bundled, user_path)
            log.info("_resolve_m3u_path(打包): 首次启动，已复制内置列表到 %s", user_path)
            return user_path
        except Exception:
            log.exception("_resolve_m3u_path(打包): 复制内置列表失败，改用内置只读列表")
            return bundled

    log.warning("_resolve_m3u_path(打包): 既无用户列表也无内置列表，使用 %s", user_path)
    return user_path


def main():
    log.info("=" * 70)
    log.info("程序启动")
    log.info("Python: %s", sys.version.replace("\n", " "))
    log.info("平台: %s", sys.platform)
    log.info("frozen: %s", getattr(sys, "frozen", False))
    log.info("可执行文件: %s", sys.executable)
    log.info("启动参数: %s", sys.argv)
    log.info("工作目录: %s", os.getcwd())
    log.info("脚本文件: %s", __file__)
    log.info("PyInstaller 资源目录 _MEIPASS: %s", getattr(sys, "_MEIPASS", None))
    try:
        from PyQt6.QtCore import QT_VERSION_STR, PYQT_VERSION_STR
        log.info("PyQt6 Qt 版本=%s，PyQt 版本=%s", QT_VERSION_STR, PYQT_VERSION_STR)
    except Exception as e:
        log.warning("无法获取 PyQt6 版本: %s", e)

    try:
        m3u_path = _resolve_m3u_path()
        log.info("main: 最终 m3u_path=%s", m3u_path)
        if not os.path.exists(m3u_path):
            # 完全没有列表文件：创建一个空的（带示例注释）
            log.warning("main: %s 不存在，准备创建空列表", m3u_path)
            try:
                os.makedirs(os.path.dirname(os.path.abspath(m3u_path)), exist_ok=True)
                with open(m3u_path, "w", encoding="utf-8") as f:
                    f.write("#EXTM3U\n")
                    f.write(f"#Update: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                    f.write("# 示例：\n")
                    f.write("#EXTINF:-1,中央人民广播电台 音乐之声\n")
                    f.write("#https://example.com/stream.mp3\n")
                log.info("main: 已创建默认 radio.m3u")
            except Exception as e:
                log.exception("无法创建 radio.m3u")
                print(f"无法创建 radio.m3u：{e}", file=sys.stderr)
                sys.exit(1)

        radios = load_radios(m3u_path)
        log.info("main: 加载到的电台数量=%d", len(radios))
        for i, (n, u) in enumerate(radios):
            log.info("    电台[%d] %s -> %s", i, n, u)
        # 没有电台也启动，让用户自己添加

        app = QApplication(sys.argv)
        app.setApplicationName("网络电台")
        log.info("main: QApplication 创建完成")

        window = RadioWindow(radios, m3u_path)
        log.info("main: RadioWindow 创建完成，准备 show")
        window.show()
        log.info("main: window.show() 已调用，进入事件循环")

        sys.exit(app.exec())
    except Exception:
        log.exception("main 运行过程中发生异常")
        raise


if __name__ == "__main__":
    main()
