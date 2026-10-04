---
status: accepted
---
# 身份权限以 PostgreSQL 会话为权威，敏感写入显式事务化

使用服务器设备会话与 256 位 opaque token，库内仅存摘要；每次访问重读主体、角色权限与商户范围。相比长期权限快照 JWT，这增加数据库读取，但让封号、权限撤销和跨域边界立即生效。

身份模块使用 Spring JDBC 和显式事务，替换 Bootstrap 未使用的 JPA starter；角色变更、一次性二次验证消费、审计及幂等结果原子提交。Boot 4 使用 `spring-boot-starter-flyway`；V001 保持不变，V002 扩展身份模型。角色身份域及员工/门店商户归属用组合外键约束。

消费者以 OTP 登录，员工密码 BCrypt，管理员须验证 TOTP，密钥 AES-GCM 加密。正式短信、微信登录及 MFA 恢复由后续适配提供。严格一次性刷新检测旧令牌重放时撤销整会话；相比宽限重试，这加强泄露识别，但要求客户端串行刷新。敏感授权绑定会话/action，成功变更才消费，事务失败回滚；幂等重放仍先检查当前权限。

限流持久化于 PostgreSQL，认证不依赖 Redis 临时可用性。审计触发器拒绝 UPDATE/DELETE/TRUNCATE；数据库所有者仍能改 DDL，正式运维权限由部署流程与运行账号分离。RabbitMQ/Outbox 的 M1 边界保持一致。

基线已核对 [Spring Boot 官方页面](https://spring.io/projects/spring-boot/) 与 4.1.1 Maven 构件。测试用 [Zonky Embedded Postgres](https://github.com/zonkyio/embedded-postgres) 运行真实 PostgreSQL，不能据此推断外部基础设施已整栈验收。
