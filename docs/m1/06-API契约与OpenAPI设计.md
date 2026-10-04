# Pawday V1 API 契约与 OpenAPI 设计

版本：M1 1.1（整改复验版） · 2026-10-03  
基准：`01-实施计划.md`、`02-三端页面与跳转信息架构.md`、`03-需求覆盖与验收清单.md`、`04-领域模型与数据库设计.md`、`05-订单支付库存状态机.md`，以及 M1 Grill 已确认决策。

> 本文定义 Pawday V1 的 HTTP API 契约、认证授权、幂等、版本冲突、分页、错误码、状态迁移动作、支付回调、AI 工具接口和 OpenAPI 组织方式。它是消费者 Flutter App、商家 Web、平台管理 Web 与统一后端之间的稳定契约，不代表接口已经实现。

---

## 1. 设计目标

Pawday API 的首要目标不是“REST 看起来整齐”，而是保证跨端行为、交易状态机、权限边界与财务事实一致。

核心原则：

1. **REST + OpenAPI 3.1** 作为 V1 对外 HTTP 契约。
2. **资源查询与状态迁移动作分离**：查询使用资源 URL；不可逆状态迁移使用明确命令接口，例如 `/cancel`、`/ship`、`/confirm-receipt`，不暴露普通 `PATCH status=...`。
3. **所有关键写接口幂等**：订单、支付意图、售后、确认收货、退款、会员购买、积分兑换等使用 `Idempotency-Key` 或业务唯一键。
4. **服务端是权限与状态机最终边界**；前端隐藏按钮不构成安全控制。
5. **金额 V1 使用整数分**，字段统一以 `_fen` 结尾；客户端不得提交可信“应付金额”作为结算依据。
6. **时间统一 RFC3339/ISO-8601 带时区**，后端数据库统一 `TIMESTAMPTZ`。
7. **异步状态可恢复查询**：支付、退款、结算、导入、搜索重建均允许 `PROCESSING`，客户端必须通过查询状态恢复，而非依赖一次请求连接。
8. **乐观锁用于可编辑资源**：关键编辑返回 `version`，更新使用 `If-Match` 或请求体 `expected_version`。
9. **API 不自动替用户做业务决定**：库存不足不换商家；AI 推荐失效不偷偷替换 Offer；账号冲突不自动合并。
10. **所有响应带可追踪请求 ID**，关键业务返回 `correlation_id`。
11. **敏感信息最小化**：商家仅获得履约必要消费者数据；AI 只获得当前任务必要数据。
12. **OpenAPI 是可测试契约**：M2 工程需要基于契约生成/校验客户端和服务端 DTO，避免三端各自猜字段。

---

## 2. API 分区与基础 URL

V1 建议统一 API Gateway/后端入口，逻辑分区如下：

```text
/api/v1/public/...       游客公开读取
/api/v1/consumer/...     消费者账户能力
/api/v1/merchant/...     商家 Web
/api/v1/admin/...        平台管理 Web
/api/v1/webhooks/...     第三方服务回调
/api/v1/internal/...     内部服务/任务，不对客户端开放
```

生产环境示例：

```text
https://api.pawday.cn/api/v1
```

约束：

- `public` 与 `consumer` 可以在同一后端应用内，但 OpenAPI tag 和权限策略必须分开。
- `merchant` 与 `admin` 不复用消费者 token。
- `/internal` 禁止暴露到公网客户端路由。
- 支付、DeepSeek、高德等第三方密钥只存在服务端。

---

## 3. OpenAPI 文档组织

建议保留一个根规范并按领域拆文件：

```text
openapi/
  pawday-v1.yaml
  paths/
    public.yaml
    consumer-auth.yaml
    consumer-pets.yaml
    consumer-catalog.yaml
    consumer-cart-checkout.yaml
    consumer-orders.yaml
    consumer-aftersales.yaml
    consumer-membership-points.yaml
    consumer-ai.yaml
    consumer-nearby.yaml
    consumer-messaging.yaml
    merchant.yaml
    admin.yaml
    webhooks.yaml
  schemas/
    common.yaml
    identity.yaml
    pet.yaml
    catalog.yaml
    order.yaml
    payment.yaml
    aftersales.yaml
    finance.yaml
    membership.yaml
    ai.yaml
```

OpenAPI 根版本：

```yaml
openapi: 3.1.0
info:
  title: Pawday V1 API
  version: 1.0.0
servers:
  - url: https://api.pawday.cn/api/v1
```

---

## 4. 通用 HTTP 约定

### 4.1 Content-Type

请求/响应默认：

```http
Content-Type: application/json
Accept: application/json
```

媒体上传走受控上传凭证，不通过业务 API 直接传超大二进制。

### 4.2 请求追踪头

服务端生成：

```http
X-Request-Id: 01H...
X-Correlation-Id: 01H...
```

客户端可传：

```http
X-Correlation-Id: <uuid-or-ulid>
```

若无则服务端创建。

### 4.3 幂等头

关键写接口：

```http
Idempotency-Key: 4a0a2c4f-...
```

规则：

- 同一主体 + 同一接口语义 + 同一 `Idempotency-Key` 重试，返回第一次成立的结果。
- 同一 Key 但关键请求参数不同，返回 `409 IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD`。
- 服务端保存请求哈希、结果资源 ID、状态码、创建时间与过期策略。
- 客户端不得因为超时生成新 Key 重复下单；应先用原 Key 重试或查询。

### 4.4 乐观锁

返回资源示例：

```json
{
  "id": "01H...",
  "version": 7
}
```

更新方式优先：

```http
If-Match: "7"
```

版本冲突：

```http
409 CONCURRENT_MODIFICATION
```

对 AI 宠物档案修改建议，必须带 proposal 中记录的 pet version；冲突后重新展示 diff。

---

## 5. 认证与 Token 模型

### 5.1 消费者

登录方式：

- 手机号验证码；
- 微信登录/绑定到手机号主账号。

建议 token：

- 短期 Access Token；
- 可撤销 Refresh Token；
- 会话绑定 `session_id` / device；
- 异常登录可撤销单设备或全部其他会话。

### 5.2 商家

商家 Web 使用独立身份体系：

- 账号/手机号登录；
- 高风险动作二次验证；
- token 中包含 `merchant_id`、staff id、角色快照引用，但服务端每次仍做权限与数据范围校验。

### 5.3 平台管理员

平台管理员使用更高等级保护：

- MFA/二次验证；
- 设备/IP 风险；
- 权限/RBAC；
- 高风险动作 reverify；
- 完整审计。

### 5.4 认证 Header

```http
Authorization: Bearer <access_token>
```

---

## 6. 授权与数据作用域

### 6.1 消费者资源归属

消费者只能访问自己名下：

- 宠物；
- 地址；
- 购物车；
- 订单；
- 售后；
- 会员/积分；
- AI 对话；
- 客服会话。

对于猜测其他资源 ID：统一返回 404 或策略化 403，避免泄露资源存在性。

### 6.2 商家作用域

商家员工权限由：

```text
功能权限并集
∩ merchant scope
∩ store scope
∩ 敏感动作额外策略
```

