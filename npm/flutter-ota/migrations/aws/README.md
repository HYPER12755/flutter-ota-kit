# AWS migrations

The AWS backend stores bundle metadata as JSON in S3 (blob database), not in a
relational database. There are **no SQL migrations** to apply — the bucket and
object prefix are created on first `deploy`.

If you front downloads with CloudFront, provision the distribution separately.
