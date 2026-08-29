# FAQ

## Must the patch and base APK use the same Flutter version?

Yes. `libapp.so` is tightly coupled to the Flutter Engine and Dart runtime. Different Flutter versions cannot safely load each other's `libapp.so`. After upgrading the Flutter SDK or Engine, you must ship a new release.

## A user skipped intermediate patch versions and just got the latest one — what happens?

Each patch is a complete `libapp.so` and does not depend on previous patches. Users can jump straight from "no patch" or an old patch to the latest one.

## How do I iterate quickly during development without uploading to a CDN?

For the offline flow, run the sample app from the [5-minute walkthrough](../README.md#try-it-in-5-minutes). For HTTP testing, deploy to a cloud backend (Supabase is fully automated via `flutter-ota init supabase` + `flutter-ota migrate supabase`) and point your app at that backend with `FlutterPatcher.configureSupabase(...)`.

## How do I handle multiple ABIs?

The server must distribute a `patch.zip` per ABI (each patch embeds one `lib/<abi>/libapp.so`). The client can read the current device ABI via `FlutterPatcher.deviceAbi` and include it in your update request.

## How do I handle multiple flavors?

The server should track patches by `flavor × ABI × versionCode`. Different flavors typically have different configs, package names, resources, and business logic — never share a patch across flavors.

## Do I need to tweak ProGuard / R8 rules?

Usually no. The plugin's reflection targets non-obfuscated Flutter Engine classes and is unaffected by your business obfuscation.

## Can a patch be revoked?

Yes. On the client, `FlutterPatcher.rollback()` deletes the current patch. On the server, simply stop returning that version from your update endpoint and new users will not download it.

## Why doesn't a patch take effect immediately?

Once the current process has loaded `libapp.so`, it can't be safely swapped at runtime. To stay safe, the patch is written to disk and loaded on the next cold start.

## Why does each patch need a `targetVersionCode`?

A patch is only valid against the base APK it was built for. Binding `targetVersionCode` prevents loading old patches after an APK upgrade and prevents the server from accidentally shipping a patch to incompatible builds.

## See also
- [Configuration](configuration.md) — env vars, `.env`, resolution order
- [Developer Guide](developer-guide.md) — targeting, channels, strategies
- [Beginner Guide](beginner-guide.md) — zero-to-first-OTA walkthrough
- [Getting Started](getting-started.md) — first deploy
