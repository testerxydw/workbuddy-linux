# WorkBuddy Linux 移植长期记忆

## 运行时版本
- WorkBuddy 5.4.x 需 Electron 39.x 运行时（锁定 39.2.7）。Electron 37 致 daemon better-sqlite3 ABI 不匹配，页面空白。

## 原生模块
- better-sqlite3 须用对应 Electron ABI 的 Linux ELF .node（npm_config_target=39.2.7，版本 12.8.0）。
- 复制 bindings、file-uri-to-path 到 app.asar.unpacked/node_modules/。
- qimei-node Linux 下因 appKey 缺失跳过；turing-sdk 仅 macOS/Windows 安全降级；wechat-copydata-decoder Windows 专属 try/catch 降级。

## Electron 39 新增文件
- 必须复制 chrome_crashpad_handler，否则启动 FATAL 找不到该文件。

## 标题栏
- 启动参数 --title-bar-style=custom 自绘三键。

## 构建入口
- build.sh --skip-extract --no-install 快速重建 deb。产物 workbuddy_<version>-<rev>_amd64.deb（根目录）。

## 环境网络限制（2026-09-01 实测）
- 本机 github.com 主域(20.205.243.166:443)被墙超时；api.github.com(20.205.243.168)可达。
- git push/clone 走 github.com 主域故失败，需经 HTTP/SOCKS 代理或 SSH 方可推送。
- 本机无常见代理端口(7890/1080/8080/8888/3128)监听。
- 曾尝试将 github.com 强制解析到 20.205.243.168（api 的 IP），TLS 握手被对端重置，无效。
