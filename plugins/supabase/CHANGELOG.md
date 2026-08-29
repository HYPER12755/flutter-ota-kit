## 0.1.1

- fix(supabase): the `migrate` RLS migration now creates the public-read policies
  (`allow public read bundles`, `allow public read bundle_patches`, `public bundles read`)
  so the anon-key app can actually fetch bundles. Previously RLS was enabled with zero
  policies, so every fresh `flutter-ota migrate supabase` produced a DB where clients
  received no OTA.

## 0.1.0

- Initial release of `flutter_ota_kit_supabase` as part of the flutter_ota_kit OTA toolkit.
