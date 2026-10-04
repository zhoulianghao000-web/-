# OpenAPI 机器契约

`pawday-v1.yaml` 是 M1 全量约定，`pawday-m2.1.yaml`/`pawday-m2.2.yaml` 保留历史增量，当前运行契约为 `pawday-m2.3.yaml`（43 operations / 47 schemas）。`x-implemented-in` 标明首次落地阶段。

```bash
python -m pip install -r requirements-validation-lock.txt
python validate_contract.py
python validate_m23_contract.py
python validate_m23_contract.py --samples ../backend/target/m23-storage-contract-samples.json --report storage-response-report.json
python validate_m23_contract.py --samples ../backend/target/m23-search-contract-samples.json --report search-response-report.json
```

Redocly 2.57.0 minimal lint 和 bundle 已为四份规范执行。动态响应检查只证明实际采样 method/path/status 范围；二进制内容另由真实 HTTP 字节对比测试，不把 JSON schema 校验冒充图片内容验收。验收样本中的 access/refresh/reverify/upload token 已脱敏。
