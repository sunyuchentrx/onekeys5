# onekeys5

Debian/Ubuntu 一键安装 SOCKS5 脚本，基于 `dante-server`，支持用户名密码认证。

## 一行命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/sunyuchentrx/onekeys5/main/install_s5.sh | sudo bash -s -- --port 1080 --user myuser --password 'mypassword'
```

如果服务器没有 `curl`，可以用：

```bash
wget -qO- https://raw.githubusercontent.com/sunyuchentrx/onekeys5/main/install_s5.sh | sudo bash -s -- --port 1080 --user myuser --password 'mypassword'
```

执行完成后脚本会直接输出：

- Host
- Port
- User
- Password
- SOCKS5 测试命令

## 参数说明

- `--port`：SOCKS5 监听端口
- `--user`：认证用户名
- `--password`：认证密码

## 本地执行

如果你想先下载再执行：

```bash
chmod +x install_s5.sh
sudo ./install_s5.sh --port 1080 --user myuser --password 'mypassword'
```

## 测试命令

安装完成后可用下面的方式验证：

```bash
curl --proxy socks5h://myuser:mypassword@你的服务器IP:1080 https://api.ipify.org
```