共同决定。

商家 API 永远从 token/会话确定 merchant，不接受客户端传任意 `merchant_id` 来切换其他商家。

### 6.3 平台 RBAC

平台 API 使用 permission code，例如：

```text
merchant.review.read
merchant.review.decide
catalog.standard.write
finance.commission.write
finance.ledger.adjust
ai.prompt.publish
access.role.write
```

高风险权限除 RBAC 外可以要求近期再验证。

---

## 7. 通用响应模型

### 7.1 单资源成功

```json
{
  "data": {
    "id": "01H...",
    "version": 3
  },
  "meta": {
    "request_id": "01HREQ...",
    "correlation_id": "01HCOR..."
  }
}
```

### 7.2 列表成功

```json
{
  "data": [
    { "id": "01H..." }
  ],
  "page": {
    "next_cursor": "eyJ...",
    "has_more": true
  },
  "meta": {
    "request_id": "01HREQ..."
  }
}
```

### 7.3 异步任务成功接收

```http
202 Accepted
```

```json
{
  "data": {
    "job_id": "01HJOB...",
    "status": "PROCESSING",
    "status_url": "/api/v1/admin/catalog-imports/01HJOB..."
  }
}
```

---

## 8. 错误响应模型

统一：

```json
{
  "error": {
    "code": "INVENTORY_INSUFFICIENT",
    "message": "部分商品库存已变化，请重新确认购物车。",
    "details": {
      "offer_ids": ["01HOFFER..."]
    },
    "retryable": false
  },
  "meta": {
    "request_id": "01HREQ...",
    "correlation_id": "01HCOR..."
  }
}
```

原则：

- `message` 用于用户/开发者可理解描述；
- 业务逻辑依赖稳定 `code`，不能解析 message；
- 内部堆栈、SQL、密钥不得返回客户端；
- 校验错误包含字段路径。

### 8.1 HTTP 状态码

| HTTP | 用途 |
|---|---|
| 200 | 查询/幂等重放成功 |
| 201 | 新资源创建成功 |
| 202 | 已接受异步处理 |
| 204 | 成功无 body |
| 400 | 请求格式/字段错误 |
| 401 | 未认证/Token失效 |
| 403 | 已认证但无权限 |
| 404 | 资源不存在或不可见 |
| 409 | 状态冲突、幂等冲突、版本冲突 |
| 422 | 业务规则不满足 |
| 429 | 限流/额度限制 |
| 502/503 | 外部依赖或服务临时不可用 |

---

## 9. 核心业务错误码

### 9.1 通用

```text
VALIDATION_ERROR
AUTH_REQUIRED
TOKEN_EXPIRED
PERMISSION_DENIED
RESOURCE_NOT_FOUND
CONCURRENT_MODIFICATION
IDEMPOTENCY_KEY_REQUIRED
IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD
RATE_LIMITED
OPERATION_REQUIRES_REVERIFY
```

### 9.2 商品/库存

```text
OFFER_NOT_ACTIVE
OFFER_CHANGED
SKU_NOT_AVAILABLE
INVENTORY_INSUFFICIENT
PRICE_QUOTE_EXPIRED
QUOTE_ALREADY_CONSUMED
INVENTORY_ADJUSTMENT_CONFLICT
ZERO_PAYABLE_ORDER_NOT_SUPPORTED
PRICE_CHANGED
ADDRESS_NOT_SERVICEABLE
CATALOG_DATA_INCOMPLETE
```

### 9.3 优惠

```text
COUPON_NOT_AVAILABLE
COUPON_EXPIRED
COUPON_NOT_ELIGIBLE
COUPON_STACKING_CONFLICT
COUPON_ALREADY_USED
PROMOTION_BUDGET_EXHAUSTED
```

### 9.4 订单/支付

```text
ORDER_NOT_CANCELLABLE
UNPAID_PARTIAL_CANCELLATION_NOT_ALLOWED
ORDER_ALREADY_CLOSED
ORDER_STATE_CONFLICT
PAYMENT_ALREADY_SUCCEEDED
PAYMENT_EXPIRED
PAYMENT_CHANNEL_UNAVAILABLE
PAYMENT_CONFIRMATION_PENDING
LATE_PAYMENT_COMPENSATION_REQUIRED
```

### 9.5 发货/售后/退款

```text
SHIPMENT_QUANTITY_EXCEEDED
ITEM_ALREADY_SHIPPED
AFTERSALE_QUANTITY_EXCEEDED
AFTERSALE_AMOUNT_EXCEEDED
AFTERSALE_STATE_CONFLICT
REFUND_ALREADY_PROCESSED
REFUND_PROCESSING
REFUND_FAILED_RETRYABLE
```

### 9.6 会员/积分/AI

```text
MEMBERSHIP_REFUND_NOT_ELIGIBLE
POINTS_INSUFFICIENT
POINTS_REWARD_ALREADY_GRANTED
AI_QUOTA_EXHAUSTED
AI_CONTEXT_VERSION_CONFLICT
AI_TOOL_NOT_ALLOWED
AI_TOOL_EXECUTION_FAILED
AI_DATA_INSUFFICIENT
```

---

## 10. 分页、排序与过滤

### 10.1 Cursor 分页

交易/消息/审计等高增长列表优先 Cursor：

```http
GET /consumer/orders?limit=20&cursor=eyJ...
```

限制：

- 默认 `limit=20`；
- 最大建议 `100`；
- cursor 为服务端不透明值；
- 不允许客户端修改 cursor 内容。

### 10.2 Page 分页

后台稳定表格可允许：

```text
?page=1&page_size=50
```

但高频变化交易列表仍推荐 Cursor。

### 10.3 排序

只接受白名单字段：

```http
?sort=price_asc
?sort=sales_desc
?sort=created_at_desc
```

禁止直接透传数据库列名。

---

## 11. 金额、数量、重量与时间

### 11.1 金额

```json
{
  "goods_amount_fen": 19900,
  "shipping_amount_fen": 800,
  "discount_amount_fen": 2000,
  "payable_amount_fen": 18700,
  "currency": "CNY"
}
```

V1 不返回浮点金额作为事实字段。前端负责格式化 `18700 -> ¥187.00`。

### 11.2 数量

商品数量整数 `quantity`。

### 11.3 重量

统一基础单位克：

```json
{ "weight_g": 4000 }
```

### 11.4 时间

```json
{ "expires_at": "2026-10-03T15:30:00+08:00" }
```

---

## 12. 媒体上传契约

流程：

1. 客户端请求受控上传凭证；
2. 服务端校验用途、格式、大小；
3. 返回对象存储上传 URL/字段；
4. 客户端直传对象存储；
5. 客户端使用 `media_asset_id` 关联评价、客服、审核证据等。

接口：

```http
POST /consumer/media/uploads
POST /merchant/media/uploads
POST /admin/media/uploads
```

业务库只保存受控媒体引用，不接受客户端任意外部 URL 作为关键证据事实。

---

# 13. Public / 游客 API

## 13.1 首页与公开配置

