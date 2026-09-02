---
name: workbuddy-linux-port
description: "WorkBuddy（腾讯 AI Agent 桌面应用，Electron 架构）从 Windows 安装包移植到 Linux 并打包为 deb 的完整流程与踩坑手册。涵盖：拆包 NSIS/7z 安装包、提取 app.asar、替换 Linux Electron 39.2.7 运行时、编译/替换原生 .node 模块、处理 ABI 不匹配导致的 SIGSEGV、为腾讯私有模块制作 stub、调试移植后功能缺失；以及本仓库 build.sh 一键构建（版本自适应、换包缓存失效）、.github/workflows/build.yml 多架构 CI 自动打包（x64/arm64/loong64）与常见 workflow 语法坑。也适用于其它 Electron 应用（非 VS Code 分支）的 Linux 移植参考。"
---

# WorkBuddy → Linux 移植技能

把 Windows 版 WorkBuddy（`@genie/workbuddy-desktop`，Electron 应用）移植到 Linux 并打包为 deb。
**本仓库交付物**：`build.sh`（本地一键构建脚本）+ `.github/workflows/build.yml`（GitHub Actions 多架构 CI）。

> ⚠️ 非官方移植，仅供学习交流，版权归原开发方（腾讯）所有。
> 与 `traework-deb-repack` 的区别：TraeWork/CodeBuddy 是 **VS Code 分支**（有 `out/main.js`），
> 可直接借同源 Linux 运行时；WorkBuddy 是**自定义 Electron 应用**（入口 `main/index.js`），
> 无同源 Linux 版，需自行解决原生模块与私有依赖，且本仓库已实现自动化打包。

## 何时触发

- 拆包 WorkBuddy Windows 安装包（NSIS → `app-64.7z` → `resources/app.asar`）。
- 需要替换 Electron 运行时、编译/替换 Linux `.node` 原生模块。
- 遇到 `SIGSEGV`（段错误）、`Cannot find module 'bindings'`、`ELECTRON_RUN_AS_NODE` ABI 问题。
- 移植后部分功能不可用（设备指纹/微信联动等）需评估与降级。
- 用 `build.sh` 本地打包，或用 `build.yml` 在 CI 自动产出多架构 deb。

---

## 架构认知（动手前必读）

WorkBuddy 不是 VS Code 分支，结构如下：

```
app-64.7z 解压后/
  WorkBuddy.exe          # Windows Electron 二进制（不能直接用）
  resources/
    app.asar             # 应用代码（asar 归档，入口 package.json → main/index.js）
    app.asar.unpacked/   # ★ 原生模块与需解包的资源（移植主要改动点）
      node_modules/      # better-sqlite3 / node-pty / koffi / @tencent/*
      native/            # wechat-copydata-decoder（Windows 专属）
      resources/         # icon.png、插件、preload 脚本等
```

关键点：
- `main/*.js` 是 **webpack bundle**（`common.js` 2.7MB、`index.js` 867KB），
  纯 JS 依赖已被打进 bundle，**运行时只依赖 `app.asar.unpacked` 里的原生模块**。
  这大幅简化移植：只需处理少数几个 `.node`。
- 入口由 `app.asar/package.json` 的 `"main": "main/index.js"` 指定，
  Electron 会自动读取，无需额外配置。

---

## 一键构建脚本 `build.sh`（本仓库实际入口）

完整流水线（对应日志 阶段 1/5~5/5）：

```
拆包 Windows NSIS → 下载 Electron 39.2.7 Linux 运行时(按 --arch) → 组装 deb-pkg
→ 精简冗余(slim) → 桌面集成(启动脚本/图标/桌面入口) → 构建 deb
```

用法：
```bash
bash build.sh                                       # 默认 x64 / slim / 装好后安装
bash build.sh /path/WorkBuddy-win32-x64-user-*.exe  # 指定安装包（文件名须含版本号）
bash build.sh --arch arm64 --no-install             # 指定架构，仅构建不安装
bash build.sh --skip-extract                        # 复用现有 deb-pkg，跳过拆包
bash build.sh --extracted <已解压 app-64 目录>       # 复用已解压目录
```

