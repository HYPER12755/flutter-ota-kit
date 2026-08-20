# 快速上手

本文档覆盖 flutter_patcher 的本地开发流程。生产部署相关内容见 [生产环境实践手册](production-playbook-zh.md)。

---

## 本地 mock server

如果你想在没有后端的情况下体验 HTTP `checkUpdate → applyPatch` 流程，可以直接启动内置 mock server。它只用于本地开发联调，不适合作为生产补丁分发服务。

```bash
# 修改 Dart 代码后重新构建 release APK
flutter build apk --release

# 构建补丁包
dart run flutter_patcher:pack \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version dev-1 \
  --target-version-code 100

# 在 0.0.0.0:8080 暴露 dist/patch.zip 和 dist/manifest.json
dart run flutter_patcher:mock_server --dist dist
```

手机和电脑处于同一 Wi-Fi 后，在客户端请求：

```dart
final check = await FlutterPatcher.checkUpdate(
  'http://<你的电脑局域网IP>:8080/check',
);

if (check.hasUpdate) {
  await FlutterPatcher.applyPatch(check.patch!);
}
```

插件还提供一个可选的最小 check-update JSON 协议，主要用于快速接入、示例和本地联调。生产环境如果已有自己的更新、灰度或鉴权协议，建议直接解析业务响应并构造 `PatchInfo`。协议格式与 `checkUpdate` 用法见 [API 参考](https://pub.dev/documentation/flutter_patcher/latest/topics/API-reference-topic.html) 和 [架构设计](https://pub.dev/documentation/flutter_patcher/latest/topics/Architecture-topic.html)。

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
dart run flutter_patcher:pack \
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

完整设计见 [崩溃保护文档](https://pub.dev/documentation/flutter_patcher/latest/topics/Crash-protection-topic.html)。
