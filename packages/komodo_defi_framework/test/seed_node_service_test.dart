import 'package:flutter/services.dart' show AssetBundle, ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/config/seed_node_validator.dart';
import 'package:komodo_defi_framework/src/services/seed_node_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _FakeBundle extends AssetBundle {
  _FakeBundle(this.map);

  final Map<String, String> map;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      map[key] ?? (throw StateError('Asset not found: $key'));

  @override
  void evict(String key) {}
}

void main() {
  group('SeedNodeService.loadBundledSeedNodes', () {
    test('filters bundled seed nodes by the current net id', () async {
      final bundle = _FakeBundle({
        'packages/komodo_defi_framework/assets/config/seed_nodes.json': '''
[
  {
    "name": "seed-node-1",
    "host": "seed01.kmdefi.net",
    "type": "domain",
    "wss": true,
    "netid": 6133,
    "contact": [{"email": ""}]
  },
  {
    "name": "seed-node-2",
    "host": "seed02.kmdefi.net",
    "type": "domain",
    "wss": true,
    "netid": 8762,
    "contact": [{"email": ""}]
  }
]
''',
      });

      final seedNodes = await SeedNodeService.loadBundledSeedNodes(
        bundle: bundle,
      );

      expect(seedNodes, equals(const ['seed01.kmdefi.net']));
    });
  });

  group('SeedNodeService with a custom network', () {
    test(
      'explicit seeds are returned as-is with the configured netId',
      () async {
        final result = await SeedNodeService.fetchSeedNodes(
          network: const KdfNetworkConfig(
            netId: 2014,
            seedNodes: ['seed1.digiscope.me'],
          ),
        );
        expect(result.seedNodes, ['seed1.digiscope.me']);
        expect(result.netId, 2014);
      },
    );

    test('bundled seeds are filtered by the requested netId', () async {
      final bundle = _FakeBundle({
        'packages/komodo_defi_framework/assets/config/seed_nodes.json': '''
[
  {"name":"dgb-seed-1","host":"seed1.digiscope.me","type":"domain","wss":false,"netid":2014,"contact":[{"email":""}]},
  {"name":"kmd","host":"seed01.kmdefi.net","type":"domain","wss":true,"netid":6133,"contact":[{"email":""}]}
]
''',
      });
      final seeds = await SeedNodeService.loadBundledSeedNodes(
        netId: 2014,
        bundle: bundle,
      );
      expect(seeds, ['seed1.digiscope.me']);
    });

    test('never falls back to 6133 defaults for a custom netId', () async {
      final bundle = _FakeBundle({}); // no bundled asset
      await expectLater(
        SeedNodeService.fetchSeedNodesWith(
          network: const KdfNetworkConfig(netId: 2014),
          remote: (netId) async => throw Exception('offline'),
          bundle: bundle,
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'msg', contains('2014')),
        ),
      );
    });

    test('explicit seeds never trigger a remote fetch', () async {
      final result = await SeedNodeService.fetchSeedNodesWith(
        network: const KdfNetworkConfig(
          netId: 2014,
          seedNodes: ['seed1.digiscope.me'],
        ),
        remote: (netId) async => throw StateError('remote must not be called'),
      );
      expect(result.seedNodes, ['seed1.digiscope.me']);
      expect(result.netId, 2014);
    });

    test('default network falls back to the default seed nodes', () async {
      final result = await SeedNodeService.fetchSeedNodesWith(
        network: const KdfNetworkConfig(),
        remote: (netId) async => throw Exception('offline'),
        bundle: _FakeBundle({}),
      );
      expect(result.seedNodes, SeedNodeValidator.getDefaultSeedNodes());
      expect(result.netId, kDefaultNetId);
    });
  });
}
