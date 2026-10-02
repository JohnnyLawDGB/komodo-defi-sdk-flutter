import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

void main() {
  test('mnemonic word count defaults to KDF and survives copyWith', () {
    const c = KomodoDefiSdkConfig();
    expect(c.mnemonicWordCount, isNull);
    final c24 = c.copyWith(mnemonicWordCount: 24);
    expect(c24.mnemonicWordCount, 24);
    expect(c24.copyWith().mnemonicWordCount, 24);
  });
}