阶段要点：
1. **拆包**：NSIS → 内层 `app-64.7z` → `resources/app.asar` + `app.asar.unpacked`。
2. **取 Electron**：下载 Electron 39.2.7 Linux 运行时（按目标架构）。
3. **组装**：Electron 运行时改名 `/opt/workbuddy/workbuddy` + `app.asar` 进 `deb-pkg`。
4. **原生模块**：按架构编译/替换 `better-sqlite3` 等（Windows/macOS 专属模块在 Linux 降级）。
5. **slim**：默认删除 `*.exe`、`*.dll`、`win32/`、`darwin/` 残留（约省 360MB；`--no-slim` 关闭）。
6. **打包**：`sed` 改写 `deb-pkg/DEBIAN/control` 的 `Version`/`Architecture`/`Installed-Size`，
   生成 `com.xydw.workbuddy_<版本>_<arch>.deb`（`dpkg-deb --root-owner-group`，并重算 `md5sums`）。

> 版本号**从 exe 文件名自动提取**（见陷阱 6）；换包由 `.workbuddy-source` 标记触发缓存失效（见陷阱 6）。

---

## 移植方案（已验证可行）

**核心思路**：Windows 的 JS 代码（asar）+ Linux 的 Electron 39.2.7 运行时 + Linux 原生模块。

| 组成部分 | 来源 | 说明 |
|---|---|---|
| Electron 运行时 | **Electron 39.2.7** Linux 包（官方或社区移植版） | ABI 与 `RUN_AS_NODE` 一致，避免 SIGSEGV；x64/arm64/loong64 需对应架构包 |
| 应用代码 | 自拆 Windows 包的 `app.asar` | 版本需与运行时兼容 |
| 原生模块 | 部分自带 + 部分自编译/替换 | 见下表 |
| 私有依赖 | 制作 stub 降级 | 见后文 |

### 原生模块处理清单（WorkBuddy 5.5.1 实测）

| 模块 | Windows 包内状态 | Linux 处理 | 结果 |
|---|---|---|---|
| koffi | 自带 `linux_x64/koffi.node` | **无需处理** | ✅ |
| better-sqlite3 | 仅 `win32-x64-136` | 自编译（Electron 39.2.7 ABI） | ✅ |
| node-pty | 无 linux prebuild | npm 装 `@lydell/node-pty-linux-x64` | ✅ |
| @tencent/qimei-node | 仅 mac/win，无 linux | 优先用社区 Linux 版；缺失则**制作 stub** | ⚠️ 遥测降级 |
| wechat-copydata-decoder | Windows 专属 | 代码已有 try/catch | ⚠️ 功能缺失 |

编译 better-sqlite3（Electron 39.2.7）：
```bash
# Electron headers 可从 electronjs.org 获取（无需 GitHub）
curl -sL -o eh.tar.gz "https://artifacts.electronjs.org/headers/dist/v39.2.7/node-v39.2.7-headers.tar.gz"
tar -xzf eh.tar.gz -C eh
export npm_config_nodedir=$PWD/eh/node_headers
npm install better-sqlite3 --build-from-source
```

---

## ⚠️ 关键陷阱

### 陷阱 1：`Cannot find module 'bindings'` —— 只复制 `.node` 不够

自编译的 `better-sqlite3` 依赖 `bindings`（及 `file-uri-to-path`）在运行时定位 `.node`。
只把编译出的 `.node` 复制进 `app.asar.unpacked` 会报 `Cannot find module 'bindings'`。

✅ 必须连带复制其**运行时 JS 依赖**：
```bash
cp -a linux_native/node_modules/{bindings,file-uri-to-path} \
      wb_pkg/.../app.asar.unpacked/node_modules/
```

### 陷阱 2：ABI 不匹配导致 `SIGSEGV`（段错误，退出码 139）

