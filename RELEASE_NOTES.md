# WorkBuddy 5.5.2-7 (Linux deb)

> 非官方移植，仅供学习交流。WorkBuddy 及其相关资源版权归腾讯所有。

上游 Windows 安装包：`WorkBuddy-win32-x64-user-5.5.2.37672479-2b0177c3.exe`
运行时：**Electron 39.2.7** Linux 构建

## 安装 / Install

```bash
sudo dpkg -i com.xydw.workbuddy_5.5.2-7_amd64.deb
sudo apt-get install -f   # 补齐缺失的运行时依赖
```

## 运行 / Run

- 应用菜单搜索 **WorkBuddy** 并点击；
- 或终端执行 `workbuddy`（`/usr/bin/workbuddy` → `/opt/workbuddy/workbuddy.sh`）。

## 本次变更 / Changes（5.5.2-7）

本版本重点：**Linux 顶部标题栏与 Windows 版对齐**，消除标题栏与页面内容的遮挡。

- **标题栏左槽对齐 Windows**：Linux 下也创建自定义标题栏左槽，`折叠 / 搜索 / 筛选` 三个按钮
  通过 portal 进入标题栏（此前 Linux 被当作"非 Windows 非 Mac"第三态，三个按钮滞留在页面内）。
- **第一项菜单显示「关于」**：与 Windows 一致，不再显示 `WorkBuddy` 作为首菜单。
- **原生菜单栏置空**：非 darwin 平台保持 `Menu.setApplicationMenu(null)`，
  避免登录后重建原生菜单栏造成遮挡。
- **屏蔽侧边栏「发现应用」入口**：侧边栏应用切换器通用态（`industry-template-switcher__trigger--general`）
  会盖住 workspace 标题与版本号，Linux 下隐藏；选中应用后的应用芯片仍正常显示。
- 左槽图标尺寸/间距/分隔线按 Windows 参数补齐（24px / gap 2px / padding 8px）。

> 说明：`isHostWindows()` 这类平台判断**未做全局翻转**——命令安全、路径长度等逻辑
> 依赖真实 Windows 语义，仅放开标题栏布局相关调用点。

## 沿用特性 / Notes

- 基于官方 Windows 安装包转制，使用 **Electron 39.2.7** Linux 运行时。
- `better-sqlite3` 等原生模块已重编译对齐 Electron 39 ABI。
- 标题栏为应用自绘，窗口三键正常显示。
- 无 root / `chrome-sandbox` 未 setuid 时，启动脚本自动追加 `--no-sandbox`。
- 默认开启 `--slim`（剔除 Windows/macOS 冗余），体积约 144M 属正常。
- 详见仓库 `README.md` 与 `docs/转制方案.md`。

## 校验 / Checksum

```bash
sha256sum com.xydw.workbuddy_5.5.2-7_amd64.deb
# 期望值：ec3c1d750e938daca74e03b3dd0d481488c7c03ecac1e0b28ed0d7c9f94e8c4e
```

| 文件 | 大小 | SHA256 |
|------|------|--------|
| `com.xydw.workbuddy_5.5.2-7_amd64.deb` | 144M | `ec3c1d750e938daca74e03b3dd0d481488c7c03ecac1e0b28ed0d7c9f94e8c4e` |
