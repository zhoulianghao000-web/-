# Pawday V1 技术选型 ADR

版本：M1 1.1（整改复验版） · 2026-10-03  
状态：Accepted / 部分实现默认值为 Provisional  
基准：`01-实施计划.md`、`02-三端页面与跳转信息架构.md`、`03-需求覆盖与验收清单.md`、`04-领域模型与数据库设计.md`、`05-订单支付库存状态机.md`、`06-API契约与OpenAPI设计.md`，以及 M1 Grill 已确认决策。

> 本文记录 Pawday V1 在进入 M2 工程基础阶段前的关键技术决策、理由、替代方案、后果和重审条件。ADR 记录“为什么这样选”，不替代领域模型、状态机或 OpenAPI。除明确标记为“实施默认值”的项目外，Accepted 项目均来自已经确认的 M1 决策。

---

## 0. ADR 状态约定

- **Accepted**：M1 已确认，M2 默认必须按此实施；变更需要新增 ADR，而不是无痕覆盖本文。
- **Provisional**：为了让 M2 可启动给出的工程默认值，不改变既有领域/API 契约；在正式实现前可用新的 ADR 替换。
- **Deferred**：V1 暂不决定或不实施。
- **Rejected**：当前阶段明确不采用。

所有 ADR 变更应保留历史版本和变更原因。

---

# ADR-001：V1 采用模块化单体，而不是从第一天拆微服务

**状态：Accepted**

## 背景

Pawday V1 已包含消费者 App、商家 Web、平台管理 Web、多商户商品、库存、订单、支付、售后、结算、会员积分、搜索、AI、附近服务等多个领域。交易正确性优先于基础设施复杂度。

## 决策

V1 后端采用 **模块化单体（Modular Monolith）**：

- 一个主要部署单元可以承载多个领域模块；
- 代码按 Identity、Pet、Merchant、Catalog、Offer/Inventory、Order、Payment、AfterSales、Finance、Promotion、Membership、Points、AI、Search、Risk、Audit 等边界拆分；
- 模块之间通过明确服务接口、领域事件和受控数据访问交互；
- 不允许为了“现在方便”跨模块任意直接修改彼此核心表；
- 高并发或边界清晰后，可通过后续 ADR 将特定模块拆成独立服务。

## 不采用

- 一开始拆几十个微服务；
- 每个页面对应一个服务；
- 以“未来可能扩容”为理由提前引入大规模服务治理。

## 理由

1. V1 最大风险在交易/库存/退款/结算一致性，不在服务数量。
2. 多模块需要清晰边界，但不需要立即承担分布式事务、服务发现、链路复杂度和多仓库治理成本。
3. 模块化单体能保留未来拆分空间，同时让核心交易使用本地数据库事务完成。

## 后果

- 必须真正做模块边界，而不是“一个大包里随便互调”。
- M2 需要建立模块依赖规则和测试。
- 后续拆服务时以领域边界和负载事实为依据。

## 重审条件

- 某模块具有明显独立扩缩容需求；
- 发布节奏相互阻塞；
- 数据隔离/合规要求迫使独立部署；
- 单体构建或运行边界已经成为可测量瓶颈。

---

# ADR-002：核心后端使用 Java + Spring Boot

**状态：Accepted**

## 决策

Pawday V1 核心交易后端使用 **Java + Spring Boot**。

## 主要职责

Java 服务负责：

- 身份与权限；
- 商品、SKU、Offer、库存；
- 购物车、试算、优惠；
- 总订单/子订单；
- 支付与退款适配；
- 售后与结算账本；
- 会员积分；
- 商家/平台后台 API；
- AI 工具调用的业务安全边界；
- Outbox 与异步任务编排。

## 不采用

- Node.js/NestJS 作为核心交易主后端；
- Python/FastAPI 作为全部交易系统主后端；
- Go 作为 V1 主交易栈。

这些技术未来仍可用于独立工具或服务，但不能形成第二套交易事实源。

## 理由

Pawday 的关键复杂度是事务、权限、状态机、审计、账本和长期维护。Java/Spring 适合作为稳定的强类型交易底座，并能与 PostgreSQL、Redis、RabbitMQ、OpenAPI 及成熟测试体系结合。

