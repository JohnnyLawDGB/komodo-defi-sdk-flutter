import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class _NullRepo extends AssetRuntimeUpdateConfigRepository {
  @override
  Future<AssetRuntimeUpdateConfig?> tryLoad() async => null;
}

class _OkRepo extends AssetRuntimeUpdateConfigRepository {
  _OkRepo(this.c);
  final AssetRuntimeUpdateConfig c;
  @override
  Future<AssetRuntimeUpdateConfig?> tryLoad() async => c;
}

void main() {
  test(
    'missing bundled config throws instead of using GLEECBTC defaults',
    () async {
      await expectLater(
        requireRuntimeConfig(_NullRepo()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('build_config.json'),
          ),
        ),
      );
    },
  );

  test('loaded config is returned unchanged', () async {
    const c = AssetRuntimeUpdateConfig(coinsRepoBranch: 'digibyte/main');
    expect(await requireRuntimeConfig(_OkRepo(c)), same(c));
  });
}
