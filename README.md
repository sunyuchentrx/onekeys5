# onekeys5

Debian/Ubuntu 一键安装 SOCKS5 脚本，基于 `dante-server`，支持用户名密码认证，并自动注册管理菜单命令 `S5`。

## 一行命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/sunyuchentrx/onekeys5/main/install_s5.sh | sudo bash -s -- --port 1080 --user myuser --password 'mypassword'
```

如果服务器没有 `curl`，可以用：

```bash
wget -qO- https://raw.githubusercontent.com/sunyuchentrx/onekeys5/main/install_s5.sh | sudo bash -s -- --port 1080 --user myuser --password 'mypassword'
```

## 安装后功能

安装完成后脚本会输出：

- Host
- Port
- User
- Password
- SOCKS5 测试命令
- 管理命令 `S5`

输入下面命令可以打开菜单：

```bash
sudo S5
```

## S5 菜单功能

- 启动服务
- 停止服务
- 重启服务
- 查看状态
- 查看日志
- 查看当前配置
- 卸载 S5
- 显示重装命令

## 参数说明

- `--port`：SOCKS5 监听端口
- `--user`：认证用户名
- `--password`：认证密码

## 测试命令

安装完成后可以这样验证：

```bash
curl --proxy socks5h://myuser:mypassword@你的服务器IP:1080 https://api.ipify.org
```