## 后果

- M2 统一 Java 工程规范、异常模型、事务边界、DTO 和模块依赖。
- AI 模型调用仍由服务端控制；即使未来增加 Python AI 服务，也不能绕过 Java 业务规则直接修改订单/库存/宠物档案。

---

# ADR-003：PostgreSQL 是核心关系数据库与最终事实源

**状态：Accepted**

## 决策

核心业务数据库使用 **PostgreSQL**。

以下事实必须以 PostgreSQL 为权威来源：

- 用户/宠物归属；
- 标准商品与版本；
- 商家 Offer；
- 库存余额与预占；
- 订单/子订单/订单项快照；
- 支付/退款业务单；
- 售后；
- 佣金/账本/结算；
- 会员与积分账本；
- 审计和 Outbox。

## 规则

- 核心账务字段不使用浮点数。
- 关系完整性、唯一键和事务约束尽可能在 DB 层保留最后一道防线。
- JSON/JSONB 可用于扩展元数据，但不能把关键订单模型退化为无结构文档。
- 历史订单保留快照/版本，不能读取当前 Offer 回填过去事实。

## 明确不采用

**订单绝不能以 MongoDB/松散生产文档作为核心交易模型。**

MongoDB 或其他文档数据库未来若使用，只能承担明确的非核心场景，并通过单独 ADR 决定。

---

# ADR-004：V1 金额暂用整数分，并封装统一 Money 类型

**状态：Accepted（允许未来通过 ADR 重审）**

## 决策

V1 金额在 API 和核心存储中暂定使用 **整数分（fen）**：

- `¥19.99 -> 1999`；
- 数据库使用 `BIGINT`；
- OpenAPI 金额字段统一 `_fen`；
- 业务代码不得直接散落裸 `long` 做金额运算，必须通过统一 `Money` 值对象/工具处理。

## 理由

- 避免浮点误差；
- 优惠分摊、退款和账本都需要确定性舍入；
- 与 V1 单币种人民币场景匹配。

## 重要限制

该决策是“V1 暂定”。未来如需多币种、小数币种或更通用 decimal 表示，必须：

1. 新增 ADR；
2. 修改统一 Money 类型；
3. 给出数据库/API 兼容和迁移计划；
4. 禁止各模块自行改字段类型。

---

# ADR-005：Redis 仅作辅助基础设施，不是交易最终事实源

**状态：Accepted**

## 决策

Redis 用于：

- 缓存；
- 登录会话辅助；
- 验证码；
- 限流；
- 短期幂等/防抖辅助；
- 必要时的分布式协调/锁；
- 可再生的短期数据。

但 Redis **不是**以下数据的最终事实源：

- 订单状态；
- 支付成功；
- 库存成交事实；
- 退款；
- 结算账本；
- 积分正式账本。

## 理由

交易事实需要关系约束、持久历史和可审计事务。Redis 可提升性能和协调，但不能替代 PostgreSQL 的权威状态。

## 后果

Redis 丢失或短期不可用不能导致历史订单/账本消失；系统需要具备从 DB 恢复可再生缓存的能力。

---

# ADR-006：异步消息使用 RabbitMQ，可靠发布采用 Transactional Outbox

**状态：Accepted**

## 决策

- V1 消息中间件：**RabbitMQ**；
- 核心事务内先提交业务事实与 `outbox_event`；
- 独立发布器将 Outbox 事件投递 RabbitMQ；
- 消费者必须幂等；
- 有限次数指数退避重试；
- 超过阈值进入死信/异常队列；
- 支持人工重放。

## 适用事件

例如：

- `OrderPaid`
- `InventoryReservationExpired`
- `SuborderShipped`
- `RefundSucceeded`
- `SettlementAdjusted`
- `PointsGranted`
- `CatalogPublished`
- `SearchReindexRequested`
- `NotificationRequested`

## 为什么不是“事务后直接发 MQ”

数据库提交成功后，进程可能在发送 MQ 前崩溃。如果没有 Outbox，会形成“钱已经收到了，但支付成功事件永久丢失”的窗口。

