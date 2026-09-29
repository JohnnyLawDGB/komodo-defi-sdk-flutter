import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  test('defaults to the upstream netid with no explicit seeds', () {
    const c = KdfNetworkConfig();
    expect(c.netId, kDefaultNetId);
    expect(c.hasExplicitSeedNodes, isFalse);
  });

  test('explicit seeds are detected; empty list is not explicit', () {
    expect(
      const KdfNetworkConfig(
        netId: 2014,
        seedNodes: ['seed1.digiscope.me'],
      ).hasExplicitSeedNodes,
      isTrue,
    );
    expect(
      const KdfNetworkConfig(netId: 2014, seedNodes: []).hasExplicitSeedNodes,
      isFalse,
    );
  });
}