```http
GET /public/home
GET /public/pet-taxonomy
GET /public/brands
GET /public/brands/{brand_id}
GET /public/spus/{spu_id}
GET /public/skus/{sku_id}/offers
GET /public/content
GET /public/content/{article_id}
GET /public/nearby/places
GET /public/nearby/places/{place_id}
```

公开商品响应可以包含公开价格、Offer 摘要，但不包含用户会员/券后的最终个性化价格。

## 13.2 搜索

```http
GET  /public/search
POST /public/search/parse
```

`/search/parse` 将自然语言转成可编辑结构化条件，不直接下单。

请求示例：

```json
{
  "query": "300元以内适合绝育英短的猫粮",
  "current_pet_id": null
}
```

响应：

```json
{
  "data": {
    "keywords": "猫粮",
    "filters": {
      "max_price_fen": 30000,
      "pet_species": "CAT",
      "neutered": true
    },
    "uncertain_terms": []
  }
}
```

游客无宠物档案时，不生成伪造宠物适配结论。

---

# 14. 消费者认证 API

```http
POST /consumer/auth/phone/request-code
POST /consumer/auth/phone/verify
POST /consumer/auth/wechat/login
POST /consumer/auth/wechat/bind
POST /consumer/auth/reverify
POST /consumer/auth/refresh
POST /consumer/auth/logout
GET  /consumer/auth/sessions
DELETE /consumer/auth/sessions/{session_id}
POST /consumer/auth/sessions/revoke-others
```

微信绑定发生冲突时：

```http
409 IDENTITY_BINDING_CONFLICT
```

不得自动合并账号。

---

# 15. 消费者账户与地址 API

```http
GET    /consumer/me
PATCH  /consumer/me
GET    /consumer/addresses
POST   /consumer/addresses
GET    /consumer/addresses/{address_id}
PATCH  /consumer/addresses/{address_id}
DELETE /consumer/addresses/{address_id}
POST   /consumer/addresses/{address_id}/set-default
GET    /consumer/settings/notifications
PUT    /consumer/settings/notifications
GET    /consumer/settings/privacy
PUT    /consumer/settings/privacy
POST   /consumer/account-deletion-requests
```

账号注销为受控请求，不直接删除交易事实。

---

# 16. 宠物 API

```http
GET    /consumer/pets
POST   /consumer/pets
GET    /consumer/pets/{pet_id}
PATCH  /consumer/pets/{pet_id}
DELETE /consumer/pets/{pet_id}
POST   /consumer/pets/{pet_id}/select-current
GET    /consumer/pets/current
```

### 16.1 过敏原

```http
GET /public/allergens
PUT /consumer/pets/{pet_id}/allergens
```

请求必须区分：

```json
{
  "items": [
    {
      "allergen_id": "chicken",
      "status": "YES",
      "severity": "UNKNOWN",
      "source": "OWNER_OBSERVATION",
      "note": "吃过后出现不适"
    }
  ]
}
```

### 16.2 体重与观察

```http
GET  /consumer/pets/{pet_id}/weights
POST /consumer/pets/{pet_id}/weights
GET  /consumer/pets/{pet_id}/observations
POST /consumer/pets/{pet_id}/observations
```

### 16.3 当前粮

```http
GET    /consumer/pets/{pet_id}/current-food
PUT    /consumer/pets/{pet_id}/current-food
DELETE /consumer/pets/{pet_id}/current-food
GET    /consumer/pets/{pet_id}/food-history
POST   /consumer/pets/{pet_id}/current-food/calibrate
```

返回预计剩余时间必须明确：

```json
{
  "estimated_days_remaining": 8,
  "is_estimate": true
}
```

---

# 17. 商品、Offer、适配与比较 API

```http
GET /consumer/spus/{spu_id}
GET /consumer/skus/{sku_id}/offers
GET /consumer/skus/{sku_id}/fit?pet_id=...
POST /consumer/products/compare
GET /consumer/shops/{merchant_id}
POST /consumer/spus/{spu_id}/favorite
DELETE /consumer/spus/{spu_id}/favorite
POST /consumer/shops/{merchant_id}/favorite
DELETE /consumer/shops/{merchant_id}/favorite
```

### 17.1 Offer 响应原则

必须区分：

```json
{
  "offer_id": "01H...",
  "merchant": { "id": "01H...", "name": "XX旗舰店" },
  "sale_price_fen": 25900,
  "member_price_fen": 24900,
  "estimated_shipping_fen": 0,
  "estimated_discount_fen": 1000,
  "estimated_payable_fen": 23900,
  "price_estimate": true,
  "inventory_status": "IN_STOCK",
  "offer_version": 14
}
```

缺少地址时运费/到手价只能标为估计。

### 17.2 适配响应

```json
{
  "data": {
    "sku_id": "01HSKU...",
    "pet_id": "01HPET...",
    "result": "HAS_WARNING",
    "display_label": "存在注意项",
    "hard_conflicts": [
      {
        "type": "ALLERGEN_CONFLICT",
        "allergen_id": "chicken",
        "message": "该商品含鸡肉成分，与宠物档案中的过敏信息冲突。"
      }
    ],
    "uncertainties": [],
    "catalog_standard_version_id": "01HVER..."
  }
}
```

允许值：

```text
SUITABLE
HAS_WARNING
NOT_RECOMMENDED
INSUFFICIENT_DATA
```

商业推广不得改变该字段。

---

# 18. 购物车 API

```http
GET    /consumer/cart
POST   /consumer/cart/items
PATCH  /consumer/cart/items/{cart_item_id}
DELETE /consumer/cart/items/{cart_item_id}
POST   /consumer/cart/merge-guest-intent
```

加车请求必须使用明确 `offer_id`，不得只传 SKU 后让后端随便选商家。

示例：

```json
{
  "offer_id": "01HOFFER...",
  "quantity": 2,
  "pet_id": "01HPET..."
}
```

Offer 失效时返回明确错误，不自动替换。

---

# 19. 结账试算 API

```http
POST /consumer/checkout/quotes
GET  /consumer/checkout/quotes/{quote_id}
```

请求：

```json
{
  "cart_item_ids": ["01HCI1", "01HCI2"],
  "address_id": "01HADDR...",
  "coupon_ids": ["01HCP1", "01HCP2"],
  "use_membership": true
}
```

服务端返回：

- 分商家商品金额；
- 运费；
- 优惠来源与分摊；
- 总应付；
- Quote 过期时间；
- 每个 Offer/version；
- 价格规则版本。

```json
{
  "data": {
    "quote_id": "01HQUOTE...",
    "expires_at": "2026-10-03T15:20:00+08:00",
    "goods_amount_fen": 40000,
    "shipping_amount_fen": 800,
    "discount_amount_fen": 3000,
    "payable_amount_fen": 37800,
    "merchant_groups": []
  }
}
```

正式定价采用05第8节 `PRICING_V1_1`，尾差算法 `LARGEST_REMAINDER_V1`，商家券每商家1张、平台商品券（含新人券）整单1张、运费券整单1张；总应付至少1分。Quote正式持久化于PostgreSQL，包含status、pricing_rule_version、algorithm_version、地址/会员/Offer/购物车版本及所有分摊，不锁库存/券。客户端展示冻结金额，下单服务端按同版本重新校验；事实变动409要求重新Quote确认，不静默接受新价。