## 为什么 V1 不选 Kafka

V1 目前更需要可靠任务/业务消息、重试和队列语义，而不是首先构建高吞吐流式数据平台。未来若分析/事件流规模需要 Kafka，另开 ADR。

---

# ADR-007：搜索采用专用搜索服务；AI 只负责语义解析，不替代搜索索引

**状态：Accepted（具体发行版 Provisional）**

## 决策

Pawday V1 使用 **Elasticsearch / OpenSearch 类专用搜索服务**，并与 DeepSeek 自然语言解析组合：

```text
自然语言输入
  -> AI 解析为结构化条件
  -> 搜索服务执行检索/过滤/排序
  -> 业务服务校验在售状态与权限
  -> 返回结果
```

商品/Offer 更新通过可靠事件增量同步索引，同时支持：

- 全量重建；
- 索引与 PostgreSQL 对账；
- 重建期间状态可观察。

## 不采用

- 仅依赖 SQL `LIKE` 作为完整搜索方案；
- 让 DeepSeek 凭模型记忆返回商品；
- 每次搜索跨大量表实时拼复杂全文检索。

## Provisional 实施默认值

M2 若没有额外基础设施限制，默认优先评估 **OpenSearch**；如果团队/托管环境明显更适配 Elasticsearch，可在不改变 API/领域契约的前提下通过小型 ADR 切换。

## 重审条件

- 托管云服务能力；
- 中文分词与同义词效果；
- 运维成本；
- 许可证/商业约束；
- 真实容量测试。

---

# ADR-008：外部 HTTP 契约采用 REST + OpenAPI 3.1

**状态：Accepted**

## 决策

三端与统一后端使用 REST HTTP API，并以 **OpenAPI 3.1** 作为可测试契约。

路径逻辑分区：

```text
/api/v1/public
/api/v1/consumer
/api/v1/merchant
/api/v1/admin
/api/v1/webhooks
/api/v1/internal
```

## 关键约定

- 状态迁移使用明确命令接口，不允许通用 `PATCH status=...`；
- 关键写接口使用 `Idempotency-Key`；
- 可编辑资源使用 version / `If-Match` 乐观锁；
- 时间使用 RFC3339/ISO-8601；
- 金额 V1 使用 `_fen`；
- 统一错误结构；
- 分页、排序、筛选有统一规范；
- OpenAPI 进入 CI 校验。

## 不采用

V1 不用 GraphQL 替代核心交易 API，也不直接把内部 RPC 暴露给 App/Web。

---

# ADR-009：消费者 App 使用 Flutter，一套业务代码面向 Android/iOS

**状态：Accepted**

## 决策

消费者 Pawday App 使用 **Flutter**，正式目标覆盖 Android 与 iOS。

允许：

- 内测阶段先验证单平台；
- 正式产品架构保持双端；
- 平台特定支付、微信、高德、推送能力通过插件/原生桥接封装。

## 理由

- Pawday 页面和交易流程高度一致；
- 减少双原生项目重复业务实现；
- 有利于保持订单/AI/宠物/会员等行为一致。

## 不采用

- V1 Android/iOS 两套独立纯原生业务工程；
- React Native 作为当前主 App 技术。

## Provisional：Flutter 状态管理与路由

此前尚未单独确认具体库。为 M2 可启动，默认建议：

- 状态管理：**Riverpod**；
- 路由：**go_router**；
- 网络层：基于 OpenAPI 生成 DTO/Client 后再封装业务 Repository；
- 页面不得直接依赖支付/AI 第三方 SDK 的业务状态。

这些属于 **Provisional 实施默认值**，可在 M2 初始化前通过小型 ADR 更换；更换不得改变 06 API 契约。

---

# ADR-010：商家 Web 与平台管理 Web 使用 Vue 3 + TypeScript

**状态：Accepted**

## 决策

- 商家 Web：Vue 3 + TypeScript；
- 平台管理 Web：Vue 3 + TypeScript；
- 两者为独立应用，但共享设计系统、通用组件和 API 基础库。

## 建议共享能力

