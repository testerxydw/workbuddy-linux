# 项目长期记忆 (workbuddy-win-to-linux)

## workbuddy-linux-port 约定与事实
- **标题栏**：WorkBuddy 用**自绘标题栏**（`build.sh` launcher 用 `--title-bar-style=custom`），显示良好，**不要**改成 `--title-bar-style=native`（那是 trae 因 DDE 标题栏三键问题才需要的）。曾误建议把 trae 的 native 参数合入 workbuddy.sh，已否决。
- **重打包来源**：从 Windows NSIS 安装包拆出 + 套 Electron Linux 运行时（39.2.7，社区/aha-kit 移植版，避 SIGSEGV）重打包；**不内置 python/node 运行时**（依赖系统 python3 + electron 自带 node）；`stage_slim` 只留 linux 原生模块。
- **官方包 5.4.5 重打包三版**（workspace 目录，原包未动）：
  - `com.tencent.workbuddy_5.4.5-slim_amd64.deb`（354MB/1541MB，删跨平台垃圾 29MB）
  - `…-slim2`（266MB/953MB，再删 runtime 587MB）⚠️风险：官方 app 或硬编码调 `resources/runtime/python`，删后依赖 python 功能(MCP/AI工具链)可能异常，需桌面实测
  - `…-slim3`（260MB/897MB，再精 locale/LICENSES 56MB）——官方包框架内安全极限
  - 注：slim2→slim3 仅瘦 56MB；那 252MB node_modules 差(官方276 vs 我们24)是官方 5.4.5 真实依赖，非可删垃圾；我们 24MB 源于 5.5.1 Windows 源依赖集更小（换源），非删文件可得。
- **包体积对比关键数**：原包 5.4.5 deb 实测 362MB（曾误抄 trae 的 273MB）/ 解包 1570MB；我们 com.xydw.workbuddy 5.5.1 解包 ~633MB。差 ~920MB 主因 runtime 591 + 全平台依赖 258 + locales 40。
- trae-solo-cn_0.1.61：同为拆 win 重打包，electron 39.2.7 同源，无内置 runtime，跨平台垃圾已清零，app 为解开目录，launcher 含 DDE 参数（--title-bar-style=native 等）。
- **asar 改包能力（2026-09-03 打通）**：本机无 asar npm 模块，但有纯 node 工具 `/media/dp25/DATA/deb/fcitx5-deb/workbuddy-win-to-linux/asar_tool.js`（extract/pack 两子命令），完整复刻 Electron C++ asar 的 pickle 前缀格式，无需 electron 进程、绝不卡：
  - 头部布局：offset0 uint32=4(P0)、4 uint32=ceil4(H)+8(P1)、8 uint32=ceil4(H)+4(P2)、12 uint32=H(真实 JSON header 长度 P3)；JSON 从 offset16 起；`dataStart=16+ceil4(H)`；file data 偏移相对 dataStart。
  - pack 按原 header 顺序重排内部文件偏移、重算 size，保留 unpacked/link/executable；文件含 `integrity` 则重算 SHA256(base64)。
  - 坑：用 electron 主进程跑 asar 解/压会**卡死**（同步跑完但 event loop 不退出，需 `process.exit(0)`）；且本机 electron **不支持 `--require` 主进程预加载**（preload 方案不可行），故改走直接改 asar 文件。
- **菜单栏隐藏补丁（2026-09-03）**：WorkBuddy 在 `_p1UiPrelude` 对 Linux 已 `Menu.setApplicationMenu(null)`，但登录后 `setMenuUserId`/切语言等会再次 `buildAndSetApplicationMenu`（`main/menu-builder.js`）重建原生菜单栏遮挡窗口。修复：该函数加 `if (process.platform !== "darwin") { electron.Menu.setApplicationMenu(null); return; }`。已做成 `build.sh` 的 `stage_patch_app`（stage_assemble 之后、作用于 `$RES_DIR/app.asar`），可复现；产出 `com.xydw.workbuddy_5.5.1-6_amd64.deb` 已装。
  - 副作用：null 菜单会去掉 Linux 原生 Edit 菜单（撤销/重做/复制/粘贴/全选），但 web 输入框里通常仍可用（Chromium 默认）。若实测编辑快捷键异常，可改 `win.setMenuBarVisibility(false)` 保留菜单对象。
