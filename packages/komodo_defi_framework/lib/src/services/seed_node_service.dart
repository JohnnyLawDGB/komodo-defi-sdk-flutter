import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_framework/src/config/kdf_logging_config.dart';
import 'package:komodo_defi_framework/src/config/seed_node_validator.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Service class responsible for fetching and managing seed nodes.
///
/// This class follows the Single Responsibility Principle by focusing
/// solely on seed node acquisition and management.
class SeedNodeService {
  static const String _packageName = 'komodo_defi_framework';
  static const String _seedNodesAssetPath = 'assets/config/seed_nodes.json';

  /// Gets the runtime configuration for seed node updates.
  ///
  /// This method loads the appropriate configuration for fetching seed nodes,
  /// following the same pattern as other update managers in the framework.
  static Future<AssetRuntimeUpdateConfig> _getRuntimeConfig() async {
    final configRepository = AssetRuntimeUpdateConfigRepository();
    return await configRepository.tryLoad() ?? const AssetRuntimeUpdateConfig();
  }

  /// Fetches seed nodes for [network].
  ///
  /// Explicit seeds in [network] are returned as-is. Otherwise: remote
  /// `seed-nodes.json` filtered by `network.netId`, then the bundled asset,
  /// then (only for [kDefaultNetId]) the hard-coded defaults.
  static Future<({List<String> seedNodes, int netId})> fetchSeedNodes({
    KdfNetworkConfig network = const KdfNetworkConfig(),
    bool filterForWeb = kIsWeb,
  }) {
    return fetchSeedNodesWith(
      network: network,
      filterForWeb: filterForWeb,
      remote: (netId) async {
        final config = await _getRuntimeConfig();
        final (
          seedNodes: nodes,
          netId: _,
        ) = await SeedNodeUpdater.fetchSeedNodes(
          config: config,
          netId: netId,
          filterForWeb: filterForWeb,
        );
        return SeedNodeUpdater.seedNodesToStringList(nodes);
      },
    );
  }

  /// Test seam for [fetchSeedNodes]: [remote] replaces the network fetch.
  @visibleForTesting
  static Future<({List<String> seedNodes, int netId})> fetchSeedNodesWith({
    required KdfNetworkConfig network,
    required Future<List<String>> Function(int netId) remote,
    bool filterForWeb = kIsWeb,
    AssetBundle? bundle,
  }) async {
    final netId = network.netId;
    if (network.hasExplicitSeedNodes) {
      return (
        seedNodes: List<String>.unmodifiable(network.seedNodes!),
        netId: netId,
      );
    }
    try {
      return (seedNodes: await remote(netId), netId: netId);
    } catch (e) {
      if (KdfLoggingConfig.verboseLogging) {
        debugPrint('Remote seed node fetch failed for netid $netId: $e');
        debugPrint('WARN Falling back to bundled seed nodes');
      }
    }
    try {
      final bundled = await loadBundledSeedNodes(
        netId: netId,
        filterForWeb: filterForWeb,
        bundle: bundle,
      );
      return (seedNodes: bundled, netId: netId);
    } catch (e) {
      if (netId != kDefaultNetId) {
        throw Exception('No seed nodes available for netid $netId: $e');
      }
      if (KdfLoggingConfig.verboseLogging) {
        debugPrint('Bundled peer configuration load failed');
        debugPrint('WARN Falling back to emergency seed nodes');
      }
      return (seedNodes: SeedNodeValidator.getDefaultSeedNodes(), netId: netId);
    }
  }

  /// Loads bundled seed nodes for [netId] from the framework asset package.
  ///
  /// The bundled asset is filtered the same way as the remote source: only
  /// nodes matching [netId] are accepted, and on web only WSS nodes are kept.
  static Future<List<String>> loadBundledSeedNodes({
    int netId = kDefaultNetId,
    bool filterForWeb = kIsWeb,
    AssetBundle? bundle,
  }) async {
    const assetKey = 'packages/$_packageName/$_seedNodesAssetPath';
    final content = await (bundle ?? rootBundle).loadString(assetKey);
    var seedNodes = SeedNode.fromJsonList(
      jsonListFromString(content),
    ).where((node) => node.netId == netId).toList();

    if (filterForWeb && kIsWeb) {
      seedNodes = seedNodes.where((node) => node.wss).toList();
    }

    if (seedNodes.isEmpty) {
      throw Exception('No bundled seed nodes found for netid $netId');
    }

    return SeedNodeUpdater.seedNodesToStringList(seedNodes);
  }

  /// Gets seed nodes based on configuration preferences.
  ///
  /// This is a convenience method that determines the appropriate seed nodes
  /// based on P2P settings and provided seed nodes.
  ///
  /// Returns:
  /// - `null` if P2P is disabled
  /// - Provided [seedNodes] if they are specified
  /// - Remote seed nodes if [fetchRemote] is true
  /// - Default seed nodes as fallback
  static Future<List<String>?> getSeedNodes({
    List<String>? seedNodes,
    bool? disableP2p,
    bool fetchRemote = true,
  }) async {
    // If P2P is disabled, no seed nodes are needed
    if (disableP2p ?? false) {
      return null;
    }

    // Use explicitly provided seed nodes if available
    if (seedNodes != null && seedNodes.isNotEmpty) {
      return seedNodes;
    }

    // Fetch remote seed nodes or use defaults
    if (fetchRemote) {
      final result = await fetchSeedNodes();
      return result.seedNodes;
    }

    try {
      return await loadBundledSeedNodes();
    } catch (_) {
      return SeedNodeValidator.getDefaultSeedNodes();
    }
  }
}
