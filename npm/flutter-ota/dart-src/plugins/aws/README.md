# flutter_ota_kit_aws

AWS backend for flutter_ota_kit: bundle metadata in an **S3-backed blob
database** and artifacts in **S3** (with optional CloudFront signed URLs). Used
by the `flutter-ota` CLI and the Flutter SDK's `FlutterPatcher.configureAws(...)`.

## What's inside

- `s3Database` / `S3DatabaseConfig` — bundle metadata stored as S3 objects.
- `s3Storage` / `AwsS3StorageConfig` — artifact storage in S3.
- CloudFront signed URLs: `cloudfrontSignedUrl`, `verifyCloudfrontSignedUrl`,
  and `withCloudFrontSignedUrl(...)`.
- `AwsS3ClientLike` / `AwsCloudFrontClientLike` test seams.

## Configuration (environment)

| Variable | Purpose |
| --- | --- |
| `AWS_REGION` | S3 region (falls back to `AWS_REGION`/`AWS_DEFAULT_REGION` if unset). |
| `AWS_BUCKET` | Target bucket name. |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Credentials. |
| `AWS_ENDPOINT` | Optional custom endpoint (e.g. MinIO). |
| `AWS_BASE_PATH` | Optional key prefix. |
| `AWS_SESSION_TOKEN` | Optional temporary session token. |

## License

MIT.