**现象**：主进程 GUI 正常，但 daemon 子进程崩溃
`Daemon app-server exited before ready: code=null signal=SIGSEGV`

**原因**：daemon 以 `ELECTRON_RUN_AS_NODE=1` 启动（见 `main/index.js` 的 spawn 处），
原生模块 ABI 强绑定，混用直接段错误。

**注意**：段错误发生在原生层，**JS 的 try/catch 无法拦截**。

**处理思路**：
- ❌ 不要跨大版本借 Electron 运行时（37↔39 的 ABI 差异就会触发此坑）。
- ✅ **本仓库固定使用 Electron 39.2.7**：其 `RUN_AS_NODE` 与主进程 ABI 一致，
  同一份 Linux 原生模块两个场景都能加载，SIGSEGV 完全消失。
- 结论：**优先选与原应用 ABI 匹配的 Electron 大版本**。

### 陷阱 3：腾讯私有包无法从 npm 获取

以下包在公开 npm 上不存在（私有/需鉴权），**无法安装，只能降级**：
`@tencent/qimei-node`、`@tencent/aegis-electron-sdk-v2`、
`@tencent/universal-report`、`@tencent/tencent-docs-ai-engine`

而公开可装的：
`better-sqlite3`、`@lydell/node-pty-linux-x64`、`koffi`、`@tencent-connect/qqbot-connector`

**stub 写法**（以 qimei 为例，避免加载 mac/win 原生二进制）：
```js
class QimeiStub {
    getVersion() { return ''; }
    getQimei36() { return Promise.resolve(''); }
    start() {} stop() {}
}
module.exports = QimeiStub;
```

### 陷阱 4：asar 提取可能报 ENOENT（可忽略）

```bash
asar extract app.asar out/   # 可能报 unpacked 内某文件缺失
```
只要主体目录（main/、resources/、package.json）提取出来即可，
缺失的是 unpacked 引用文件，不影响分析。

### 陷阱 5：网络 —— GitHub 不通但 npm 通

本环境实测：
- ❌ `github.com` 443 不通（无法下 Release 资产、无法 `gh auth login`）
- ✅ **SSH 到 GitHub 可用**（`git push` 正常）
- ✅ npm registry 通（`registry.npmjs.org`）
- ✅ `artifacts.electronjs.org` 通（可下 Electron headers）
- ✅ `registry.npmmirror.com` 通（可下 Node headers 等镜像资源）

**启示**：不要依赖"下载别人移植好的包"作为唯一路径，
利用 npm + npmmirror 完全可以自主编译所需原生模块。

### 陷阱 6：版本号从 exe 文件名提取 + 换包需缓存失效

- `build.sh` 从 `WIN_EXE` 文件名提取 `X.Y.Z` 作为 deb 的 `Version`
  （如 `WorkBuddy-win32-x64-user-5.5.1.37570276-9af62480.exe` → `5.5.1`）。
  **文件名必须含版本号**；CI 下载时若把 exe 固定命名为无版本号的名字，版本识别会失败/回退错误。
- `extracted/app-64/.workbuddy-source` 记录「exe 文件名 + 大小」。
  换包（版本号/大小变化）即视为新包，强制**重新覆盖解包**，
  避免「deb 标新版却装出旧版」（早期踩过的坑）。

### 陷阱 7：deb 架构命名 `x64` vs `amd64`

`--arch x64` 时，deb 的 `Architecture` 字段与文件名后缀是 **`amd64`**
（`build.sh` 内 `x64 → DEB_ARCH=amd64` 映射）。
因此 CI `build.yml` 的 matrix 用 `arch: x64`，但 artifact/release 的 glob **必须用 `debarch: amd64` 映射**：
```yaml
matrix:
  include:
    - arch: x64
      runner: ubuntu-24.04
      debarch: amd64
    - arch: arm64
      runner: ubuntu-24.04-arm
      debarch: arm64
# 上传/发布路径用 com.xydw.workbuddy_*_${{ matrix.debarch }}.deb
```
否则 `upload-artifact` 的 `com.xydw.workbuddy_*_x64.deb` 匹配不到实际 `*_amd64.deb`
而 `if-no-files-found: error` 失败（x64 job 构建成功但上传失败，整轮 failure）。

