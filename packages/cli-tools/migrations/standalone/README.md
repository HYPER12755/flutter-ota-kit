# Standalone migrations

The `standalone` backend is a self-hosted bundle store (served by the
`flutter_patcher_server` middleware). It does not use a relational database, so
there are no SQL migrations to run through `flutter_patcher migrate`.

Set it up by running the standalone server (see `packages/server`) and pointing
your app at it via `FlutterPatcher.configureServer(...)`.
