# Pawday 管理员 Web

Vue 3 + TypeScript 实体工程，使用仓库共享生成 API client 和工作台 shell。

从仓库根目录执行：

```sh
pnpm install --frozen-lockfile
pnpm dev:admin
```

访问 `http://127.0.0.1:5174`；`/api` 由开发代理转发到后端 `127.0.0.1:8080`。后端先运行根目录本地启动脚本。发布静态构建时配置 SPA history fallback，并将 `/api` 代理到后端以保持同源访问。

管理员登录需要密码与 TOTP；设备注销需要重新输入密码及新的 TOTP。审计页读取真实 API。

令牌只保存在内存，刷新页面须重新登录。完整命令与验收见 [M2.4 工程说明](../docs/M2.4-前端工程说明.md)与 [M2 总验收](../docs/M2-总验收报告.md)。