ACTIVE/CONSUMED/EXPIRED/INVALIDATED与04一致；同Quote最多一个订单。下单先检查幂等重放再检查Quote消费；新Key重复消费409 `QUOTE_ALREADY_CONSUMED`。请求address_id必须等于Quote地址，版本变化409 `CONCURRENT_MODIFICATION`。

---

# 20. 创建订单 API

```http
POST /consumer/orders
Idempotency-Key: <required>
```

请求：

```json
{
  "quote_id": "01HQUOTE...",
  "address_id": "01HADDR...",
  "client_confirmed_at": "2026-10-03T15:08:00+08:00"
}
```

服务端同一核心事务：

1. 校验 Quote/Offer/价格/地址/优惠；
2. 预占所有库存；
3. 创建总单、子单、订单项快照；
4. 固化优惠分摊；
5. 创建 Payment；
6. 写 Outbox。

任一库存失败：

```http
409 INVENTORY_INSUFFICIENT
```

不得生成半套可见订单。

成功：

```http
201 Created
Location: /api/v1/consumer/orders/{order_id}
```

---

# 21. 订单查询与动作 API

```http
GET  /consumer/orders
GET  /consumer/orders/{order_id}
GET  /consumer/suborders/{suborder_id}
POST /consumer/suborders/{suborder_id}/cancel
POST /consumer/suborders/{suborder_id}/confirm-receipt
GET  /consumer/suborders/{suborder_id}/shipments
GET  /consumer/shipments/{shipment_id}
```

### 21.1 取消

```http
POST /consumer/suborders/{suborder_id}/cancel
Idempotency-Key: ...
```

```json
{
  "items": [
    { "order_item_id": "01HOI...", "quantity": 1 }
  ],
  "reason_code": "NO_LONGER_NEEDED"
}
```

服务端判断未发货数量和售后占用；已发货数量返回422 `ORDER_NOT_CANCELLABLE`并引导售后。返回取消资源（cancellation_id、status、items、refund_id可空），已付款退款异步202；GET `/consumer/cancellations/{cancellation_id}`恢复结果。

取消接受即占数量、停止发货，退款失败不重新开放履约。未付款部分取消返回422 `UNPAID_PARTIAL_CANCELLATION_NOT_ALLOWED`；新增 `POST /consumer/orders/{order_id}/cancel` 用于父单完整未付款取消，要求幂等键和reason_code。持久化以04第10.3.1为准。

### 21.2 确认收货

```http
POST /consumer/suborders/{suborder_id}/confirm-receipt
Idempotency-Key: ...
```

不默认确认其他子单。

---

# 22. 支付 API

### 22.1 获取支付单

```http
GET /consumer/payments/{payment_id}
```

### 22.2 发起渠道支付

```http
POST /consumer/payments/{payment_id}/attempts
Idempotency-Key: ...
```

请求：

```json
{
  "channel": "WECHAT",
  "client_platform": "IOS"
}
```

响应只返回 SDK/渠道所需参数，不把第三方密钥交客户端。

### 22.3 查询支付结果

```http
GET /consumer/payments/{payment_id}/status
```

可能返回：

```text
PENDING
PROCESSING
SUCCEEDED
FAILED
CLOSED
```

客户端不能自行把渠道 SDK “成功”当订单支付成功。

### 22.4 支付渠道切换

Payment请求和响应不设置创建时channel；只有Attempt请求必填channel。Payment响应successful_attempt_id和final_channel在成功前null，成功后从实际成功Attempt派生；退款定位payment_attempt_id。

创建新 attempt 前服务端检查：

- Payment 未成功；
- 不存在不可安全并行的活动 attempt；
- 若前渠道结果不确定，则先查询/关闭再切换。

---

# 23. 支付 Webhook

```http
POST /webhooks/payments/wechat
POST /webhooks/payments/alipay
POST /webhooks/refunds/wechat
POST /webhooks/refunds/alipay
```

要求：

1. 验签；
2. 原始渠道事件 ID/流水号唯一；
3. 幂等处理；
4. 不依赖客户端 session；
5. 快速返回渠道要求的 ACK；
6. 核心交易落库后异步执行非关键通知。

晚到支付：

- 不返回“忽略”；
- 创建异常 case；
- 默认进入原路退款补偿流程。

---

# 24. 售后 API

```http
GET  /consumer/aftersales
POST /consumer/aftersales
GET  /consumer/aftersales/{aftersale_id}
POST /consumer/aftersales/{aftersale_id}/cancel
POST /consumer/aftersales/{aftersale_id}/evidence
POST /consumer/aftersales/{aftersale_id}/escalate
POST /consumer/aftersales/{aftersale_id}/return-shipment
```

创建售后：

```http
POST /consumer/aftersales
Idempotency-Key: ...
```

```json
{
  "suborder_id": "01HSO...",
  "type": "RETURN_AND_REFUND",
  "items": [
    {
      "order_item_id": "01HOI...",
      "quantity": 1
    }
  ],
  "reason_code": "DAMAGED",
  "description": "包装破损",
  "media_asset_ids": ["01HMEDIA..."]
}
```

服务端返回本次最大可退金额估算和当前状态，不接受客户端自报退款金额作为事实。

---

# 25. 评价 API

```http
GET  /consumer/spus/{spu_id}/reviews
POST /consumer/order-items/{order_item_id}/reviews
PATCH /consumer/reviews/{review_id}
```

评价创建由订单项资格决定；真实购买标识由服务端生成。

评价积分通过唯一业务事件异步/同步发放，重复请求不重复奖励。

---

# 26. 会员 API

```http
GET  /consumer/membership
GET  /consumer/membership/plans
POST /consumer/membership/orders
GET  /consumer/membership/orders/{membership_order_id}
POST /consumer/membership/orders/{membership_order_id}/payment-attempts
POST /consumer/membership/subscriptions/{subscription_id}/refund-requests
```

会员购买：

```http
POST /consumer/membership/orders
Idempotency-Key: ...
```

```json
{
  "plan_version_id": "01HPLANV..."
}
```

服务端根据当前有效期计算新的起止时间；客户端不能传 `new_expiry_at`。

V1 无自动续费 API。

---

# 27. 积分与签到 API

```http
GET  /consumer/points
GET  /consumer/points/ledger
POST /consumer/checkins
GET  /consumer/points/redemption-options
POST /consumer/points/redemptions
```

签到：

```http
POST /consumer/checkins
Idempotency-Key: ...
```

服务端判断当天是否已签到与连续天数；最多 30 天周期由当前规则版本决定。

积分兑换为原子扣减；余额可以因退款clawback变负，V1正式禁止余额<0的新兑换；非负时仍须余额>=成本。收入先抵负值。服务端持账户锁校验，失败422 `POINTS_INSUFFICIENT`。

---

# 28. 优惠券 API

