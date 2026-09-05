/// <reference path="../pb_data/types.d.ts" />

// PocketBase JS hook: validate and enrich bundle records on create.
// Runs inside the PB Go binary's embedded JS VM (goja). Use $app.dao() to
// query, $app.settings() to read config, $apis.request() to call webhooks.

/** @type {OnRecordCreateRequestHandler} */
onRecordCreateRequest((e) => {
    // Reject bundles that look malformed.
    const b = e.record;
    if (!b.get("channel") || !b.get("platform") || !b.get("file_hash")) {
        throw new BadRequestError("channel, platform and file_hash are required");
    }
    if (b.getString("platform").length > 16) {
        throw new BadRequestError("platform must be <= 16 chars");
    }
    if (b.getInt("rollout_cohort_count") > 1000) {
        throw new BadRequestError("rollout_cohort_count must be 0..1000");
    }

    // Append to the audit log.
    const audit = $app.dao().findCollectionByNameOrId("audit_log");
    const row = new Record(audit, {
        action: "deploy",
        bundle_id: b.get("id"),
        channel: b.get("channel"),
        details: JSON.stringify({
            platform: b.get("platform"),
            message: b.get("message"),
            should_force_update: b.getBool("should_force_update"),
        }),
    });
    $app.dao().save(row);

    e.next();
}, "bundles");

/** @type {OnRecordUpdateRequestHandler} */
onRecordUpdateRequest((e) => {
    const b = e.record;
    if (b.getInt("rollout_cohort_count") > 1000) {
        throw new BadRequestError("rollout_cohort_count must be 0..1000");
    }
    e.next();
}, "bundles");

/** @type {OnRecordDeleteRequestHandler} */
onRecordDeleteRequest((e) => {
    const audit = $app.dao().findCollectionByNameOrId("audit_log");
    const row = new Record(audit, {
        action: "delete_bundle",
        bundle_id: e.record.get("id"),
    });
    $app.dao().save(row);
    e.next();
}, "bundles");
