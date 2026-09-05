#!/usr/bin/env bash
# ============================================================================
# WorkBuddy Linux 自动更新探测器
#
# 流程：
#   1. 读取仓库当前记录的 Windows 安装包版本（来自 RELEASE_NOTES.md）
#   2. 调用 Windows 端更新接口探测是否有更新
#        GET https://copilot.tencent.com/v2/update?platform=workbuddy-win32-x64-user&version=<当前版本>
#      接口语义：返回「比请求版本更新」的版本；已是最新则返回空（HTTP 204 或空 JSON）
#   3. 比较版本号；若无更新直接退出（不触碰 git）
#   4. 若有更新：
#        - 更新 RELEASE_NOTES.md 顶部上游安装包名 / 下载直链
#        - 把下载直链写入 latest-windows-exe.txt（供 CI 读取，免手动维护 secret）
#        - 打附注 tag vX.Y.Z-1 并推送 main + tag
#        - tag push 自动触发 .github/workflows/build.yml 构建并发布 GitHub Release
#
# 依赖：curl / git / python3
# 用法：bash check-update.sh            # 探测 + 有更新则自动更新仓库
#       DRY_RUN=1 bash check-update.sh  # 只打印将要执行的动作，不落盘/不推送
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

API="https://copilot.tencent.com/v2/update"
PLATFORM="workbuddy-win32-x64-user"
NOTES="RELEASE_NOTES.md"
DRY_RUN="${DRY_RUN:-0}"

log()  { echo "[check-update] $*"; }
die()  { echo "[check-update][错误] $*" >&2; exit 1; }

[[ -f "$NOTES" ]] || die "缺少 $NOTES"

# ---------- 1. 读取仓库当前 Windows 版本 ----------
CUR_EXE=""
# 优先用 latest-windows-exe.txt（脚本每次更新时写入的新地址，作为权威单一信息源），
# 避免从 RELEASE_NOTES 多段 changelog 里 grep 到旧版本。文件不存在时回退 RELEASE_NOTES。
if [[ -f latest-windows-exe.txt ]]; then
  CUR_EXE=$(grep -oE 'WorkBuddy-win32-x64-user-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+\.exe' latest-windows-exe.txt | head -1 || true)
fi
if [[ -z "$CUR_EXE" ]]; then
  CUR_EXE=$(grep -oE 'WorkBuddy-win32-x64-user-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]+\.exe' "$NOTES" | head -1 || true)
fi
CUR_FULL=$(echo "$CUR_EXE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
SRC_NOTE="$NOTES"; [[ -f latest-windows-exe.txt ]] && SRC_NOTE="latest-windows-exe.txt"
[[ -n "$CUR_FULL" ]] || die "无法解析当前 Windows 版本（latest-windows-exe.txt / $NOTES）"
log "当前仓库 Windows 版本: $CUR_FULL（来源: $SRC_NOTE）"

# ---------- 2. 探测更新接口 ----------
FEED_URL="${API}?platform=${PLATFORM}&version=${CUR_FULL}"
log "探测更新接口: $FEED_URL"
RESP=$(curl -s --max-time 20 "$FEED_URL" || true)
if [[ -z "$RESP" || "$RESP" == "{}" || "$RESP" == "[]" ]]; then
    log "接口返回空 —— 当前已是最新，无需更新。"
    exit 0
fi

NEW_FULL=$(echo "$RESP" | grep -oE '"version":"[0-9][0-9.]*"'   | head -1 | sed -E 's/"version":"//; s/"//' || true)
NEW_URL=$( echo "$RESP" | grep -oE '"url":"https?://[^"]+"'     | head -1 | sed -E 's/"url":"//; s/"//' || true)
[[ -n "$NEW_FULL" && -n "$NEW_URL" ]] || {
    log "接口返回缺少 version/url 字段，视为无更新。原始响应: $RESP"
    exit 0
}
log "接口返回最新版本: $NEW_FULL"
log "下载直链: $NEW_URL"

# ---------- 3. 版本比较（4 段整数，逐段比较） ----------
ver_gt() {  # ver_gt <new> <cur>  —— new 严格大于 cur 时返回 0
    local IFS='.'
    read -ra a <<< "$1"; read -ra b <<< "$2"
    local n=${#a[@]} m=${#b[@]} i
    for (( i=0; i < (n>m?n:m); i++ )); do
        local x=${a[i]:-0} y=${b[i]:-0}
        (( x > y )) && return 0
        (( x < y )) && return 1
    done
    return 1
}
if ! ver_gt "$NEW_FULL" "$CUR_FULL"; then
    log "接口版本($NEW_FULL)未高于当前($CUR_FULL) —— 无更新。"
    exit 0
fi

# ---------- 4. 有更新：计算版本与文件名 ----------
NEW_EXE_NAME="$(basename "${NEW_URL%%\?*}")"
APP_V="$(echo "$NEW_FULL" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
DEB_REV=1
NEW_TAG="v${APP_V}-${DEB_REV}"

log "发现新版本！app=$APP_V  deb=${APP_V}-${DEB_REV}  tag=$NEW_TAG"

# 已存在该 tag 则跳过（幂等）
if git rev-parse -q --verify "refs/tags/$NEW_TAG" >/dev/null; then
    log "tag $NEW_TAG 已存在，跳过（避免重复）。"
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY_RUN] 将更新 $NOTES 顶部为: $NEW_EXE_NAME / $NEW_URL"
    log "[DRY_RUN] 将写入 latest-windows-exe.txt: $NEW_URL"
    log "[DRY_RUN] 将打 tag $NEW_TAG 并推送 origin main + tag"
    exit 0
fi

# ---------- 5. 落地：更新 RELEASE_NOTES / 写 url 文件 ----------
python3 - "$NEW_FULL" "$NEW_EXE_NAME" "$NEW_URL" "$APP_V" "$DEB_REV" <<'PY'
import sys
new_full, new_exe, new_url, app_v, deb_rev = sys.argv[1:6]
path = "RELEASE_NOTES.md"
lines = open(path, encoding="utf-8").read().split("\n")
for i, l in enumerate(lines):
    if l.startswith("# WorkBuddy") and "(Linux deb)" in l:
        lines[i] = f"# WorkBuddy {app_v}-{deb_rev} (Linux deb)"
    if "上游 Windows 安装包" in l:
        lines[i] = f"上游 Windows 安装包：`{new_exe}`"
    if l.startswith("下载：") or l.startswith("下载:"):
        lines[i] = f"下载：`{new_url}`"
open(path, "w", encoding="utf-8").write("\n".join(lines))
print(f"[check-update] RELEASE_NOTES.md 已更新为 {app_v}-{deb_rev}")
PY

printf '%s\n' "$NEW_URL" > latest-windows-exe.txt
log "已写入 latest-windows-exe.txt"

# ---------- 6. 提交 + 打 tag + 推送（触发 CI） ----------
git add RELEASE_NOTES.md latest-windows-exe.txt
git commit -m "chore: 上游更新至 WorkBuddy ${NEW_FULL}" >/dev/null
git tag -a "$NEW_TAG" -m "WorkBuddy ${APP_V} Linux 打包 (${NEW_TAG})

基于上游 Windows 安装包转制:
  ${NEW_EXE_NAME}
下载:
  ${NEW_URL}"
git push origin main
git push origin "$NEW_TAG"
log "已推送 main 与 tag $NEW_TAG —— GitHub Actions 将自动构建并发布 Release。"