```http
GET  /consumer/coupons
POST /consumer/coupons/{coupon_definition_id}/claim
GET  /consumer/coupons/{user_coupon_id}
```

结账时券核销不通过单独客户端“使用券”接口完成，而由 Quote/Order 事务控制，避免券与订单状态分离。

---

# 29. 消息与客服 API

```http
GET  /consumer/messages
POST /consumer/messages/{message_id}/read
GET  /consumer/conversations
POST /consumer/conversations
GET  /consumer/conversations/{conversation_id}/messages
POST /consumer/conversations/{conversation_id}/messages
```

消息卡片中的订单/商品引用打开时再次做授权校验，不因为聊天记录中存在 ID 就允许越权读取。

---

# 30. AI API

## 30.1 会话

```http
POST   /consumer/ai/conversations
GET    /consumer/ai/conversations
GET    /consumer/ai/conversations/{conversation_id}
DELETE /consumer/ai/conversations/{conversation_id}
POST   /consumer/ai/conversations/{conversation_id}/messages
```

发送消息：

```http
POST /consumer/ai/conversations/{conversation_id}/messages
Idempotency-Key: ...
```

```json
{
  "text": "帮豆豆比较这三款粮",
  "current_pet_id": "01HPET...",
  "selected_sku_ids": ["01HS1", "01HS2", "01HS3"]
}
```

服务端流程：

1. 验证宠物归属；
2. 记录本次明确上下文；
3. 检查 AI 额度；
4. 规则层过滤硬冲突；
5. 检索真实在售 SKU/Offer；
6. DeepSeek 解释；
7. 满足成功完成条件后扣额度；
8. 保存 prompt/rule/catalog version 引用。

### 30.2 AI 响应

```json
{
  "data": {
    "message_id": "01HAIM...",
    "text": "...",
    "pet_context": {
      "pet_id": "01HPET...",
      "name": "豆豆"
    },
    "product_cards": [
      {
        "sku_id": "01HSKU...",
        "catalog_standard_version_id": "01HVER...",
        "availability_checked_at": "2026-10-03T15:20:00+08:00"
      }
    ],
    "warnings": [],
    "quota": {
      "remaining": 9
    }
  }
}
```

### 30.3 AI 工具白名单

V1 允许服务端 AI orchestration 调用：

```text
search_products
get_product_details
get_pet_profile_minimal
compare_products
get_offer_availability
add_cart_item
favorite_product
get_nearby_vet_places
propose_pet_profile_change
```

禁止：

```text
pay_order
confirm_payment
create_irreversible_order_without_user_confirmation
prescribe_medication
diagnose_disease
modify_pet_profile_without_confirmation
```

AI 工具调用全部走内部服务契约，不能让模型直接访问数据库。

### 30.4 AI 档案建议

```http
GET  /consumer/ai/profile-proposals/{proposal_id}
POST /consumer/ai/profile-proposals/{proposal_id}/accept
POST /consumer/ai/profile-proposals/{proposal_id}/reject
```

接受时验证宠物 `version`；冲突：

```http
409 AI_CONTEXT_VERSION_CONFLICT
```

---

# 31. 附近与高德 API

```http
GET /public/nearby/places?category=VET&city=...
GET /public/nearby/places/{place_id}
POST /consumer/nearby/navigation-intents
```

`navigation-intents` 只生成/返回目的地数据与可唤起高德的安全参数，不在 Pawday 内提供完整路线导航。

医院响应只包含地点/营业/联系方式/来源等字段，不提供治疗效果排行或医疗诊断建议。

---

# 32. 商家 Web API：身份与入驻

```http
POST /merchant/auth/login
POST /merchant/auth/reverify
POST /merchant/auth/refresh
GET  /merchant/me
GET  /merchant/onboarding
PUT  /merchant/onboarding
POST /merchant/onboarding/submit
GET  /merchant/onboarding/status
```

入驻资料修改使用版本控制；已审核资料的关键变更可能重新进入审核。

---

# 33. 商家门店 API

```http
GET    /merchant/stores
POST   /merchant/stores
GET    /merchant/stores/{store_id}
PATCH  /merchant/stores/{store_id}
POST   /merchant/store-claims
GET    /merchant/store-claims/{claim_id}
```

商家不能通过 API 自行设置 `pawday_certified=true` 或官方旗舰状态。

---

# 34. 商家商品与 Offer API

```http
GET  /merchant/catalog/search
GET  /merchant/catalog/skus/{sku_id}
GET  /merchant/offers
POST /merchant/offers
GET  /merchant/offers/{offer_id}
PATCH /merchant/offers/{offer_id}
POST /merchant/offers/{offer_id}/activate
POST /merchant/offers/{offer_id}/pause
POST /merchant/offers/batch
POST /merchant/catalog-requests
GET  /merchant/catalog-requests/{request_id}
```

标准配料/营养字段为只读。

### 34.1 Offer更新与唯一库存命令

`PATCH /merchant/offers/{offer_id}` 只接收sale_price_fen、member_price_fen、fulfillment_sla，要求If-Match。销售状态使用已定义activate/pause等命令。**请求schema additionalProperties:false，禁止on_hand_qty、reserved_qty、target_on_hand_qty、status和operator**。

```json
{"sale_price_fen":25900,"member_price_fen":24900}
```

商家库存正式且唯一写入口：

```http
POST /merchant/offers/{offer_id}/inventory-adjustments
Idempotency-Key: <required>
```

```json
{"delta_qty":-2,"reason_code":"COUNT_CORRECTION","expected_version":14}
```

正式锁定delta_qty（非0有符号整数），不接收目标总量或reserved_qty；operator由会话取得。返回201：adjustment_id、offer_id、delta_qty、resulting_on_hand_qty、resulting_reserved_qty、resulting_available_qty、version。版本冲突409 `CONCURRENT_MODIFICATION`；扣减后on_hand<reserved返回409 `INVENTORY_ADJUSTMENT_CONFLICT`。唯一库存流水、余额更新和审计同事务，幂等重放返回原结果。

新Offer库存从0开始，再用此接口初始化；`/merchant/offers/batch`仅批量价格/履约修改，库存批量调用Adjustment契约且逐项报告，禁止batch旁路覆盖库存。

---

# 35. 商家订单与发货 API

```http
GET  /merchant/orders
GET  /merchant/orders/{suborder_id}
POST /merchant/orders/{suborder_id}/shipments
GET  /merchant/orders/{suborder_id}/shipments
POST /merchant/shipments/{shipment_id}/tracking-correction
```

创建 Shipment：

```http
POST /merchant/orders/{suborder_id}/shipments
Idempotency-Key: ...
```

```json
{
  "carrier_code": "SF",
  "tracking_no": "SF123...",
  "items": [
    { "order_item_id": "01HOI...", "quantity": 2 }
  ]
}
```

服务端验证累计发货数量。

---

# 36. 商家售后 API

```http
GET  /merchant/aftersales
GET  /merchant/aftersales/{aftersale_id}
POST /merchant/aftersales/{aftersale_id}/approve-refund
POST /merchant/aftersales/{aftersale_id}/approve-return
POST /merchant/aftersales/{aftersale_id}/reject
POST /merchant/aftersales/{aftersale_id}/inspection
```

