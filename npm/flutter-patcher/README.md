# flutter-patcher (flutter-ota CLI)

Command-line interface for [flutter_patcher](https://github.com/HYPER12755/flutter_patcher) — a self-hosted OTA ("code push") platform for Flutter Android, hot-updater compatible.

## Install

```bash
npm i -g @_nazmiforreal/flutter-ota
```

This installs the `flutter-patcher` command. A prebuilt Linux binary ships with the package; on other platforms it falls back to `dart compile exe` (requires the [Dart SDK](https://dart.dev)).

## Usage

```bash
flutter-patcher --help
flutter-patcher keys                                              # generate an Ed25519 keypair
flutter-patcher build -a app-release.apk \
  --version 1.0.0 --target-version-code 1                        # -> dist/patch.zip (all ABIs)
flutter-patcher deploy --source dist \
  --channel production --backend standalone \
  --key <PRIVATE_KEY_BASE64>                                      # upload + sign a bundle
```

### Backends

`--backend supabase|postgres|cloudflare|aws|standalone` (or `FLUTTER_PATCHER_BACKEND`).
Each resolves its own env / `.flutter_patcher.json` config.

### Commands

`init`, `build`, `deploy`, `bundle` (list/delete/promote), `rollback`, `channel`
(get/set/list), `fingerprint`, `doctor`, `migrate`, `config`, `keys`, `console`,
`patch`, `mock_server`.

## License

MIT