- 表格/分页/筛选；
- 表单和校验；
- 金额展示；
- 日期时区；
- 上传；
- 审核时间线；
- 权限指令仅作 UI 辅助；
- OpenAPI 生成类型；
- 错误/请求 ID 展示。

## 安全原则

前端路由和按钮权限不是安全边界；服务端必须再次校验 merchant/store scope 或 admin RBAC。

---

# ADR-011：对象存储 + CDN 管理媒体文件

**状态：Accepted**

## 决策

商品图、门店图、文章媒体、评价图片/视频、客服图片采用：

**对象存储 + CDN**。

业务数据库只保存：

- asset id；
- 对象 key；
- MIME/type；
- 尺寸/大小；
- 安全扫描/状态；
- 业务引用。

客户端通过受控短期上传凭证上传，不把长期存储密钥写进 App/Web。

## 不采用

- 图片二进制塞 PostgreSQL 核心表；
- 单服务器本地硬盘作为生产媒体主存储；
- 无治理的第三方图床作为关键商品资源源。

---

# ADR-012：认证、RBAC 与数据范围必须由服务端执行

**状态：Accepted**

## 决策

三个主体体系分开处理：

1. 消费者；
2. 商家员工；
3. 平台员工。

服务端执行：

- authentication；
- role permission；
- merchant/store data scope；
- owner/subject ownership；
- high-risk reverify；
- device/session revoke；
- audit。

商家员工多角色：

- 功能权限取并集；
- 数据范围仍受商户/门店限制；
- 敏感权限可附加二次验证/审批。

## 禁止

- 仅靠前端隐藏按钮；
- merchant id 由前端传入后无归属校验；
- 客服角色拥有财务/佣金写权限。

---

# ADR-013：DeepSeek 是解释/交互层；业务规则和数据事实留在 Pawday 服务端

**状态：Accepted**

## 决策

DeepSeek 用于：

- 选粮对话；
- 商品比较解释；
- 配料说明；
- 自然语言条件解析；
- 宠物档案修改建议；
- 未来客服辅助。

但确定性业务链固定为：

```text
宠物档案
 -> 确定性规则
 -> 在售 SKU 检索
 -> 推荐排序
 -> DeepSeek 解释
```

## 强约束

- 过敏/禁忌硬规则不由模型自由判断；
- 商品、库存、价格来自实时业务服务；
- AI 推荐只引用当前可验证的在售 SKU；
- AI 工具调用必须返回真实业务结果；
- AI 不直接付款；
- AI 修改宠物档案必须先生成 proposal，由用户确认并做版本校验；
- 医疗场景不提供诊断、治疗和用药，转附近兽医/医院入口。

## 部署原则

DeepSeek API 密钥只在服务端。客户端不得直接调用模型供应商。

## 模型可替换性

AI Provider 应做适配层，业务工具协议和结构化上下文不与单一模型厂商 SDK 深度耦合。未来替换模型时，不应重写订单/商品系统。

---

# ADR-014：支付采用服务端 Payment Adapter；开发沙箱/模拟与生产真实通道严格分离

**状态：Accepted**

## 决策

V1 统一收银台目标支持：

- 微信支付；
- 支付宝。

后端提供 `PaymentProvider`/Adapter 抽象，业务域不直接散落第三方 SDK 调用。

开发/内测：

- mock / sandbox；
- 明确显示测试环境；
- 可模拟成功、失败、处理中、晚回调、退款失败。

生产上线前：

- 切换真实微信/支付宝；
- 服务端验签；
- webhook 幂等；
- 主动查询补偿；
- 对账；
- 合规分账/结算方案。

## 禁止

- 客户端返回“支付成功”直接改订单；
- Pawday 私下归集资金后人工给商家转账作为正式结算架构；
- 模拟支付通过即宣称生产支付验收完成。

---

# ADR-015：库存一致性依赖 PostgreSQL 事务；Redis 不能单独决定是否售出

**状态：Accepted**

## 决策

订单提交时：

1. 服务端对所选 Offer 做库存预占；
2. 任一 Offer 失败，则整次跨店提交失败；
3. 不静默换卖家；
4. 预占期限后台可配置，V1 默认 15 分钟；
5. 支付成功幂等确认后消费 Reservation 并正式扣减；
6. 超时释放；
7. 重复支付回调不得重复扣减。

