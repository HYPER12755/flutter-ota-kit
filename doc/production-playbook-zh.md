# 生产环境实践手册

在生产环境发布 flutter_ota_kit 补丁的最佳实践和经验沉淀。

---

## 灰度发布

不要直接 100% 下发补丁。建议逐步放量：

```text
1% → 5% → 20% → 50% → 100%
```

每个阶段观察 crash 率、启动失败率和关键业务指标。

---

## 上报启动诊断

建议上报 `lastBootDiagnostic`：

```dart
final diag = await FlutterPatcher.lastBootDiagnostic;

if (diag != null && !diag.isHealthy) {
  // 替换为你自己的埋点 SDK：Firebase Analytics / Sentry / 自家上报等
  analytics.report('patch_dropped', {
    'status': diag.status.name,
    'patch_version': diag.patchVersion,
    'crash_count': diag.crashCount,
    'message': diag.message,
  });
}
```

如果同一补丁短时间内多次触发 `droppedCircuitBreaker`，服务端应自动停止下发。

---

## 保留发布记录

建议为每个补丁记录：

| 字段 | 示例 |
|---|---|
| 补丁版本 | `1.0.0-h1` |
| 目标 APK `versionCode` | `100` |
| ABI | `arm64-v8a` |
| Flavor | `production` |
| MD5 | `0123456789abcdef...` |
| 签名 | （如有下发） |
| 发布时间 | `2025-07-15T10:00:00Z` |
| 灰度比例 | `20%` |
| 状态 | 灰度中 / 全量 / 已下架 |

---

## 准备紧急下架

紧急下架只需要从你的更新接口中停止下发该补丁版本。已经触发崩溃保护的设备会在本地回滚，并拒绝再次应用同一份问题补丁。

---

## 多 ABI 分发

服务端需按 ABI 分发不同的 `patch.zip`（每个补丁只携带一份 `lib/<abi>/libapp.so`）。客户端通过 `FlutterPatcher.deviceAbi` 上报 ABI。

推荐服务端分发键：`ABI × flavor × versionCode`。

---

## 多 Flavor 分发

不同 flavor 的配置、包名、资源和业务逻辑可能不同，不建议混用补丁。服务端应按 `flavor × ABI × versionCode` 维度管理。

---

## 实战经验

_本节收录来自生产用户的实战 tips。如果你有经验可以分享，欢迎 [提 issue](https://github.com/HYPER12755/flutter_ota_kit/issues)，我们会加到这里。_
