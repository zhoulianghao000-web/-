# Pawday 消费者 App

实体 Flutter 工程位于 `flutter/`，使用 Riverpod + go_router。五 Tab：首页、分类、宠物、附近、我的；已连接手机号 OTP、session/refresh 与 Repository/API 层。

```sh
cd consumer-app/flutter
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run --dart-define=PAWDAY_API_BASE=http://127.0.0.1:8080/api/v1
```

Android 模拟器将 API 地址改为 `http://10.0.2.2:8080/api/v1`。Release 强制 HTTPS；Web 是开发预览，当前 Android 产物为 debug 包。原生会话使用 flutter_secure_storage，Web 预览使用内存；恢复检查服务端身份，注销/换账号清空当前宠物 context。实际宠物与商品领域接口在 M3 加入。

完整构建、CI 和边界见 [工程说明](../docs/M2.4-前端工程说明.md)与 [M2 总验收](../docs/M2-总验收报告.md)。