并发正确性必须由 PostgreSQL 条件更新、行锁/版本控制等服务端事务机制实现。

---

# ADR-016：财务/积分正式账本采用 append-only + adjustment

**状态：Accepted**

## 决策

以下历史记录不得静默覆盖：

- merchant ledger；
- settlement adjustment；
- points ledger；
- refund result；
- commission allocation；
- audit record。

纠错必须创建：

- adjustment；
- reversal；
- compensating entry。

并记录关联原单据、原因、操作者和时间。

## 典型规则

- 已结算后退款：不改旧结算单，创建负向调整，从后续可结算金额抵扣，必要时形成应收余额；
- 购买积分已消费后发生退款：按规则回退，允许积分余额为负，未来积分先抵消负值。

---

# ADR-017：优惠在下单时确定性分摊并固化快照

**状态：Accepted**

## 决策

正式定价版本 `PRICING_V1_1` 与尾差 `LARGEST_REMAINDER_V1` 以05第8节为准：会员/基础价→商家商品活动→商家券→平台商品活动→平台券→运费→运费补贴/券。商家券每商家1张、平台商品券含新人券整单1张、运费券整单1张；商品行可0分，总订单至少1分。按当前阶段余额使用整数最大余数法，Quote稳定allocation_key复制到订单。

订单创建时保存：

- 优惠规则版本；
- 原始金额；
- 每个订单项/运费的优惠分摊；
- 实付金额。

部分退款：

- 原则上按该项原实付金额退款；
- 不在售后阶段重新计算并追缴历史满减门槛；
- 整个优惠范围取消时，优惠券是否返还按订单时规则快照执行；
- 部分退款通常不返券。

---

# ADR-018：搜索/推荐与广告必须服从宠物安全适配规则

**状态：Accepted**

## 决策

排序可考虑：

- 相关性；
- 商品质量；
- 销量；
- 价格；
- 商家服务；
- 用户行为；
- 当前宠物适配。

但处理顺序必须满足：

```text
硬冲突/数据完整性规则
 -> 候选集
 -> 商业/个性化排序
 -> 广告位插入（显式标记）
```

**广告可以买曝光，不能买“适合这只宠物”的结论。**

---

# ADR-019：高德用于地点/导航交接，Pawday 不自建导航引擎

**状态：Accepted**

## 决策

Pawday 附近服务负责：

- 宠物店；
- 宠物医院；
- 美容洗护；
- 寄养；
- 地址/电话/营业信息；
- 门店认领和认证状态。

用户点击导航后，将目的地交给 **高德地图**。

## 医疗边界

附近宠物医院只提供地点和基础信息，不做：

- 医疗诊断；
- 治疗建议；
- 医院治疗能力排名；
- 因医疗问题自动推荐某医院治疗方案。

---

# ADR-020：环境、配置与密钥严格分层

**状态：Accepted**

## 环境

至少区分：

- local/dev；
- test/CI；
- sandbox/staging；
- production。

## 规则

- 第三方密钥不进入 Flutter/Web bundle；
- 正式支付/分账凭证不得用于开发环境；
- 商业运营参数进入版本化配置，不硬编码客户端；
- 配置发布需要审计；
- 敏感日志脱敏。

## 运营参数示例

- 库存锁定期限（默认 15 分钟）；
- 售后/结算缓冲（默认 7 天）；
- 会员月/年价格；
- AI 额度；
- 佣金策略；
- 结算周期；
- 优惠/运费策略；
- 签到积分；
- 首发城市。

---

# ADR-021：审计日志为安全与财务一等能力

**状态：Accepted**

## 决策

关键操作审计至少记录：

- actor / actor role；
- 时间；
- 对象类型和 ID；
- action；
- 前值/后值或结构化 diff；
- request/correlation id；
- 来源 IP/设备上下文（按安全策略）；
- 关联订单/退款/结算/商品/AI版本等业务 ID。

敏感字段必须脱敏，不记录密码、支付私钥或模型 API key 原文。

普通业务操作员不能修改审计历史。

---

