# 快速上手

本文档覆盖 flutter_ota_kit 的本地开发流程。生产部署相关内容见 [生产环境实践手册](production-playbook-zh.md)。

---

## 没有后端时如何快速体验

如果没有现成后端，推荐直接接入 Supabase（全自动化，几分钟即可跑通完整 HTTP 流程）：

```bash
npm i -g @_nazmiforreal/flutter-ota
flutter-ota init supabase
flutter-ota migrate supabase
flutter build apk --release
flutter-ota build --name dev-1 --platform android --arch x86_64
flutter-ota deploy --source dist --channel production --backend supabase --key <PRIVATE_KEY_BASE64>
```

然后在 App 中：

```dart
await FlutterPatcher.init(
  publicKey: '<PUBLIC_KEY_BASE64>',
  autoApplyUpdates: true,
);
await FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  supabaseUrl: 'https://<ref>.supabase.co',
  anonKey: '<ANON_KEY>',
  bucket: 'bundles',
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.fingerprint,
  appVersion: '1.0.0',
));
await FlutterPatcher.checkAndApplyUpdates();
```

`flutter-ota init` 支持四种云端后端：`supabase`（全自动化）、`postgres`、`cloudflare`（R2 + D1）、`aws`（S3）。除 Supabase 外，其余后端的 `migrate` 只打印需要手动执行的命令。各后端的凭据、环境变量与设备侧 `configureX` 示例见 [架构设计](architecture-zh.md) 的「后端」一节。

更多后端协议细节见 [API 参考](https://pub.dev/documentation/flutter_ota_kit/latest/topics/API-reference-topic.html) 和 [架构设计](architecture-zh.md)。

---

## 省略 MD5 校验

`PatchInfo.md5` 是可选字段。若服务端协议不下发 md5（或你只想靠 HTTPS 防篡改），可省略：

```dart
PatchInfo(version: 'fix-1', patchUrl: '...', targetVersionCode: 100); // md5 默认空串
```

此时下载完整性校验会被跳过。**注意签名校验也会一并跳过**（Ed25519 签名输入即 md5 hex，没有 md5 就没有签名输入）。要启用签名校验必须同时下发 md5。

---

## 多 ABI 配置

服务端需按 ABI 分发不同的 `patch.zip`（每个补丁内部只携带一份 `lib/<abi>/libapp.so`）。客户端可通过 `FlutterPatcher.deviceAbi` 获取当前设备 ABI，并将其带入你自己的更新请求。

---

## 多 Flavor 配置

建议服务端按 `flavor × ABI × versionCode` 维度管理补丁。不同 flavor 的配置、包名、资源和业务逻辑可能不同，不建议混用补丁。

---

## `--assets` 进阶用法

路径较多时，把 `--assets` 指向一个文本文件，前缀 `@` —— 每行一个路径，`#` 开头为注释，内联和 `@file` 可以混用：

```bash
# patch-assets.txt
assets/hero.png
assets/strings/zh.json
assets/illustrations/onboarding-1.png
```

```bash
dart run flutter_ota_kit:pack \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100 \
  --assets @patch-assets.txt,assets/last-minute.png
```

---

## 崩溃保护调参

如果需要调整崩溃保护参数，可以显式传入 `init`：

```dart
await FlutterPatcher.init(
  maxCrashCount: 1,
  verifyAfter: const Duration(seconds: 5),
);
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `maxCrashCount` | `1` | 连续失败多少次后熔断补丁 |
| `verifyAfter` | `5 seconds` | 首帧后 Dart 错误钩子继续监听的窗口 |

Android 11+ 可以通过 `ApplicationExitInfo` 更准确地区分崩溃、ANR、用户主动关闭和系统回收。Android 10 及以下识别能力有限，建议结合线上崩溃监控和服务端下架策略。

完整设计见 [崩溃保护文档](https://pub.dev/documentation/flutter_ota_kit/latest/topics/Crash-protection-topic.html)。