所有决定记录操作者、理由与当前状态版本。

商家“同意退款”不会直接返回“退款已到账”，而是创建/触发 Refund 并进入处理状态。

---

# 37. 商家营销 API

```http
GET  /merchant/coupons
POST /merchant/coupons
PATCH /merchant/coupons/{coupon_id}
POST /merchant/coupons/{coupon_id}/publish
POST /merchant/coupons/{coupon_id}/stop
GET  /merchant/campaigns
POST /merchant/campaigns/{campaign_id}/apply
GET  /merchant/marketing/subscriptions
```

商家只能管理自身券/店铺活动，不得修改平台券。

---

# 38. 商家财务 API

```http
GET /merchant/finance/summary
GET /merchant/finance/ledger
GET /merchant/finance/statements
GET /merchant/finance/statements/{statement_id}
GET /merchant/finance/settlements
GET /merchant/finance/settlements/{settlement_id}
GET /merchant/invoices
GET /merchant/invoices/{request_id}
POST /merchant/invoices/{request_id}/complete
```

账本查询只读；商家无 API 修改财务账本。

---

# 39. 商家员工与权限 API

```http
GET    /merchant/staff
POST   /merchant/staff/invitations
PATCH  /merchant/staff/{staff_id}
POST   /merchant/staff/{staff_id}/disable
GET    /merchant/roles
POST   /merchant/roles
PATCH  /merchant/roles/{role_id}
```

角色编辑不能突破当前操作者自己的管理权限。

---

# 40. 平台管理：用户、商家、门店

```http
GET  /admin/users
GET  /admin/users/{user_id}
GET  /admin/merchants
GET  /admin/merchants/{merchant_id}
GET  /admin/merchant-reviews
GET  /admin/merchant-reviews/{review_id}
POST /admin/merchant-reviews/{review_id}/approve
POST /admin/merchant-reviews/{review_id}/request-more-info
POST /admin/merchant-reviews/{review_id}/reject
GET  /admin/store-claims
POST /admin/store-claims/{claim_id}/approve
POST /admin/store-claims/{claim_id}/reject
```

审核决定为命令接口，并要求 reason/evidence；不能直接 PATCH `status=APPROVED`。

---

# 41. 平台管理：标准商品与导入

```http
GET  /admin/brands
POST /admin/brands
GET  /admin/spus
POST /admin/spus
GET  /admin/skus
POST /admin/skus
GET  /admin/catalog-reviews
POST /admin/catalog-reviews/{request_id}/approve
POST /admin/catalog-reviews/{request_id}/reject
POST /admin/catalog-imports
GET  /admin/catalog-imports/{batch_id}
POST /admin/catalog-imports/{batch_id}/confirm
POST /admin/catalog-imports/{batch_id}/cancel
```

Excel/CSV 导入流程：

```text
upload -> parse -> validate -> duplicate report -> preview -> explicit confirm -> commit -> event/index sync
```

未经 confirm 不覆盖标准库。

已发布标准版本不可普通 PATCH 覆盖；修改产生新版本：

```http
POST /admin/skus/{sku_id}/standard-versions
POST /admin/sku-standard-versions/{version_id}/publish
```

---

# 42. 平台管理：Offer 风险与冻结

```http
GET  /admin/offers
GET  /admin/offers/{offer_id}
POST /admin/offers/{offer_id}/freeze
POST /admin/offers/{offer_id}/unfreeze
POST /admin/offers/{offer_id}/delist
```

必须提交：

```json
{
  "reason_code": "ABNORMAL_PRICE",
  "note": "..."
}
```

并产生审计日志。

---

# 43. 平台管理：订单、支付、售后、退款

```http
GET /admin/orders
GET /admin/orders/{order_id}
GET /admin/payments
GET /admin/payments/{payment_id}
POST /admin/payments/{payment_id}/requery
GET /admin/aftersales
GET /admin/aftersales/{aftersale_id}
POST /admin/aftersales/{aftersale_id}/decisions
GET /admin/refunds
GET /admin/refunds/{refund_id}
POST /admin/refunds/{refund_id}/retry
```

不得提供：

```text
PATCH /admin/payments/{id} { status: "SUCCEEDED" }
```

支付成功只能来自真实渠道确认或 MOCK 环境明确适配器。

---

# 44. 平台管理：佣金、结算与账本

```http
GET  /admin/finance/commission-policies
POST /admin/finance/commission-policies
POST /admin/finance/commission-policies/{id}/publish
GET  /admin/finance/settlement-policies
POST /admin/finance/settlement-policies
GET  /admin/finance/settlements
GET  /admin/finance/settlements/{settlement_id}
POST /admin/finance/settlements/{settlement_id}/retry
GET  /admin/finance/ledger
POST /admin/finance/ledger/adjustments
GET  /admin/finance/reconciliation
POST /admin/finance/reconciliation/jobs
```

人工账本调整：

```http
POST /admin/finance/ledger/adjustments
Idempotency-Key: ...
```

```json
{
  "merchant_id": "01HM...",
  "related_entry_id": "01HLE...",
  "amount_fen": -1200,
  "reason_code": "APPROVED_CORRECTION",
  "description": "..."
}
```

需要高权限 + reverify + 审计；历史 entry 不修改。

---

# 45. 平台管理：优惠、会员、积分

```http
GET  /admin/coupons
POST /admin/coupons
POST /admin/coupons/{id}/publish
POST /admin/coupons/{id}/stop
GET  /admin/membership/plans
POST /admin/membership/plans/versions
POST /admin/membership/plan-versions/{id}/publish
GET  /admin/points/rules
POST /admin/points/rules/versions
POST /admin/points/rule-versions/{id}/publish
GET  /admin/points/ledger
```

所有运营参数带版本和生效时间；发布新版本不改历史订单/积分事实。

---

# 46. 平台管理：AI

```http
GET  /admin/ai/prompts
POST /admin/ai/prompts/versions
POST /admin/ai/prompts/{version_id}/validate
POST /admin/ai/prompts/{version_id}/stage
POST /admin/ai/prompts/{version_id}/activate
POST /admin/ai/prompts/{version_id}/rollback

GET  /admin/ai/rules
POST /admin/ai/rules/versions
POST /admin/ai/rules/{version_id}/validate
POST /admin/ai/rules/{version_id}/activate

GET  /admin/ai/evaluations
POST /admin/ai/evaluations/runs
GET  /admin/ai/policies
POST /admin/ai/policies/versions
```

过敏等硬规则不能仅由 Prompt 版本承担。

---

# 47. 平台管理：搜索与推荐

```http
GET  /admin/search/health
POST /admin/search/reindex
GET  /admin/search/reindex/{job_id}
POST /admin/search/reconcile
GET  /admin/search/product-requests

GET  /admin/recommendations/config
POST /admin/recommendations/config/versions
POST /admin/recommendations/config/{version_id}/publish
```

索引重建为异步任务，返回 202。

---

# 48. 平台管理：风险、权限、审计、系统

