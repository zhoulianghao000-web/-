# Pawday 安卓游客入口测试版安装说明

安卓版本：0.6.13+19。文件：`Pawday-Consumer-0.6.13-guest-debug.apk`。

1. 将新APK复制到安卓手机后打开安装。也可在电脑双击桌面PawdayV1，进入本机入口下载APK；手机不能直接使用电脑的127.0.0.1下载地址。
2. 如果系统提示签名冲突/无法覆盖安装，先卸载旧测试版再安装新包。旧手机内的登录状态和本地偏好会清除，服务端已保存的数据保留。新旧签名比较已记录在交付验证JSON。
3. 打开“爪日 Pawday”，在手机号登录页右上角点击 **跳过**，直接进入首页，不必填手机号、验证码或勾选登录同意。
4. 游客可以查看首页参考设计及五Tab入口。测试商品/门店资料、宠物和交易等个人功能仍提示登录；在“我的”点击“手机号登录”可继续原测试流程。重新启动软件后可再次点击“跳过”。
5. 游客预览可离线查看本地参考内容。需要完整模拟交易时，仍须连接本机后端和指定测试账号；使用ADB测试手机时沿用`adb reverse tcp:8086 tcp:8086`及电脑端PawdayV1服务，未把本机API开放到公网。

本次只更新安卓测试包。消费者网页、商家和管理员入口仍按原账号登录；桌面图标、既有测试数据及安全修补保持。所有交易、短信和AI调用仍模拟，生产项继续留白。

完整开发ZIP需要全部解压后使用。现有桌面PawdayV1已由交付工具更新，直接双击原图标即可。新目录可执行`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/create-desktop-shortcut.ps1 -DeliveryRoot "实际解压目录"`创建入口；启动器会等待Docker和四服务健康，首次构建需要网络。账号从本机“测试账号”窗口查看，不分享该窗口截图。需要停止时执行`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/desktop.ps1 -Action Stop`，不要重置Docker或删除volume。