# ADR-022：媒体、备份与恢复属于基础设施，不由后台页面“代替实现”

**状态：Accepted**

## 决策

- 媒体：对象存储 + CDN；
- PostgreSQL：自动备份 + 多副本/可靠副本策略；
- 必须执行恢复演练；
- 搜索索引可重建，不能成为唯一商品事实源；
- Redis/RabbitMQ 故障需要有恢复/降级方案；
- 平台后台的“备份状态页”只展示真实基础设施状态，不能代替备份本身。

生产准入要求恢复演练成功并保留证据。

---

# ADR-023：M2 的 CI/CD 与工程质量门禁

**状态：Provisional**

此前已确定 M2 必须有 CI 和可回滚迁移，但尚未指定具体 CI 供应商。默认工程要求如下：

## 必须门禁

1. Java 编译、单元测试；
2. 模块边界测试；
3. 数据库 migration 校验；
4. OpenAPI lint / breaking-change 检查；
5. Web TypeScript 构建与测试；
6. Flutter analyze/test；
7. 依赖漏洞基础扫描；
8. 密钥泄露扫描；
9. 容器/应用构建可重复；
10. M2 种子数据必须显式标记为 demo/test。

CI 平台（GitHub Actions、GitLab CI 或其他）不在 M1 强行锁死，可依据实际代码仓库环境决定。

---

# ADR-024：数据库迁移必须版本化且可验证回滚/前向修复

**状态：Provisional / M2 必须落实**

## 决策原则

- 所有 schema 变化必须进入 migration；
- 不允许生产人工临时改表后不留迁移；
- 关键迁移要有 dry-run/备份与恢复方案；
- 对不可安全回滚的数据迁移采用 forward-fix，而不是虚假承诺“一键 rollback”；
- 应用与数据库版本兼容策略写入发布流程。

具体 Java migration 工具（Flyway/Liquibase）在 M2 初始化时用小型 ADR 选择。

---

# ADR-025：可观测性技术栈在 M2 选择，但指标语义现在固定

**状态：Provisional**

具体日志/指标/链路工具尚未确认，不在 M1 假装已经选定供应商。

M2 至少必须能观测：

- API latency/error rate；
- 数据库连接/慢查询；
- Redis/RabbitMQ 健康；
- Outbox backlog；
- DLQ 数量；
- 支付 webhook 失败/重放；
- 库存预占超时；
- 退款重试；
- 结算异常；
- 搜索索引延迟；
- AI 请求失败、额度、工具调用失败；
- 对象存储失败；
- 登录/风控异常。

具体 OpenTelemetry / Prometheus / Grafana / 托管云监控组合可在 M2 根据部署环境决定。

---

## 26. 已明确拒绝或暂缓的架构方向

| 方向 | V1 决定 |
|---|---|
| 从第一天全微服务 | Rejected |
| MongoDB 作为订单核心模型 | Rejected |
| Redis 作为库存/支付最终事实源 | Rejected |
| AI 直接决定过敏安全 | Rejected |
| AI 凭模型记忆推荐可购买 SKU | Rejected |
| 客户端直接持有 DeepSeek/支付长期密钥 | Rejected |
| 客户端返回码直接确认支付 | Rejected |
| 正式账本直接 UPDATE 历史金额 | Rejected |
| 广告改变宠物适配结论 | Rejected |
| V1 自动续费会员 | Deferred |
| V1 自动扣款订粮 | Deferred |
| 商家 App | Deferred |
| 消费者 Web 商城 | Rejected for V1 |
| ERP/WMS 深度同步 | Deferred |
| 完整电子面单 | Deferred / interface reserved |
| 价格历史曲线 | Deferred / data reserved |
| AI 客服自动接待 | Deferred / interface reserved |
| 家庭共享宠物 | Deferred |
| 小游戏 | Rejected，且不预留导航入口 |

---

## 27. M2 工程初始化推荐结构

以下为架构意图，不强制具体 Gradle/Maven 细节。

