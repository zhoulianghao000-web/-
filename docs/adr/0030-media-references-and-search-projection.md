# 媒体引用与可重建搜索投影

媒体内容由统一 ObjectStorageProvider 管理，PostgreSQL 保存主体、用途、内容身份和恢复责任；上传凭证绑定资源及当前会话，供应商 IO 与数据库状态迁移分阶段执行。资源表不保存文件字节，后续业务领域仅引用资源 ID；正式云适配器可替换开发文件适配器。

商品检索采用 PostgreSQL 权威源、Outbox/Inbox 和持久同步任务，OpenSearch 写入使用稳定 SKU ID 与数据库修订号，删除保留版本墓碑并由读取别名过滤。全量重建生成独立物理索引，验证完整文档后以单次别名请求切换；旧索引保留。搜索外部漂移可能带有较高引擎版本，对账选择新索引重建，避免绕过数据库修订号或在现用索引上删除数据；其代价是首次基础实现的对账修复需要全量扫描，M3 扩展目录后再做大规模批量与快照优化。

实现与恢复模型见 [M2.3 资源与搜索模型](../M2.3-资源与搜索模型.md)。别名切换和外部版本语义参考 [OpenSearch Index aliases](https://docs.opensearch.org/latest/im-plugin/index-alias/) 与 [Index Document API](https://docs.opensearch.org/latest/api-reference/document-apis/index-document/)。
