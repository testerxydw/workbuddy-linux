# WorkBuddy Linux deb 自动构建（CI 使用说明）

> 工作流文件：`.github/workflows/build.yml`
> 作用：把官方 Windows 安装包（`WorkBuddy-win32-x64-user-*.exe`）自动重打包为 Linux deb，支持多架构。

---

## 一、前置准备：配置仓库 Secrets

仓库 → **Settings → Secrets and variables → Actions → New repository secret**：

| Secret | 必需 | 说明 |
|--------|------|------|
| `WIN_EXE_URL` | **必需** | Windows 安装包直链，文件名**必须含版本号**，例如 `https://.../WorkBuddy-win32-x64-user-5.5.1.37570276-9af62480.exe`。`build.sh` 从该文件名自动提取应用版本（deb 的 `Version` 字段）。 |
| `ELECTRON_LOONG64_URL` | 仅 loong64 | 龙芯/UOS/Deepin 定制 Electron 的 `electron-v39.2.7-linux-loong64.zip` 下载地址。未配置时 loong64 架构自动跳过，不影响 x64/arm64。 |

> ⚠️ `WIN_EXE_URL` 缺失时，x64/arm64 的「获取 Windows 安装包」步骤会直接失败（`exit 1`）。

---

## 二、触发方式

1. **手动触发**：Actions 页面 → `build-deb` → **Run workflow**。
2. **推送 tag**：`git tag vX.Y.Z && git push --tags`（tag 形如 `v5.5.1`）。
3. **发布 Release**：在 GitHub 创建 Release 并 **Publish**，工作流会把每个架构的 deb 自动上传为该 Release 的资产。

---

## 三、架构矩阵

| 架构 | Runner | 说明 |
|------|--------|------|
| `x64` | `ubuntu-24.04`（官方） | 默认架构，Electron 官方 x64 构建 |
| `arm64` | `ubuntu-24.04-arm`（官方） | 需编译 `better-sqlite3`（`setup-node` 提供 npm） |
| `loong64` | `self-hosted, loong64` | 需自托管 runner + 配置 `ELECTRON_LOONG64_URL`；否则该 job 自动跳过 |

- `fail-fast: false`：某个架构失败不会中断其他架构。
- 默认开启 `--slim`（剔除 Windows/macOS 冗余文件），通过 `--arch` 参数化每个架构的 Electron、原生模块与 `Architecture` 字段。

---

## 四、构建流程（build.sh 内部）

1. **拆包**：解 Windows NSIS 安装器 → 解内层 `app-64.7z`，得到 `app.asar` + `app.asar.unpacked`。
2. **取 Electron**：下载对应架构的 Electron 39.2.7 Linux 运行时。
3. **组装**：把 Electron 运行时（改名 `/opt/workbuddy/workbuddy`）+ `app.asar` 组装进 `deb-pkg`。
4. **原生模块**：按架构编译/替换 `better-sqlite3` 等（Windows/macOS 专属模块在 Linux 降级）。
5. **slim**：默认删除 `*.exe`、`*.dll`、`win32/`、`darwin/` 残留。
6. **打包**：生成 `com.xydw.workbuddy_<版本>_<arch>.deb`，`Architecture` 写入 `control`。

**缓存失效**：`build.sh` 在 `extracted/app-64/.workbuddy-source` 记录源包标识（exe 文件名 + 大小）。
换包（版本号变化）会强制重新覆盖解包，避免误用旧缓存导致「deb 标新版却装出旧版」。

---

## 五、获取产物

- 每次构建完成后，在 **Actions → 对应 run → Artifacts** 提供：
  - `deb-x64`、`deb-arm64`、`deb-loong64`
  - 下载即得 `com.xydw.workbuddy_<版本>_<arch>.deb`
- 若由 **Release（published）** 触发，deb 会自动出现在该 Release 的 **Assets** 中，任何人可直接下载。

---

## 六、发布一个版本（推荐流程）

1. 在 Secrets 中把 `WIN_EXE_URL` 指向目标 Windows 安装包直链（文件名含版本号）。
2. 推送 tag：`git tag v5.5.1 && git push --tags`，或手动 Run workflow。
3. 等待 x64 / arm64（loong64 视配置）三个架构完成，从 Artifacts 或 Release 资产取 deb。
4. 需要 Release 资产时：创建 GitHub Release 并 Publish，工作流自动上传各架构 deb。

---

## 七、loong64 特殊处理

- 需准备一台 loong64 自托管 runner：**Settings → Runners → New self-hosted runner**，标签设为 `loong64`。
- 必须配置 `ELECTRON_LOONG64_URL`，否则 loong64 job 跳过。
- 无自托管机器时的 **QEMU 替代方案**见 `build.yml` 文件末尾注释（改用 `loongnix/debian-loong64` 容器，需自行保证镜像内含 `rsync/7z/dpkg-dev/python3/curl/node` 且能访问 `ELECTRON_LOONG64_URL`）。

---

## 八、本地构建对照

```bash
# 把 Windows 安装包放到仓库根（文件名含版本号），然后：
bash build.sh --arch x64     # 默认 --slim，产出 amd64 deb
bash build.sh --arch arm64   # 需 arm64 交叉编译环境
sudo dpkg -i com.xydw.workbuddy_*.deb
```

---

## 九、常见问题

- **x64/arm64 报 “缺少仓库 Secret: WIN_EXE_URL”**：未配置 `WIN_EXE_URL`。
- **deb 版本号与 exe 不符**：确保 `WIN_EXE_URL` 文件名含版本号（如 `...-5.5.1.37570276-xxx.exe`）；CI 已修复为保留原始文件名，本地同理。
- **arm64 原生模块报错**：检查 `setup-node` 步骤是否正常提供 npm（`better-sqlite3` 需要 `node-gyp` 编译）。
- **deb 体积偏小（约 140M）**：`--slim` 默认开启剔除了约 360MB 的 Windows 冗余，属正常；Electron 引擎改名 `/opt/workbuddy/workbuddy`，不在包内以 `electron` 命名。
- **loong64 被跳过**：属预期，除非同时配置 `ELECTRON_LOONG64_URL` 与自托管 runner。
