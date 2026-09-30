import 'package:komodo_coin_updates/src/runtime_update_config/asset_runtime_update_config_repository.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Loads the bundled runtime config or fails loudly.
///
/// DigiByte fork: the built-in `AssetRuntimeUpdateConfig()` defaults point at GLEECBTC/coins.
/// Falling back to them would silently switch a DigiByte build to another project's coin list,
/// so a missing or unreadable `build_config.json` is a fatal packaging error instead.
Future<AssetRuntimeUpdateConfig> requireRuntimeConfig(
  AssetRuntimeUpdateConfigRepository repo,
) async {
  final config = await repo.tryLoad();
  if (config == null) {
    throw StateError(
      'packages/komodo_defi_framework/app_build/build_config.json is missing or invalid; '
      'refusing to fall back to upstream coin configs.',
    );
  }
  return config;
}