### 陷阱 8：`deb-pkg/DEBIAN/control` 模板必须 git 跟踪

`control` 是 `stage_deb` 的**输入模板**：`build.sh` 仅 `sed` 改写 `Version`/`Architecture`/`Installed-Size`，
**不自行生成**该文件。它必须纳入 git 跟踪。
曾被误加进 `.gitignore` 导致 CI `checkout` 缺失而 `die "未找到 .../DEBIAN/control"`。
注意区分：`md5sums` 才是真正生成物（可忽略）；`control` 不可忽略。

### 陷阱 9：CI workflow job 级 `if` 不能用 `matrix`/`secrets` 上下文

GitHub 在 job **创建前**评估 job 级 `if`，`matrix`/`secrets` 上下文不可用，
否则整个 workflow 解析失败、所有 run 立即 `failure`。
本仓库 `loong64` 已拆为**独立 job**，用 `workflow_dispatch` 的 `enable_loong64` input 控制
（x64/arm64 始终构建；loong64 默认跳过，需自托管 runner 标签 `loong64` + `ELECTRON_LOONG64_URL` secret）。

---

## 实测结果（WorkBuddy 5.5.1 / Electron 39.2.7 / deepin 25 / X11）

**最终方案**：官方 Windows `app.asar` + **Electron 39.2.7** 运行时
+ Linux 原生模块（koffi/better-sqlite3/node-pty + 社区 qimei Linux 版）+ 启动脚本。

- ✅ SIGSEGV = 0（daemon 正常，不再崩溃）
- ✅ GUI 窗口正常（标题栏三键显示，`--title-bar-style=custom` 生效）
- ✅ `CellJS container initialized`、`signalStartupFirstPaint` 首帧绘制完成（页面正常渲染）
- ✅ 原生模块 better-sqlite3 / node-pty / koffi / qimei 加载正常
- ✅ 平台识别 `workbuddy-linux-x64`、系统 git/python/node 自动使用
- ⚠️ 微信消息解码（wechat-copydata-decoder）为 Windows 专属，缺失自动降级

> 与社区结论一致：此类移植**部分功能可用**是正常预期。

### 标题栏三键修复（重要）

WorkBuddy 是自绘标题栏应用，Linux 下若三键不显示，启动时加：
```bash
--title-bar-style=custom
```
该参数让 WorkBuddy 自绘的标题栏（右上角最小化/最大化/关闭）正常显示。
否则窗口 `_MOTIF_WM_HINTS` decorations=0 且无三键。

---

## 验证清单

1. `dpkg-deb -c out.deb` 文件齐全、symlink 正确、架构字段正确（`amd64`/`arm64`/`loong64`）。
2. `ls .../app.asar.unpacked/node_modules/` 含 `bindings`、`file-uri-to-path`。
3. `deb-pkg/DEBIAN/control` 模板已纳入 git 跟踪（CI 构建必需）。
4. 启动后 `xdotool search --name WorkBuddy` 能查到窗口。
5. 日志确认 `CellJS container initialized` 且无模块加载错误。
6. 已知限制写入 `control` 的 `Description`，避免使用者误解。

---

## 关联

- **一键脚本**：`build.sh`（仓库根，拆包→组装→构建 deb，参数见上文）
- **CI 文档**：`CI.md`；**工作流**：`.github/workflows/build.yml`
- **产物**：`com.xydw.workbuddy_5.5.1-*_amd64.deb` / `_arm64.deb` / `_loong64.deb`
  （Artifacts 名 `deb-x64` / `deb-arm64` / `deb-loong64`）
- 同类技能：`traework-deb-repack`（VS Code 分支的移植，可对比参考）
