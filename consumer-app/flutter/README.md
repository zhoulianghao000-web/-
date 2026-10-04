# Consumer Flutter App

M2 bootstrap defaults (Provisional):
- Flutter stable
- Riverpod
- go_router
- OpenAPI-generated DTO/client + Repository layer
- no payment/AI provider secrets in the app

Suggested initialization on the target workstation:

```bash
flutter create .
flutter pub add flutter_riverpod go_router dio
flutter analyze
flutter test
```

M2 first screens: launch, login shell, five-tab navigation shell, API environment diagnostics.
