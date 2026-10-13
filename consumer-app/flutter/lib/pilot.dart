import 'package:flutter/foundation.dart';

const pilotMode = bool.fromEnvironment('PAWDAY_PILOT');
bool get androidGuestSkipAvailable =>
    pilotMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
const pilotLabel = '模拟试点 · 仅测试账号 · 不发生真实交易、短信或 AI 调用';
