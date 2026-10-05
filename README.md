# Pawday M4.4 — 子订单履约

M2.3 实现对象存储抽象、真实本地文件适配器、受控媒体上传、OpenSearch V1 索引与可靠同步/重建/对账、Redis 健康门禁。M2.1 身份和 M2.2 Outbox 能力保留。M2.4 增加共享生成客户端、Vue 商家/管理员工程及 Flutter 消费者工程。

M2.4 PR #2 已合并。M3.1 从合并后的主分支增加宠物分类/品种/过敏原、版本化年龄规则、消费者档案和体重记录、Flutter 宠物页及管理员分类维护页。实现范围及验收边界见 [M3.1 说明](docs/M3.1-宠物分类与档案.md)；M3.1 PR #3 已合并；M3.2 增加标准商品、不可覆盖的来源版本、商家纠错、平台审核和 CSV/XLSX 导入确认，见 [M3.2 说明](docs/M3.2-标准商品与审核.md)。M3.2 PR #4 已合并；M3.3 增加门店报价、上下架、平台冻结和不可覆盖库存 Adjustment，见 [M3.3 说明](docs/M3.3-商家报价与库存.md)。M3.3 PR #5 已合并；M3.4 接通消费者浏览、确定性适配和真实业务搜索投影。M3.4 PR #6 已合并；M4.1 增加购物车、地址、冻结试算及受控配送配置。M4.1 PR #7 已合并；M4.2 增加 Quote 消费、事务订单与库存/券预占、未付款取消及超时释放。M4.2 PR #8 已合并；M4.3 增加开发环境模拟支付、渠道尝试、安全关闭、幂等确认和异常补偿。见 [M4.3 说明](docs/M4.3-模拟支付.md)。当前运行时契约为 [pawday-m4.4.yaml](openapi/pawday-m4.4.yaml)，共享 DTO/client 从此生成。

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

脚本创建独立四服务项目，然后执行 `mvn -B -ntp -Pinfrastructure-it verify`。没有 broker/Redis/OpenSearch 时失败，不能使用 mock 或 skip。普通 `mvn verify` 运行身份/媒体/宠物测试，不等价于完整基础设施验收；`rabbit-it` 保留单独 M2.2 broker 回归。

已有真实服务时使用 [test-existing-infrastructure.ps1](scripts/test-existing-infrastructure.ps1)，传入隔离端口、测试 Rabbit 凭据、原生 rabbitmqctl 或测试容器名称；OpenSearch cluster.name 必须是 `pawday-m23-it`，测试会修改其 Pawday 索引。无需安装系统服务，独立临时 PostgreSQL 由测试自动启动。

## 接口与模型

- [M2.3 机器契约](openapi/pawday-m2.3.yaml)：43 operations / 47 schemas，包含历史身份/投递接口。
- [资源与搜索模型](docs/M2.3-资源与搜索模型.md)：权限、状态、事务、重建与恢复边界。
- [验收报告](docs/M2.3-验收报告.md)：实际门禁与环境限制。
- [M2 检查清单](M2-CHECKLIST.md)。

消费者/商家/管理员使用 `/api/v1/media` 申请一次性凭证后 PUT 原始图片；数据库只保存媒体引用。管理员搜索运维路径 `/api/v1/admin/operations/search`，敏感命令需 action/session reverify + audit + Idempotency-Key。M3 通过 CatalogSearchSource 加入业务事务并发布事件；M3.2 已实现平台标准商品维护和商家纠错页面；M3.3 已接入报价与库存管理；M3.4 已接通消费者商品查询、确定性适配、报价比较和真实业务搜索投影。

真实本地验收使用原生服务替代缺失的 Docker，其中 Redis 为社区 Windows 移植的真实服务；CI 固定官方 Linux Redis 镜像。M2.3 的完整 Compose 已由 GitHub Actions 实际验收通过（运行 37127050020）；本机原生服务证据与 CI Docker 证据分别保留。

## 三端前端

启动命令、身份边界和真实联调门禁见 [M2.4 前端工程说明](docs/M2.4-前端工程说明.md)。商家端 5173，管理端 5174；Flutter 提供五 Tab、手机号登录和安全会话恢复。[M2 基础工程技术总验收](docs/M2-总验收报告.md)已通过：167 项测试、305 个实际 HTTP 响应、5 个远程 Job 全部通过。M2.4 PR #2、M3.1 PR #3 已合并；M3.2 已通过技术验收，PR #4 已合并。M3.3 技术验收通过，PR #5 已合并；见 [M3.3 验收报告](docs/M3.3-验收报告.md)。详见 [M3.2 验收报告](docs/M3.2-验收报告.md)。

M3.4 与 [M3 技术总验收](docs/M3-总验收报告.md)已通过：289 项测试、680 个实际 HTTP 响应验证、5 个 CI Job 全部 success。详见 [M3.4 验收报告](docs/M3.4-验收报告.md)。PR #6 已合并；M4.1 已完成技术验收，M4 交易闭环仍需后续阶段。适配资料未知时返回信息不足，不提供虚构营养判断。

M4.1 已通过 **317 项测试、826 个实际 HTTP 响应验证、5 个真实 CI Job**。见 [实现说明](docs/M4.1-购物车与Pricing-Quote.md)和 [验收报告](docs/M4.1-验收报告.md)。消费者从商品详情选择明确 Offer 加车、登录回跳并试算；管理员通过配送配置页发布规则，必须 RBAC + 密码/TOTP 二次验证。Quote 不创建订单或锁库存。PR #7 已合并，M4.2 已完成。

M4.2 已通过 **339 项测试、1,016 个实际 HTTP 响应验证、5 个真实 CI Job**。见 [实现说明](docs/M4.2-库存预占与订单.md)和 [验收报告](docs/M4.2-验收报告.md)。Flutter 接通确认下单/订单/未付款取消，商家查询获授权子单，管理员配置订单期限；此为 M4.2 历史范围；PR #8 已合并，M4.3 已接通模拟支付。每阶段开发包含可执行 JAR 和启动说明，并保留源码包/验收报告/哈希验证记录，桌面和仓库实施计划同步。

M4.3 已通过 **368 项测试、1,256 个实际 HTTP 响应验证、5 个真实 CI Job**。见 [实现说明](docs/M4.3-模拟支付.md)和 [验收报告](docs/M4.3-验收报告.md)。消费者收银台、商家已付款状态和受控管理员核查已接通；生产环境禁用模拟器。PR #9 已合并，后续推进 M4.4 履约，M4 总验收尚未完成。开发包含 0.4.3 可执行 JAR，Android debug APK 另附；每阶段报告/哈希证据和两份实施计划同步。

M4.4 实现子单分包发货与逐包收货，见 [实现说明](docs/M4.4-子订单履约.md)。真实 CI 验证中，尚未宣告验收通过；每阶段交付包/报告和两份实施计划继续同步。
