import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_service.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Answers a KDF start that sends no wallet password with [noAuthResult] and
/// one that does with [walletResult].
class _StartupKdfOperations implements IKdfOperations {
  _StartupKdfOperations({
    required this.noAuthResult,
    required this.walletResult,
  });

  final KdfStartupResult noAuthResult;
  final KdfStartupResult walletResult;
  final startParams = <Map<String, dynamic>>[];
  bool _running = false;

  @override
  String get operationsName => 'network startup fake';

  @override
  Future<KdfStartupResult> kdfMain(
    Map<String, dynamic> params, {
    int? logLevel,
  }) async {
    startParams.add(params);
    final result = params.containsKey('wallet_password')
        ? walletResult
        : noAuthResult;
    _running = result.isOk;
    return result;
  }

  @override
  Future<MainStatus> kdfMainStatus() async =>
      _running ? MainStatus.rpcIsUp : MainStatus.notRunning;

  @override
  Future<StopStatus> kdfStop() async {
    final wasRunning = _running;
    _running = false;
    return wasRunning ? StopStatus.ok : StopStatus.notRunning;
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<String?> version() async => _running ? 'test-version' : null;

  @override
  Future<Map<String, dynamic>> mm2Rpc(Map<String, dynamic> request) async =>
      switch (request['method']) {
        'get_wallet_names' => {
          'mmrpc': '2.0',
          'result': {'wallet_names': <String>[], 'activated_wallet': null},
        },
        'stream::shutdown_signal::enable' => {
          'mmrpc': '2.0',
          'result': {'streamer_id': 'test-stream'},
        },
        _ => {'mmrpc': '2.0', 'result': <String, dynamic>{}},
      };

  @override
  Future<void> validateSetup() async {}

  @override
  Future<bool> isAvailable(IKdfHostConfig hostConfig) async => true;

  @override
  void resetHttpClient() {}

  @override
  void dispose() {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testHome;

  setUpAll(() async {
    testHome = await Directory.systemTemp.createTemp('kdf-network-startup-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => testHome.path,
    );
    // Read the existing source assets without running build transformers.
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key.endsWith('app_build/build_config.json')) {
        // Force the local seed-node fallback without a network request.
        return ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode(
              '{"coins":{"coins_repo_content_url":"http://[",'
              '"cdn_branch_mirrors":{}}}',
            ),
          ),
        );
      }
      if (!key.startsWith('packages/')) return null;
      final source = File('../${key.substring('packages/'.length)}');
      if (!source.existsSync()) return null;
      return ByteData.sublistView(await source.readAsBytes());
    });
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    await testHome.delete(recursive: true);
  });

  setUp(() {
    const options = AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
      allowWeakPassword: true,
    );
    final storedUser = KdfUser(
      walletId: WalletId.fromName('test-wallet', options),
      isBip39Seed: true,
    );
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'user_test-wallet': jsonEncode(storedUser.toJson()),
    });
  });

  test('no-auth KDF start uses the configured DigiByte network', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.initError,
      walletResult: KdfStartupResult.ok,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
      network: const KdfNetworkConfig(
        netId: 2014,
        seedNodes: ['seed1.digiscope.me'],
      ),
    );
    addTearDown(service.dispose);

    await expectLater(service.getUsers(), throwsA(isA<AuthException>()));

    final params = operations.startParams.single;
    expect(params['netid'], 2014);
    expect(params['seednodes'], ['seed1.digiscope.me']);
  });

  test('wallet KDF start uses the configured DigiByte network', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.ok,
      walletResult: KdfStartupResult.initError,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
      network: const KdfNetworkConfig(
        netId: 2014,
        seedNodes: ['seed1.digiscope.me'],
      ),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.signIn(
        walletName: 'test-wallet',
        password: 'Qz7!sentinel-Wv4#',
        options: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          allowWeakPassword: true,
        ),
      ),
      throwsA(isA<AuthException>()),
    );

    final walletStarts = operations.startParams
        .where((p) => p.containsKey('wallet_password'))
        .toList();
    expect(walletStarts, isNotEmpty);
    for (final params in walletStarts) {
      expect(params['netid'], 2014);
      expect(params['seednodes'], ['seed1.digiscope.me']);
    }
  });

  test('default network is unchanged (6133)', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.initError,
      walletResult: KdfStartupResult.ok,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
    );
    addTearDown(service.dispose);

    await expectLater(service.getUsers(), throwsA(isA<AuthException>()));
    final params = operations.startParams.single;
    expect(params['netid'], kDefaultNetId);
    expect(params['seednodes'], isNotEmpty);
    expect(params['seednodes'], isNot(contains('seed1.digiscope.me')));
  });

  test('wallet creation asks KDF for the configured word count', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.ok,
      walletResult: KdfStartupResult.initError,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
      mnemonicWordCount: 24,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.register(
        walletName: 'new-wallet',
        password: 'Qz7!sentinel-Wv4#',
        options: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          allowWeakPassword: true,
        ),
      ),
      throwsA(isA<AuthException>()),
    );

    final walletStarts = operations.startParams
        .where((p) => p.containsKey('wallet_password'))
        .toList();
    expect(walletStarts, isNotEmpty);
    for (final params in walletStarts) {
      expect(params['word_count'], 24);
      expect(params.containsKey('passphrase'), isFalse);
    }
  });

  test('word_count is omitted unless configured', () async {
    final hostConfig = LocalConfig(https: false, rpcPassword: 'rpc-pass');
    final operations = _StartupKdfOperations(
      noAuthResult: KdfStartupResult.ok,
      walletResult: KdfStartupResult.initError,
    );
    final service = KdfAuthService(
      KomodoDefiFramework.createWithOperations(
        hostConfig: hostConfig,
        kdfOperations: operations,
      ),
      hostConfig,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.signIn(
        walletName: 'test-wallet',
        password: 'Qz7!sentinel-Wv4#',
        options: const AuthOptions(
          derivationMethod: DerivationMethod.hdWallet,
          allowWeakPassword: true,
        ),
      ),
      throwsA(isA<AuthException>()),
    );

    expect(operations.startParams, isNotEmpty);
    for (final params in operations.startParams) {
      expect(params.containsKey('word_count'), isFalse);
    }
  });

  test(
    'no-auth and wallet KDF starts listen on the host config port',
    () async {
      // The client dials hostConfig.rpcUrl; KDF must bind exactly that port,
      // or the RPC password goes to whatever else listens there.
      final hostConfig = LocalConfig(
        https: false,
        rpcPassword: 'rpc-pass',
        port: 41234,
      );
      final operations = _StartupKdfOperations(
        noAuthResult: KdfStartupResult.ok,
        walletResult: KdfStartupResult.initError,
      );
      final service = KdfAuthService(
        KomodoDefiFramework.createWithOperations(
          hostConfig: hostConfig,
          kdfOperations: operations,
        ),
        hostConfig,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.signIn(
          walletName: 'test-wallet',
          password: 'Qz7!sentinel-Wv4#',
          options: const AuthOptions(
            derivationMethod: DerivationMethod.hdWallet,
            allowWeakPassword: true,
          ),
        ),
        throwsA(isA<AuthException>()),
      );

      expect(hostConfig.rpcUrl.port, 41234);
      expect(
        operations.startParams.map((p) => p.containsKey('wallet_password')),
        containsAll([false, true]),
      );
      for (final params in operations.startParams) {
        expect(params['rpcport'], 41234);
        expect(params['rpc_password'] == hostConfig.rpcPassword, isTrue);
      }
    },
  );
}