```http
GET  /admin/risk/cases
GET  /admin/risk/cases/{case_id}
POST /admin/risk/cases/{case_id}/actions
GET  /admin/risk/rules
POST /admin/risk/rules/versions

GET  /admin/access/staff
POST /admin/access/staff
GET  /admin/access/roles
POST /admin/access/roles
PATCH /admin/access/roles/{role_id}

GET  /admin/audit
GET  /admin/audit/{event_id}
GET  /admin/system/health
GET  /admin/system/backups
GET  /admin/privacy/requests
POST /admin/privacy/requests/{id}/execute
```

审计日志普通管理员只读，不提供普通删除/修改 API。

---

# 49. 内部任务 API / 管理命令

内部任务尽量通过 Job Runner/队列执行；如需要运维命令 API，只挂 `/internal` 且服务到服务认证。

典型：

```http
POST /internal/jobs/orders/expire
POST /internal/jobs/payments/requery
POST /internal/jobs/refunds/retry
POST /internal/jobs/settlements/evaluate
POST /internal/jobs/outbox/publish
POST /internal/jobs/search/reconcile
```

不得由消费者/商家 token 调用。

---

## 50. 关键资源 Schema 示例

### 50.1 Money

```yaml
MoneyFen:
  type: integer
  format: int64
  minimum: 0
  description: Amount in CNY fen. 1999 means ¥19.99.
```

负向财务账本不复用非负 Money schema，单独定义 SignedMoneyFen。

### 50.2 VersionedResource

```yaml
VersionedResource:
  type: object
  required: [id, version]
  properties:
    id:
      type: string
    version:
      type: integer
      format: int64
```

### 50.3 ApiError

```yaml
ApiError:
  type: object
  required: [error, meta]
  properties:
    error:
      type: object
      required: [code, message, retryable]
      properties:
        code: { type: string }
        message: { type: string }
        retryable: { type: boolean }
        details: { type: object, additionalProperties: true }
    meta:
      type: object
      properties:
        request_id: { type: string }
        correlation_id: { type: string }
```

---

## 51. 命令接口 OpenAPI 示例

```yaml
/consumer/orders:
  post:
    tags: [Consumer Orders]
    operationId: createOrder
    security:
      - bearerAuth: []
    parameters:
      - $ref: '#/components/parameters/IdempotencyKey'
    requestBody:
      required: true
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/CreateOrderRequest'
    responses:
      '201':
        description: Order created
        headers:
          Location:
            schema: { type: string }
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/OrderResponse'
      '409':
        description: Inventory/price/idempotency conflict
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ApiError'
```

幂等参数：

```yaml
IdempotencyKey:
  name: Idempotency-Key
  in: header
  required: true
  schema:
    type: string
    minLength: 16
    maxLength: 128
```

---

## 52. 回调与外部依赖契约

第三方适配器统一内部接口，业务域不直接依赖微信/支付宝 SDK 对象。

### 52.1 PaymentProvider

```text
createPaymentAttempt(command)
queryPayment(providerTransactionRef)
closePayment(providerTransactionRef)
requestRefund(refundCommand)
queryRefund(refundRef)
verifyAndParseWebhook(rawRequest)
```

### 52.2 MapProvider

```text
searchPlaces(criteria)
getPlace(placeRef)
buildNavigationDestination(place)
```

### 52.3 LogisticsProvider（正式适配边界）

```text
queryTracking(carrierCode, trackingNo, shipmentReference)
normalizeEvents(providerPayload)
providerHealth()
```

标准TrackingResult：carrier_code、tracking_no、status（UNKNOWN/SHIPPED/IN_TRANSIT/DELIVERED/EXCEPTION）、events[{event_id, occurred_at, description, location可空}]、last_synced_at、stale、provider_reference。事件按供应商事件ID或规范化内容hash幂等，保留供应商原状态以供审计；轨迹“签收”不自动等于用户确认收货。

无轨迹/失败展示UNKNOWN、stale和重试提示，不编造轨迹。用户通过GET shipment读取归一化结果；供应商密钥只在服务端，具体物流轨迹供应商维持Provisional，由M2选型验证，不阻塞当前边界契约。电子面单仍仅预留。

### 52.4 LlmProvider

```text
complete(conversation, tools, policyVersion)
```

模型输出必须经过业务 orchestration 验证；模型不能直接决定订单/资金状态。

---

## 53. 状态迁移到 API 的映射

| 业务动作 | API | 幂等 | 关键校验 |
|---|---|---:|---|
| 提交订单 | `POST /consumer/orders` | 必须 | Quote、Offer、库存、优惠、地址 |
| 发起支付 | `POST /consumer/payments/{id}/attempts` | 必须 | Payment 未成功/未关闭 |
| 支付确认 | Webhook/Internal | 渠道唯一键 | 验签、渠道流水、库存 reservation |
| 取消未发货 | `POST /consumer/suborders/{id}/cancel` | 必须 | 未发货数量、可退金额 |
| 商家发货 | `POST /merchant/orders/{id}/shipments` | 必须 | 累计发货数量、权限 |
| 确认收货 | `POST /consumer/suborders/{id}/confirm-receipt` | 必须 | 子单可收货 |
| 售后申请 | `POST /consumer/aftersales` | 必须 | 剩余可售后数量/金额 |
| 商家同意售后 | merchant action API | 必须/业务唯一 | SLA、状态、权限 |
| 平台裁决 | `POST /admin/aftersales/{id}/decisions` | 必须 | 平台权限、证据、状态 |
| 退款 | internal/admin | refund业务号 | 最大可退、支付渠道 |
| 结算 | system/admin | settlement batch key | eligible、冻结、账本 |
| 积分奖励 | event consumer | event业务键 | 资格、重复事件 |
| AI档案修改 | proposal accept | 必须 | 用户确认、pet version |

---

## 54. 版本策略

V1 URL 主版本：

```text
/api/v1
```

兼容规则：

- 新增可选字段通常不升主版本；
- 新增枚举值前必须确保客户端按未知值安全降级；
- 删除字段、改变字段语义、改变金额单位等破坏性变化需要新版本/迁移计划；
- OpenAPI schema 变更必须进入 CI compatibility check；
- 事件 schema 独立使用 `event_version`。

---

## 55. 敏感字段与日志

以下字段不得原样进入普通应用日志：

- 完整支付密钥/签名私钥；
- Access/Refresh Token；
- 验证码；
- 完整证件号；
- 完整银行卡/支付账户敏感信息；
- 用户密码/密码哈希；
- DeepSeek/高德/支付渠道 secret。

手机号、地址等日志按策略掩码。

API 错误日志必须包含 request/correlation id，便于在不暴露用户隐私的情况下排查。

---

## 56. 限流原则

至少覆盖：

| API | 目的 |
|---|---|
| 请求短信验证码 | 防滥用/撞库 |
| 登录/再验证 | 防暴力尝试 |
| AI 消息 | 额度+系统保护 |
| 搜索解析 | 防 LLM 滥用 |
| 下单 | 防刷单 |
| 领取优惠券 | 防套利 |
| 评论/媒体 | 防刷评 |
| 商家批量操作 | 防误操作/资源耗尽 |

