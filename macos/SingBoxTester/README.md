# SingBoxTester

用于测试当前源码构建的 sing-box（包含 REALITY 的 `X25519MLKEM768` 支持）。

## 构建

在仓库根目录执行：

```bash
./script/build_and_run.sh
```

生成的 app 位于 `dist/SingBoxTester.app`。

## 使用

1. 选择或拖入 sing-box JSON 配置。
2. 点击“校验”检查配置。
3. 点击“启动”，在日志区域查看连接结果。
4. 配置包含 TUN 时，点击“管理员终端启动”，在 Terminal 输入管理员密码。

普通启动模式没有 root 权限。REALITY 客户端配置需要启用 `tls.utls`，推荐使用 `chrome` 指纹。
