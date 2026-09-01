# WorkBuddy 5.4.7-5 (Linux deb)

> 非官方移植，仅供学习交流。WorkBuddy 及其相关资源版权归腾讯所有。

## 安装 / Install

```bash
sudo dpkg -i workbuddy_5.4.7-5_amd64.deb
sudo apt-get install -f   # 补齐缺失的运行时依赖
```

## 运行 / Run

- 应用菜单搜索 **WorkBuddy** 并点击；
- 或终端执行 `workbuddy`（已软链至 `/usr/bin/workbuddy`）。

## 说明 / Notes

- 基于官方 Windows 安装包转制，使用 **Electron 39.2.7** Linux 运行时。
- `better-sqlite3` 等原生模块已重编译对齐 Electron 39 ABI。
- 标题栏采用 `--title-bar-style=custom` 自绘，三键正常显示。
- 无 root / `chrome-sandbox` 未 setuid 时，启动脚本自动追加 `--no-sandbox`。
- 详见仓库 `README.md` 与 `docs/转制方案.md`。

## 校验 / Checksum

发布资产 `workbuddy_5.4.7-5_amd64.deb` 的 SHA256 可在下载后通过以下命令核对：

```bash
sha256sum workbuddy_5.4.7-5_amd64.deb
```
