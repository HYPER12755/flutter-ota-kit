library;

// Re-export core types for convenience.
export 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show
        Bundle,
        GetBundlesArgs,
        Platform,
        UpdateInfo,
        semverSatisfies;

// Plugin-core types.
export 'src/types.dart';

// Helpers.
export 'src/calculate_pagination.dart';
export 'src/query_bundles.dart';
export 'src/paginate_bundles.dart';
export 'src/filter_compatible_app_versions.dart';
export 'src/parse_storage_uri.dart';
export 'src/content_addressed_assets.dart';
export 'src/compression_format.dart';
export 'src/storage_profile.dart';
export 'src/create_storage_key_builder.dart';
export 'src/is_object.dart';
export 'src/asset_storage_layout.dart';
export 'src/bundle_storage_layout.dart';
export 'src/legacy_asset_storage_layout.dart';

// Factories.
export 'src/bundle_unit_of_work.dart';
export 'src/bundle_unit_of_work_store.dart'
    show getRequestBundleUnitOfWork, clearUnitOfWorkStore;
export 'src/request_update_bundle_state.dart';
export 'src/create_database_plugin.dart';
export 'src/create_blob_database_plugin.dart';
export 'src/create_storage_plugin.dart';
export 'src/generate_min_bundle_id.dart';
export 'src/uuidv7.dart';
export 'src/get_update_info.dart';
export 'src/resolve_update_info_from_bundles.dart';
export 'src/resolve_update_info_from_bundles.dart';
