# flutter-ota (flutter-ota CLI)

Command-line interface for [flutter_ota_kit](https://github.com/HYPER12755/flutter-ota-kit) — a multi-backend OTA ("code push") toolkit for Flutter Android, hot-updater compatible.

## Install

```bash
npm i -g @_nazmiforreal/flutter-ota
```

This installs the `flutter-ota` command. A prebuilt Linux binary ships with the package; on other platforms it falls back to `dart compile exe` (requires the [Dart SDK](https://dart.dev)).

## Usage

```bash
flutter-ota --help
flutter-ota keys                                              # generate an Ed25519 keypair
flutter-ota build -a app-release.apk \
  --version 1.0.0 --target-version-code 1                        # -> dist/patch.zip (all ABIs)
flutter-ota deploy --source dist \
  --channel production --backend supabase \
  --key <PRIVATE_KEY_BASE64>                                      # upload + sign a bundle
```

### Backends

`--backend supabase|postgres|cloudflare|aws`.
Each resolves its own env / `.flutter_ota_kit/config.json` (global: `~/.flutter_ota_kit/config.json`).

### Commands

`init`, `build`, `deploy`, `bundle` (list/show/delete/disable/enable/force/promote/update),
`rollback`, `channel` (list/get/set), `fingerprint`, `doctor`, `migrate`, `config`
(get/set/list), `keys`, `console`, `storage` (list/delete).

## License

MIT
