#!/bin/bash
# 把官方 绿联云-NAS amd64 包改造成「自带 wine + 官方渲染逻辑(run_v4.sh)」的自包含包。
# 目标：deepin 上表现=官方；其它 x86_64 发行版(glibc>=2.28)装完即跑，无需系统 wine 包。
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG=official
APPID=com.ugreen.nas.xydw
FILES="$ROOT/$PKG/opt/apps/$APPID/files"
DEB="$ROOT/ugreen-nas-self_1.19.0.2160_amd64.deb"

echo "== 1) 打包 deepin-wine10-stable(官方同款) 到 files/deepin-wine =="
mkdir -p "$FILES/deepin-wine"
tar -C /opt/deepin-wine10-stable --hard-dereference -cf - . | tar -C "$FILES/deepin-wine" -xf -

echo "== 2) 打包 deepin-wine-helper 工具到 files/tools =="
mkdir -p "$FILES/tools"
tar -C /opt/deepinwine/tools --hard-dereference -cf - . | tar -C "$FILES/tools" -xf -
# arm 专用软链，x86_64 场景无用，去掉避免悬挂
rm -f "$FILES/tools/box86-activex"

echo "== 3) 修补包内 run_v4.sh 的两处跨发行版硬伤 =="
python3 - "$FILES/tools/run_v4.sh" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read()
# 3a) GL 探测路径改为包内(原硬编码 /opt/deepinwine/tools/gl-wine)
assert 'gl_wine_path="/opt/deepinwine/tools/gl-wine"' in s, "gl_wine_path 未找到"
s=s.replace('gl_wine_path="/opt/deepinwine/tools/gl-wine"','gl_wine_path="$SHELL_DIR/gl-wine"')
# 3b) 去掉 deepin-wine-banner 的致命退出：让 banner 命令忽略错误，并把随后的 if 改为 false，
#     使内部的 debug_log/exit 1 永不执行（纯 ASCII 锚点，避免中文匹配问题）
anchor='  "$SHELL_DIR/deepin-wine-banner"\n    if [[ $? != 0 ]]; then'
assert anchor in s, "banner 锚点未找到"
s=s.replace(anchor, '  "$SHELL_DIR/deepin-wine-banner" >/dev/null 2>&1 || true\n    if false; then')
open(p,"w").write(s)
print("patched run_v4.sh OK")
PY

echo "== 4) 改写 run.com...sh：指向包内 wine 与包内 run_v4.sh =="
RUN="$FILES/run.$APPID.sh"
sed -i 's#^START_SHELL_PATH=.*#START_SHELL_PATH="/opt/apps/'"$APPID"'/files/tools/run_v4.sh"#' "$RUN"
sed -i 's#^export APPRUN_CMD=.*#export APPRUN_CMD="/opt/apps/'"$APPID"'/files/deepin-wine/bin/wine"#' "$RUN"
chmod 755 "$RUN"

echo "== 5) control：去掉 deepin 独占依赖，补 p7zip-full + 推荐 libgl1 =="
CTRL="$ROOT/$PKG/DEBIAN/control"
python3 - "$CTRL" <<'PY'
import sys
p=sys.argv[1]
lines=open(p).read().splitlines()
out=[]; i=0
while i<len(lines):
    l=lines[i]
    if l.startswith("Depends:"):
        out.append("Depends: p7zip-full, fonts-wqy-microhei, fonts-noto-cjk")
        # 在其后插入 Recommends
        out.append("Recommends: libgl1, libglu1-mesa")
    elif l.startswith("Installed-Size:"):
        out.append("Installed-Size: __SIZE__")
    else:
        out.append(l)
    i+=1
open(p,"w").write("\n".join(out)+"\n")
print("control 改写完成")
PY
SIZE=$(du -sk "$ROOT/$PKG" | cut -f1)
sed -i "s/__SIZE__/$SIZE/" "$CTRL"

echo "== 6) 为非 deepin 桌面补 /usr/share/applications + /usr/share/icons + /usr/bin 入口 =="
mkdir -p "$ROOT/$PKG/usr/share/applications" "$ROOT/$PKG/usr/share/icons" "$ROOT/$PKG/usr/bin"
cp "$FILES/../entries/applications/$APPID.desktop" "$ROOT/$PKG/usr/share/applications/$APPID.desktop"
cp -r "$FILES/../entries/icons/hicolor" "$ROOT/$PKG/usr/share/icons/hicolor"
cat > "$ROOT/$PKG/usr/bin/ugreen-nas" <<EOF
#!/bin/sh
exec /opt/apps/$APPID/files/run.$APPID.sh "\$@"
EOF
chmod 755 "$ROOT/$PKG/usr/bin/ugreen-nas"

echo "== 7) 重新打包 =="
rm -f "$DEB"
dpkg-deb --build "$ROOT/$PKG" "$DEB" >/dev/null
echo "BUILD_OK -> $DEB"
du -h "$DEB"