```text
pawday/
  backend/
    app/
    modules/
      identity/
      pet/
      merchant/
      catalog/
      offer-inventory/
      pricing-promotion/
      order/
      payment/
      fulfillment/
      aftersales/
      finance/
      membership-points/
      review/
      nearby/
      content/
      messaging/
      ai/
      search/
      risk/
      audit-config/
    infrastructure/
      postgres/
      redis/
      rabbitmq/
      outbox/
      object-storage/
      payment-providers/
      ai-provider/
      search-provider/
      amap/
  consumer-app/
    flutter/
  merchant-web/
    vue/
  admin-web/
    vue/
  openapi/
  database/
    migrations/
  docs/
    adr/
```

原则：目录服务于领域边界，不能仅为了“看起来微服务化”把同一事务拆成跨网络调用。

---

## 28. M1 技术选型一致性检查

进入 M2 前，以下必须同时成立：

- [x] 核心交易后端技术已确定为 Java + Spring Boot。
- [x] 核心关系数据库已确定为 PostgreSQL。
- [x] Redis 仅辅助，不替代 DB 交易事实。
- [x] RabbitMQ + Outbox 负责可靠异步事件。
- [x] 搜索采用专用搜索服务，AI 只做结构化语义解析/解释。
- [x] 消费者 App 使用 Flutter。
- [x] 两套后台使用 Vue 3 + TypeScript。
- [x] REST + OpenAPI 3.1 是三端稳定契约。
- [x] 金额 V1 暂为整数分，统一 Money 抽象保留未来迁移空间。
- [x] 支付、退款、库存、账本以服务端事务/幂等为准。
- [x] 支付供应商、DeepSeek、高德密钥不进入客户端。
- [x] AI 无权绕过安全规则、库存、支付或档案确认。
- [x] 生产支付/分账与模拟环境严格区分。
- [x] 媒体使用对象存储 + CDN。
- [x] 权限与数据范围在服务端执行。
- [x] 财务、商品审核、AI 配置和高风险动作可审计。
- [x] 搜索索引可重建，PostgreSQL 保持事实源。
- [x] M2 CI、数据库迁移、可观测性具体工具允许按工程环境补充小型 ADR。

---

## 29. M1 结束后进入 M2 的工程原则

M2 不应该“同时把所有页面做出来”。实施顺序继续遵循纵向可运行切片：

1. 建立仓库与模块化单体骨架；
2. PostgreSQL migration 基础与环境配置；
3. 认证、会话、RBAC、审计；
4. Redis/RabbitMQ/Outbox 基础适配；
5. OpenAPI 契约校验和三端生成类型；
6. 对象存储适配；
7. 搜索服务与索引同步骨架；
8. demo seed 数据；
9. 建立最小身份/商品/Offer 可运行链；
10. 用自动测试证明越权、幂等、迁移和核心基础设施约束成立。

M2 的完成标准仍以 `01-实施计划.md` 为准：**一键启动、迁移可控、种子数据明确为演示、认证/越权测试通过**，而不是页面数量。



# ADR-026：Quote、支付渠道、取消与库存命令统一事实归属

**状态：Accepted · 2026-10-03 · M1整改**

问题：04–06把正式契约写成可选建议，允许不同实现产生相互冲突的交易事实。

决策：Quote持久化PostgreSQL，消费一次；订单一对一引用。Payment是金额与支付意图，Attempt拥有渠道与渠道流水，成功渠道派生，原路退款必须绑定实际收款Attempt。部分取消使用取消单/不可变明细和append-only事件，接受即停止发货，cancelled_qty可重建。商家库存只有delta Adjustment命令，版本/幂等/余额/审计同事务；Offer PATCH不接收库存。

取舍：比Redis临时报价、Payment覆盖channel、只存取消汇总或直接库存SET多出持久化/审计成本，但能重放金额与数量，避免退款期间继续发货、切渠道丢历史和库存覆盖预占。改变这些归属会影响迁移/DTO/对账，故在M1统一，不留M2二选一。

正式细节见04第8–12节、05第8–12节、06第19–23/34节。Coupon与AI quota枚举、负积分兑换禁令、Offer唯一约束、物种生命周期taxonomy和LogisticsProvider均为正式边界；具体物流供应商与物种数值来源须在工程/运营阶段验证，不能虚构。
