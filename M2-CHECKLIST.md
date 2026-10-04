# Pawday M2 检查清单

## M2.1 / M2.2

- [x] 三身份域、RBAC、二次验证、审计与身份负向回归
- [x] 事务 Outbox、publisher confirm、Inbox 幂等、Retry/DLQ/受控重放
- [x] 异步 OTP 与稳定外部幂等键；真实 RabbitMQ 停机恢复门禁
- [ ] 正式短信供应商、员工开户及 MFA 恢复生产适配

## M2.3

- [x] ObjectStorageProvider 抽象和真实本地适配器上传/读取/删除/元数据
- [x] media_asset 引用表与 owner/realm/scope/store/session 边界
- [x] 一次性受控凭证、类型/长度/hash/魔数/图片尺寸/期限校验
- [x] 文件与数据库分阶段恢复、删除重试、失效 worker fencing、暂存清理
- [x] 真实 OpenSearch 集群健康检查及重复索引/版本/别名初始化
- [x] V1 strict mapping，SKU 稳定 ID、事实 revision、删除墓碑
- [x] 三商品变化事件 + SearchReindexRequested 接入 M2.2 Outbox/Rabbit/Inbox
- [x] 搜索不可用时事实可提交，恢复后同步，重复消费与旧版本无错误结果
- [x] 全量新索引重建、完整事实校验、原子双别名切换、失败保留旧索引
- [x] 对账、失败项重试、受 RBAC/reverify/audit/idempotency 保护的运维命令
- [x] 真实 Redis 读写/TTL/健康及不可用恢复
- [x] PostgreSQL / RabbitMQ / Redis / OpenSearch 同时健康的实际证据
- [x] CI 配置固定四服务与 storage/search/infrastructure-it 硬门禁
- [x] 远程 GitHub Actions 实际执行（M2.3 运行 37127050020 通过）
- [x] Docker Compose 引擎实跑（GitHub Actions 官方 Linux 四服务）
- [ ] 正式云存储适配器与商品/评价/文章发布后的资源读取策略

## M2.4 / 总门禁

- [x] Merchant/Admin Vue 工程：真实身份、门店 scope、RBAC、MFA/reverify/审计
- [x] 共享 TypeScript API 客户端：生成 DTO、错误、refresh、request ID、幂等/冲突
- [x] Flutter 五 Tab：游客、手机号登录、session/refresh、returnTo、current pet context
- [x] 后端、真实数据库迁移与全部基础设施门禁
- [x] OpenAPI lint/bundle 与实际响应验证
- [x] M2 基础工程技术总验收通过（[总验收报告](docs/M2-总验收报告.md)）；M2.4 PR 待评审合并

- [x] 本地 Web lint/typecheck/test/build 与 Chromium 页面回归
- [x] 本地 Flutter analyze/test/Web release build
- [x] TypeScript/Dart OpenAPI 生成一致性检查
- [x] M2.4 远程 Web/Flutter/APK/真实前后端联调全部执行通过（167 tests、305 实际响应）
