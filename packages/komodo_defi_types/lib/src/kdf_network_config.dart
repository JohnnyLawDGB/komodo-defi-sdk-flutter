import 'package:komodo_defi_types/src/constants.dart';

/// Which KDF P2P network to join.
///
/// [netId] is passed to KDF as `netid`. When [seedNodes] is non-empty the SDK
/// uses exactly those seeds and never fetches or falls back to others.
class KdfNetworkConfig {
  const KdfNetworkConfig({this.netId = kDefaultNetId, this.seedNodes});

  final int netId;
  final List<String>? seedNodes;

  bool get hasExplicitSeedNodes => seedNodes != null && seedNodes!.isNotEmpty;
}
