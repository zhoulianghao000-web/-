# Pawday M2.4 — 三端前端工程

M2.3 实现对象存储抽象、真实本地文件适配器、受控媒体上传、OpenSearch V1 索引与可靠同步/重建/对账、Redis 健康门禁。M2.1 身份和 M2.2 Outbox 能力保留。M2.4 增加共享生成客户端、Vue 商家/管理员工程及 Flutter 消费者工程。

## 本地启动

需要 Java 21、Docker Compose；交付包带可执行 JAR，也可使用 Maven 3.9+ 构建。

```powershell
./scripts/init-local.ps1
./scripts/start-local.ps1
```

脚本生成被忽略的本地密钥/测试身份，Compose 在 loopback 启动 PostgreSQL 17.9、Redis 8.2.10、RabbitMQ 4.3.6、OpenSearch 3.9.0 并等待健康。开发环境关闭 OpenSearch 安全插件；正式部署另配认证/TLS和云存储 provider。访问令牌、上传凭证、验证码不打印到日志或提交仓库。

## 必须运行的门禁

```powershell
./scripts/test-infrastructure.ps1
```

脚本创建独立四服务项目，然后执行 `mvn -B -ntp -Pinfrastructure-it verify`。没有 broker/Redis/OpenSearch 时失败，不能使用 mock 或 skip。普通 `mvn verify` 只运行身份/媒体测试，不等价于 M2.3 验收；`rabbit-it` 保留单独 M2.2 broker 回归。

已有真实服务时使用 [test-existing-infrastructure.ps1](scripts/test-existing-infrastructure.ps1)，传入隔离端口、测试 Rabbit 凭据、原生 rabbitmqctl 或测试容器名称；OpenSearch cluster.name 必须是 `pawday-m23-it`，测试会修改其 Pawday 索引。无需安装系统服务，独立临时 PostgreSQL 由测试自动启动。

## 接口与模型

- [M2.3 机器契约](openapi/pawday-m2.3.yaml)：43 operations / 47 schemas，包含历史身份/投递接口。
- [资源与搜索模型](docs/M2.3-资源与搜索模型.md)：权限、状态、事务、重建与恢复边界。
- [验收报告](docs/M2.3-验收报告.md)：实际门禁与环境限制。
- [M2 检查清单](M2-CHECKLIST.md)。

消费者/商家/管理员使用 `/api/v1/media` 申请一次性凭证后 PUT 原始图片；数据库只保存媒体引用。管理员搜索运维路径 `/api/v1/admin/operations/search`，敏感命令需 action/session reverify + audit + Idempotency-Key。M3 通过 CatalogSearchSource 加入业务事务并发布事件；当前没有商品/推荐业务页面或 CRUD 功能。

真实本地验收使用原生服务替代缺失的 Docker，其中 Redis 为社区 Windows 移植的真实服务；CI 固定官方 Linux Redis 镜像。M2.3 的完整 Compose 已由 GitHub Actions 实际验收通过（运行 37127050020）；本机原生服务证据与 CI Docker 证据分别保留。

## 三端前端

启动命令、身份边界和真实联调门禁见 [M2.4 前端工程说明](docs/M2.4-前端工程说明.md)。商家端 5173，管理端 5174；Flutter 提供五 Tab、手机号登录和安全会话恢复。M2.4 完成后先执行 M2 总验收，通过后才进入 M3。
