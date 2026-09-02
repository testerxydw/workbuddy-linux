# WorkBuddy（buddywork）长期记忆

## 项目性质
- **包名**：`com.xydw.workbuddy`，`amd64`，`.deb` 格式。
- **产品**：腾讯 **CodeBuddy** 的 AI 编程工作台（Electron 工作台，`codebuddy` / `cbc-prewarm`）。
- **非官方重打包**：拆解官方 **Windows NSIS 安装包**（`WorkBuddy-win32-x64-user-*.exe`），保留跨平台 JS 层（`app.asar` / `app.asar.unpacked`），替换为 Linux Electron 运行时与原生二进制后重新打包，使其可在 Deepin / UOS / Debian 系运行。

## 转制关键要点（易错点）
1. **Electron 锁定 39.2.7**：与 Windows 包内置 Linux 原生模块 ABI 对齐；误用 37 会导致 `better-sqlite3` ABI 不匹配、daemon 崩溃、页面空白。
2. **重编译 `better-sqlite3@12.8.0`**：`target=39.2.7`，覆盖 `app.asar.unpacked` 内 `.node`，并补齐 `bindings` / `file-uri-to-path`。
3. **标题栏自绘**：`--title-bar-style=custom` + main.js `titleBarOverlay` 守卫，避免 Linux 标题栏白块/丢失。
4. **沙箱回退**：无 root 或 `chrome-sandbox` 未 setuid 时，启动脚本自动追加 `--no-sandbox`。
5. **补齐运行时依赖**：复制 `chrome_crashpad_handler` 避免启动 FATAL，`ulimit -n 65535` 提高文件描述符上限。
6. **Windows/macOS 专属模块安全降级**：`qimei-node` / `turing-sdk` / `wechat-copydata-decoder` 等按代码逻辑降级，不影响主流程。

## 产出与发布
- 产出 deb 版本：`5.4.7-10`、`5.5.1-3`（amd64）。
- 发布目标：GitHub Release（仓库 `testerxydw/github-releaase-pkg-url`，tag `2026-09-02`）。
- 安装：`sudo dpkg -i com.xydw.workbuddy_*.deb`，终端执行 `workbuddy`。

## 记忆归属（重要）
- 本项目记忆**独立入库**于此目录（`workbuddy-win-to-linux/.codebuddy/memory`），与 codebuddy（github-releaase-pkg-url）项目的记忆**分库管理，互不混用**。
