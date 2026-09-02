# WorkBuddy CN（Linux 重打包版）

> ⚠️ 非官方移植 · 仅供学习交流
> Unofficial repack, for study/exchange only.
> 仓库已公开，但仅供个人学习/研究使用，请勿用于商业用途或大规模再分发。
> Public repo, but for personal study/research only — no commercial use or mass redistribution.

---

## 简介 / Introduction

WorkBuddy 是腾讯 CodeBuddy 推出的 AI 编程工作台，官方仅提供 Windows / macOS 安装包。
本项目将其**官方 Windows NSIS 安装包**拆包后，替换 Linux 平台的 Electron 运行时与原生模块，
重新打包为 Debian（`deb`）安装包，使其可在 Deepin / UOS / Debian 系 Linux 上运行。

WorkBuddy CN (Linux repack). This project unpacks the official Windows installer,
replaces the platform-specific Electron runtime and native modules with Linux builds,
and repackages it as a `deb` package for Deepin / UOS / Debian-based Linux.

---

## 免责声明 / Disclaimer

- 本仓库**不包含**任何 WorkBuddy 官方二进制、源代码或受版权保护的资源，仅包含转制脚本与说明文档。
- WorkBuddy 及其相关资源版权归腾讯所有。请使用你**自行下载**的官方 Windows 安装包作为源材料。
- 本项目仅供个人学习与技术研究，不得用于商业用途或再分发官方资源。
- 本仓库现已**公开**，但用途仍仅限于个人学习与技术研究；**不得用于商业用途，亦不得对本产物或官方资源进行大规模再分发**。使用本软件即视为同意上述条款，一切后果由使用者自行承担。

---

## 系统要求 / Requirements

- 发行版：Deepin 23 / UOS v25 / Debian 12+（amd64）
- 运行依赖（由 `deb` 的 `Depends` 自动处理）：`libgtk-3-0`、`libnss3`、`libgbm1`、`libasound2` 等
- 构建依赖：`bash`、`rsync`、`p7zip`（`7z`）、`dpkg-deb`、`python3`、`curl`、`ImageMagick`（可选，用于生成多尺寸图标）

---

## 快速安装 / Quick Install

从 GitHub Release 下载对应版本的 `com.xydw.workbuddy_<version>_amd64.deb`，然后：

```bash
sudo dpkg -i com.xydw.workbuddy_*.deb
sudo apt-get install -f   # 若提示缺少运行时依赖，自动补齐
```

启动方式：

- 应用菜单搜索 **WorkBuddy** 并点击；
- 或在终端执行：`workbuddy`（已软链至 `/usr/bin/workbuddy`，指向 `/opt/workbuddy/workbuddy`）。

---

## 从源码构建 / Build from Source

1. 准备官方 Windows 安装包 `WorkBuddy-win32-x64-user-*.exe`，放置于仓库根目录
   （或使用 `--extracted <目录>` 复用已解压目录）。
2. 运行构建脚本：

```bash
bash build.sh
# 指定安装包路径：
bash build.sh /path/to/WorkBuddy-win32-x64-user-*.exe
```

### 构建流水线 / Pipeline

1. 拆包 Windows NSIS → 解压内层 `app-64.7z`
2. 下载 **Electron 39.2.7** Linux x64 运行时（优先 npmmirror 镜像，失败回退 GitHub）
3. 组装 `deb-pkg`（Electron 运行时 + WorkBuddy JS 资源层 `app.asar` / `app.asar.unpacked`）
4. 重编译 `better-sqlite3` 等 Linux 原生模块（ABI 对齐 Electron 39）
5. 桌面集成（启动脚本 / 图标 / `.desktop`）
6. 构建 deb（自增 `Version`、重算 `Installed-Size`、生成 `md5sums`）

产物：`com.xydw.workbuddy_<version>_amd64.deb`

### 常用参数 / Options

| 参数 | 说明 |
|------|------|
| `--skip-extract` | 跳过拆包，复用现有 `deb-pkg` |
| `--slim` | 精简 Windows/macOS 专有冗余文件 |
| `--no-install` | 仅构建 deb，不执行 `dpkg -i` |
| `--extracted <dir>` | 复用已解压的 app-64 目录 |

---

## 目录结构 / Layout

```
build.sh                 # 唯一构建入口：拆包 → 组装 → 原生模块 → 桌面集成 → 构建 deb
docs/转制方案.md          # 转制技术方案文档（含已落地修复要点）
deb-pkg/DEBIAN/control    # 包元信息（纳入版本库）
.gitignore               # 排除大二进制与中间产物
```

> 注：`deb-pkg/opt`、`deb-pkg/usr`、`*.deb`、`extracted-win/` 等二进制与中间产物已被
> `.gitignore` 排除，不纳入版本库（运行时由 `build.sh` 重新生成）。

---

## 已知问题 / Known Issues

- 部分 Windows/macOS 专属原生模块（`qimei-node` / `turing-sdk` / `wechat-copydata-decoder`）
  按代码逻辑安全降级，不影响主流程。
- 无 root 或 `chrome-sandbox` 未 setuid 时，启动脚本自动追加 `--no-sandbox`。
- 标题栏采用 `--title-bar-style=custom` 自绘，三键（最小化/最大化/关闭）正常显示。
- 需 Electron 39 运行时：使用 Electron 37 会因 `better-sqlite3` ABI 不匹配导致 daemon 子进程崩溃、页面空白。

---

## 许可证 / License

- 本仓库转制脚本以 **MIT** 许可。
- WorkBuddy 相关资源版权归腾讯所有，请遵守其官方许可协议。
