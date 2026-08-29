# 常见问题

## 补丁和基准 APK 的 Flutter 版本必须一致吗？

是的。`libapp.so` 与 Flutter Engine / Dart 运行时深度绑定，不同 Flutter 版本的 Engine 无法安全加载对方的 `libapp.so`。如果升级了 Flutter SDK 或 Flutter Engine，必须重新发版。

## 用户跳过了中间版本的补丁，直接收到最新补丁会怎样？

每个补丁都是完整的 `libapp.so`，不依赖之前的补丁。用户可以从无补丁或旧补丁直接跳到最新补丁。

## 开发期间怎么快速验证，不想每次上传 CDN？

离线流程可以直接跑 [5 分钟体验](../README-zh.md#5-分钟体验) 里的示例 App；HTTP 流程可以部署到云端后端（Supabase 最省事：先 `flutter-ota init supabase`，再 `flutter-ota migrate supabase`），然后在 App 里用 `FlutterPatcher.configureSupabase(...)` 指向该后端。

## 多个 ABI 怎么处理？

服务端需按 ABI 分发不同的 `patch.zip`（每个补丁内部只携带一份 `lib/<abi>/libapp.so`）。客户端可通过 `FlutterPatcher.deviceAbi` 获取当前设备 ABI，并将其带入你自己的更新请求。

## 多 flavor 怎么处理？

建议服务端按 `flavor × ABI × versionCode` 维度管理补丁。不同 flavor 的配置、包名、资源和业务逻辑可能不同，不建议混用补丁。

## 需要修改 ProGuard / R8 配置吗？

通常不需要。插件的反射操作针对 Flutter Engine 的非混淆类，不受宿主业务混淆影响。

## 补丁能撤回吗？

可以。客户端侧调用 `FlutterPatcher.rollback()` 会删除当前补丁。服务端侧只要停止在更新接口中返回该版本补丁，新用户就不会继续下载。

## 补丁为什么不是立即生效？

`libapp.so` 已经被当前进程加载后，无法安全地在运行时替换。为了保证稳定性，补丁会先落盘，并在下一次冷启动时加载。

## 为什么要绑定 `targetVersionCode`？

补丁只适用于构建它时对应的基准 APK。绑定 `targetVersionCode` 可以避免 APK 升级后继续加载旧补丁，也可以避免服务端误把补丁下发给不兼容版本。
