import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

void main() {
  test('asset auto-update defaults on and can be switched off', () {
    const c = KomodoDefiSdkConfig();
    expect(c.enableAssetAutoUpdate, isTrue);
    final off = c.copyWith(enableAssetAutoUpdate: false);
    expect(off.enableAssetAutoUpdate, isFalse);
    expect(off.copyWith().enableAssetAutoUpdate, isFalse);
  });
}
