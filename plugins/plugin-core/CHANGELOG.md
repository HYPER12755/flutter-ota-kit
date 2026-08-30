## 0.0.2

### Changed

- **Shared previously-duplicated backend helpers in one place.** Extracted
  `ensureExpectedBucket` (the S3/R2 bucket-mismatch guard, formerly copied
  byte-for-byte in the cloudflare + aws storage profiles), `normalizeMetadata`
  (bundle `metadata` JSON-string/object normalization, formerly in the supabase +
  postgres mappers and cloudflare's `parseMetadata`), `buildBundlePatchId`
  (the `${bundleId}:${baseBundleId}` patch primary key, formerly in three mappers),
  and `updateJsonKeyRegex` (the `update.json` key matcher, formerly duplicated in
  the aws blob database + `createBlobDatabasePlugin`). The four backend plugins
  now import these from `plugin-core` instead of maintaining their own copies.
  Public API of the backend packages is unchanged (cloudflare still re-exports
  `buildBundlePatchId` / `parseMetadata` as aliases of the shared helpers).

## 0.0.1

- Initial release of `flutter_ota_kit_plugin_core` as part of the flutter_ota_kit OTA toolkit.
