import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Records what KDF would be started with; never starts anything.
class _RecordingOperations implements IKdfOperations {
  final startParams = <JsonMap>[];

  @override
  Future<KdfStartupResult> kdfMain(JsonMap params, {int? logLevel}) async {
    startParams.add(params);
    return KdfStartupResult.ok;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const rpcPassword = 'Rpc-Pass-1!';
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('kdf-host-port-');
  });

  tearDown(() async {
    await home.delete(recursive: true);
  });

  Future<KdfStartupConfig> startupOn(int rpcPort) =>
      KdfStartupConfig.generateWithDefaults(
        walletName: 'w',
        walletPassword: 'p',
        enableHd: false,
        rpcPassword: rpcPassword,
        rpcPort: rpcPort,
        userHome: home.path,
        dbDir: home.path,
        coinsPath: 'coins',
        disableP2p: true,
      );

  test('a local KDF is started on the host config port', () async {
    final operations = _RecordingOperations();
    final framework = KomodoDefiFramework.createWithOperations(
      hostConfig: LocalConfig(
        https: false,
        rpcPassword: rpcPassword,
        port: 41234,
      ),
      kdfOperations: operations,
    );
    addTearDown(framework.dispose);

    await framework.startKdf(await startupOn(41234));

    expect(operations.startParams.single['rpcport'], 41234);
  });

  test(
    'a local KDF is never started on a port the client does not dial',
    () async {
      final operations = _RecordingOperations();
      final framework = KomodoDefiFramework.createWithOperations(
        hostConfig: LocalConfig(
          https: false,
          rpcPassword: rpcPassword,
          port: 41234,
        ),
        kdfOperations: operations,
      );
      addTearDown(framework.dispose);

      await expectLater(
        framework.startKdf(await startupOn(kDefaultKdfRpcPort)),
        throwsArgumentError,
      );
      expect(operations.startParams, isEmpty);
    },
  );
}