限流命中返回 `429 RATE_LIMITED` 与可选 `Retry-After`。

---

## 57. 缓存与 ETag

公开品牌、标准商品、文章、分类等读多写少资源可返回：

```http
ETag: "..."
Cache-Control: ...
```

消费者个性化价格、库存、结账、订单、支付、财务数据禁止使用可能导致旧事实误展示的长时间公共缓存。

结账时永远重新查询 PostgreSQL 事实，不依赖搜索缓存。

---

## 58. OpenAPI Security Schemes

```yaml
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    merchantBearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    adminBearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

实际 token 是否 JWT 在 07 ADR 进一步固化；对 OpenAPI 客户端表现为 Bearer 即可。

---

## 59. 客户端生成与契约测试

M2 建议：

1. OpenAPI 作为单一 HTTP 契约源；
2. CI 校验 YAML；
3. 生成/校验 Dart API client；
4. 为 Vue 3 两个 Web 生成共享 TypeScript types/client；
5. 后端 controller DTO 与 OpenAPI 做一致性测试；
6. 针对错误码建立 contract test；
7. 关键状态机接口建立集成测试，不只 Mock controller。

---

## 60. M1 API 验收推演

### A01 游客浏览后登录恢复

游客调用 public 商品与本地加车意图；登录后调用 merge；Offer 失效时明确返回失效项，不替换商家。

### A02 并发下单

两客户端对库存1的 Offer 使用不同 Idempotency-Key 同时 `POST /consumer/orders`：仅一方 201；另一方 409 `INVENTORY_INSUFFICIENT`。

### A03 客户端超时重试

第一次创建订单服务端已成功但客户端断线。客户端使用同一 Key 重试：返回同一 `order_id`，不再预占库存。

### A04 支付重复回调

微信同渠道交易号回调 3 次：Payment 只 SUCCEEDED 一次，API/账本/库存无重复副作用。

### A05 晚到支付

Payment 已 CLOSED 后真实成功 webhook：记录 late case，默认创建退款补偿；不静默恢复库存已失效订单。

### A06 多商户订单

一个 Quote 两个 merchant groups：创建一个 Order + 两个 Suborder；各商家 API 仅能读取自己的子单。

### A07 部分发货

商家创建 Shipment 数量2，再创建数量1；第四件尝试返回 `SHIPMENT_QUANTITY_EXCEEDED`。

### A08 部分售后

订单项数量3，第一次售后1成功；第二次2成功；再次1返回 `AFTERSALE_QUANTITY_EXCEEDED`。

### A09 优惠退款

原实付分摊 48/32 元，退第二项时退款依据订单快照为32元，不重新计算满减。

### A10 已结算后退款

退款成功触发 append-only ledger adjustment；历史 settlement 查询响应保持原数据。

### A11 商品版本

SKU 标准 V4 发布后，新适配 API 引用 V4；旧订单详情继续返回 V3 snapshot/version。

### A12 AI 失败

DeepSeek 网络失败：返回可重试 AI 错误；额度不扣。工具加车失败：AI 响应不得显示“已加入购物车”。

### A13 AI 上下文切换

旧会话宠物 A；用户当前宠物切 B；新消息显式记录 B，上游不得改写旧消息的 A 上下文。

### A14 商家越权

商家A员工请求商家B `suborder_id`：404/403，绝不返回订单数据。

### A15 平台权限

客服角色调用佣金发布：403 `PERMISSION_DENIED`；即使前端手工构造请求也失败。

### A16 版本冲突

两个运营同时编辑 Offer；第二个携带旧 `If-Match` 更新返回 409，不覆盖第一个结果。

### A17 隐私注销

注销流程完成后消费者资源不可登录恢复；历史交易由后台受控查询保留，新注册相同手机号不继承旧资源。

### A18 异步搜索

Offer 下架事务成功、索引事件延迟。搜索短暂仍显示，但加车/Quote/Order API 实时校验并拒绝成交。

---

## 61. 本文与工程实现的边界

本文确定：

- 资源路径；
- HTTP 语义；
- 认证与授权边界；
- 幂等与版本冲突规则；
- 请求/响应主要结构；
- 业务错误码；
- 状态迁移动作接口；
- 支付 webhook 原则；
- AI 工具白名单；
- OpenAPI 组织和契约测试方向。

M2 工程阶段继续输出：

- 在M1已验证的 `openapi/pawday-v1.yaml` 基础上补齐非核心模块DTO与客户端生成；不得把M1核心契约再次推迟；
- Spring Boot controller/application service 实现；
- PostgreSQL migration；
- Redis/RabbitMQ/OpenSearch 适配；
- Flutter/TypeScript 生成客户端；
- 契约测试与状态机集成测试。

---

## 62. M1 API 完成门槛

06 文档完成需满足：

- 02 中消费者、商家、平台关键页面动作都能映射到 API；
- 04 中关键领域对象都有资源/命令接口或明确内部事件责任；
- 05 中所有关键状态迁移不存在“直接改 status”后门；
- 下单、支付、售后、退款、积分、会员等关键写操作有幂等策略；
- 并发编辑有版本冲突策略；
- 商家/消费者/平台资源作用域清晰；
- 财务和支付接口不允许客户端声明事实；
- AI 不能直接支付、诊断、绕过规则或未经确认改档案；
- OpenAPI 足够支持 M2 生成客户端与契约测试。

下一步：`07-技术选型ADR.md`，记录 Java/Spring Boot、PostgreSQL、Redis、RabbitMQ、OpenSearch/Elasticsearch 类搜索服务、Vue 3 + TypeScript、Flutter、Outbox、对象存储/CDN 等选型、备选方案和后续演进边界。


## 63. M1机器契约交付与优先级

`openapi/pawday-v1.yaml` 为M1机器契约根，使用OpenAPI 3.1.0 / JSON Schema 2020-12，包含本次整改与交易主链的正式请求/响应、权限、幂等、错误响应、枚举和约束；`pawday-v1.bundle.json` 为校验后的自包含bundle。单文件仅使用内部$ref。

根规范中的操作均为正式可生成DTO契约。本文其他非核心业务路径是设计清单，完整DTO在M2对应模块前补齐，**不能把未写入根规范的路径当成已生成/已验证接口**；coverage.json逐项列出正式覆盖和待细化路径。根规范是已覆盖操作的HTTP形状权威；本文与04/05负责无法仅靠schema表达的并发、归属、累计金额、外部确认和事务语义。

验证入口 `openapi/validate_contract.py`；固定依赖见requirements-validation.txt。验证包含OAS3.1结构、$ref、operationId、路径参数、关键鉴权/幂等、禁止库存PATCH、状态枚举、正反样例、定价/退款边界。实际Spring Boot与PostgreSQL集成验证属于M2，生产通道与恢复属于M6。

标准依据：[OpenAPI 3.1.0](https://spec.openapis.org/oas/v3.1.0.html)；Offer NULL唯一语义依据：[PostgreSQL唯一索引](https://www.postgresql.org/docs/current/indexes-unique.html)。
