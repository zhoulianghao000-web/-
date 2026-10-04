---
status: accepted
---
# 稳定业务事件 ID、持久 inbox 和独立外部发送任务

M2.2 选择至少一次发布与持久消费去重，保持业务 event_id 稳定，为 RETRY/DLQ 分配独立 transport ID；confirm 丢失允许重发。claim token 与租约隔离 worker，已完成 inbox 不因人工重放清除，generation 隔离旧尝试。相比追求跨 broker/数据库的伪原子提交，这让故障恢复路径可以检查和操作。

OTP 创建仅在 PostgreSQL 事务里写挑战与 Outbox；consumer 同事务写 inbox 和 sms_delivery，提交后 ack。发送者在事务外调用供应商，以 challenge ID 幂等；未接入的供应商不能声称已具备 exactly-once，正式适配必须证明同键去重或查询不确定发送结果。发送材料加密且按过期/完成清除，队列只含引用。

发布、消费和短信分别有限重试；DEAD 不删除，DLQ 转发也持久化，只有管理员二次验证、RBAC、版本、幂等键、审计同事务的命令可恢复。基础设施数据库不可用时保留 broker 消息，不耗用业务 poison 预算；不可解析消息由 quorum at-least-once dead lettering 隔离。

机制依据：[RabbitMQ confirms](https://www.rabbitmq.com/docs/confirms)、[可靠性与确认丢失重复发布](https://www.rabbitmq.com/docs/reliability)、[quorum dead lettering](https://www.rabbitmq.com/docs/quorum-queues#dead-lettering)、[Spring AMQP CorrelationData](https://docs.spring.io/spring-amqp/docs/current/api/org/springframework/amqp/rabbit/connection/CorrelationData.html)。验收采用真实 RabbitMQ，TCP 层丢弃 confirm 帧；不把 mock 结果当成 broker 证据。
