#!/bin/bash
# 把解出的 Windows 版 UGREEN NAS 客户端用 Wine 包装成 amd64 deb
# 前置：已用 7z 解出 ugreen-tmp/app（即 app-64.7z 内容）
# 用法：bash build-ugreen-wine-deb.sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/ugreen-tmp/app"
ICON="$ROOT/ugreen-tmp/app/ugreen-app-asar/icon/favicon.png"
OUT="$ROOT/wine-deb"
DEB="$ROOT/ugreen-nas_1.19.0.78471_amd64.deb"

if [ ! -f "$SRC/UGREEN NAS.exe" ]; then
  echo "缺少 $SRC/UGREEN NAS.exe，请先 7z 解包 NSIS 与 app-64.7z" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/DEBIAN" "$OUT/opt/ugreen-nas" "$OUT/opt/ugreen-nas/app" "$OUT/opt/ugreen-nas/wine" "$OUT/usr/bin" \
         "$OUT/usr/share/applications" "$OUT/usr/share/icons/hicolor/256x256/apps"

# 1) 原 Windows 应用整体放进 /opt（--hard-dereference 打散硬链接，避免 immutable 系统 dpkg 建硬链接失败）
tar -C "$SRC" --hard-dereference -cf - . | tar -C "$OUT/opt/ugreen-nas/app" -xf -
[ -f "$ICON" ] && cp "$ICON" "$OUT/usr/share/icons/hicolor/256x256/apps/ugreen-nas.png"

# 1.5) 自带 deepin-wine（整树搬入；应用为 64 位，无需 32 位 runtime-i386）
if [ -d /opt/deepin-wine11-stable ]; then
  tar -C /opt/deepin-wine11-stable --hard-dereference -cf - . | tar -C "$OUT/opt/ugreen-nas/wine" -xf -
  echo "已打包 deepin-wine 到 /opt/ugreen-nas/wine（硬链接已打散）"
else
  echo "警告：未找到 /opt/deepin-wine11-stable，将改为依赖系统 wine" >&2
fi

# 2) Wine 启动器
cat > "$OUT/opt/ugreen-nas/ugreen-nas.sh" <<'EOF'
#!/bin/sh
# UGREEN NAS 客户端（Windows 构建）Wine 启动器（自带 deepin-wine）
set -e

APP_DIR="/opt/ugreen-nas/app"
WINE_ROOT="/opt/ugreen-nas/wine"
PREFIX="${WINEPREFIX:-$HOME/.wine-ugreen-nas}"

# 强制中文 locale，避免非中文系统界面中文显示为方框（参考 deepin-wine 官方做法）
if locale -a 2>/dev/null | grep -qi 'zh_CN'; then
  export LANG=zh_CN.UTF-8
  export LANGUAGE=zh_CN:zh
fi

# 优先用包内自带的 deepin-wine；否则回退到系统 wine / deepin-wine
WINE_BIN="${UGREEN_WINE_BIN:-}"
if [ -z "$WINE_BIN" ] && [ -x "$WINE_ROOT/bin/wine" ]; then
  WINE_BIN="$WINE_ROOT/bin/wine"
  export WINEDLLPATH="${WINEDLLPATH:-$WINE_ROOT/lib}"
fi
if [ -z "$WINE_BIN" ]; then
  for c in /opt/deepin-wine11-stable/bin/wine \
           /opt/deepin-wine-staging/bin/wine \
           /opt/deepin-wine10-stable/bin/wine \
           /opt/deepin-wine8-stable/bin/wine \
           /opt/deepin-wine6-stable/bin/wine \
           wine ; do
    if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then WINE_BIN="$c"; break; fi
  done
fi
if [ -z "$WINE_BIN" ]; then
  echo "错误：未找到 wine，请安装 deepin-wine11-stable 或 wine" >&2
  exit 1
fi
# 把 wine 所在目录加入 PATH，便于应用内再拉起 .exe 守护
WINE_DIR="$(dirname "$WINE_BIN")"
export PATH="$WINE_DIR:$PATH"

export WINEPREFIX="$PREFIX"
export WINEARCH=win64
export WINEDEBUG="-all"
# 禁止 Wine 自动创建菜单/桌面快捷方式
export WINEDLLOVERRIDES="winemenubuilder.exe=d"

# 首次运行：初始化 prefix，尽量装中文字体（winetricks 可用时）
if [ ! -d "$PREFIX" ]; then
  mkdir -p "$PREFIX"
  if command -v winetricks >/dev/null 2>&1; then
    winetricks -q cjkfonts >/dev/null 2>&1 || true
  fi
fi

# 以应用目录为工作目录，保证相对路径的 win32 守护被正确找到
cd "$APP_DIR" || exit 1

exec "$WINE_BIN" "$APP_DIR/UGREEN NAS.exe" \
  --no-sandbox \
  --disable-gpu \
  --use-gl=swiftshader \
  --enable-unsafe-swiftshader \
  "$@"
EOF

# 3) /usr/bin 入口
cat > "$OUT/usr/bin/ugreen-nas" <<'EOF'
#!/bin/sh
exec /opt/ugreen-nas/ugreen-nas.sh "$@"
EOF

# 4) 桌面文件
cat > "$OUT/usr/share/applications/ugreen-nas.desktop" <<'EOF'
[Desktop Entry]
Name=UGREEN NAS
Comment=UGREEN NAS 桌面客户端（Wine 运行）
Exec=ugreen-nas
Icon=ugreen-nas
Terminal=false
Type=Application
Categories=Network;FileTransfer;
StartupWMClass=ugreen nas.exe
EOF

# 5) control
cat > "$OUT/DEBIAN/control" <<EOF
Package: ugreen-nas
Version: 1.19.0.78471
Section: net
Priority: optional
Architecture: amd64
Depends: xdg-utils
Recommends: fonts-wqy-zenhei | fonts-noto-cjk
Installed-Size: __SIZE__
Maintainer: local packager <local@build>
Description: UGREEN NAS desktop client (Windows build, self-contained deepin-wine)
 绿联 NAS 桌面客户端。原版为 Windows 应用，本包自带 deepin-wine11-stable
 运行环境，开箱即用，无需目标机预先安装 wine / deepin-wine。
 核心功能依赖 Windows 专用守护进程（UgAgent / syncspace / videoPlayer，均为 64 位），
 在自带 Wine 下可运行。
 .
 首次启动自动初始化 WINEPREFIX（默认 ~/.wine-ugreen-nas）。
 若连接/守护异常，请确认依赖的运行库（如 .NET）已在前缀中可用。
EOF

chmod 755 "$OUT/opt/ugreen-nas/ugreen-nas.sh" "$OUT/usr/bin/ugreen-nas"

# 填 Installed-Size（KB）
SIZE=$(du -sk "$OUT/opt/ugreen-nas/app" | cut -f1)
sed -i "s/__SIZE__/$SIZE/" "$OUT/DEBIAN/control"

dpkg-deb --build "$OUT" "$DEB" >/dev/null
echo "BUILD_OK -> $DEB"
du -h "$DEB"
