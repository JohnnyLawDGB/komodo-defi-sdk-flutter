import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_merge_utils.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

Transaction _perspective({required bool custodyCredit}) {
  final amount = Decimal.parse('12.5');
  return Transaction(
    id: 'tx-hash',
    internalId: 'tx-hash',
    assetId: AssetId(
      id: 'USDT-TRC20',
      name: 'Tether',
      symbol: AssetSymbol(assetConfigId: 'USDT-TRC20'),
      chainId: AssetChainId(chainId: 728126428),
      derivationPath: "m/44'/195'",
      subClass: CoinSubClass.trc20,
    ),
    balanceChanges: BalanceChanges(
      netChange: custodyCredit ? amount : -amount,
      receivedByMe: custodyCredit ? amount : Decimal.zero,
      spentByMe: custodyCredit ? Decimal.zero : amount,
      totalAmount: amount,
    ),
    timestamp: DateTime.utc(2026, 7, 10),
    confirmations: 1,
    blockHeight: 123,
    from: const ['standard-eoa'],
    to: const ['gasfree-custody'],
    txHash: 'tx-hash',
  );
}

void main() {
  test('cross-page address perspectives merge without data loss', () {
    final reconciler = TransactionListReconciler();
    final firstPage = reconciler.merge(
      existing: const [],
      incoming: [_perspective(custodyCredit: false)],
    );
    final merged = reconciler
        .merge(
          existing: firstPage,
          incoming: [_perspective(custodyCredit: true)],
        )
        .single;

    expect(merged.balanceChanges.spentByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.receivedByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.netChange, Decimal.zero);
  });

  test('re-fetching one perspective never double-counts it', () {
    final reconciler = TransactionListReconciler();
    final debit = _perspective(custodyCredit: false);
    final first = reconciler.merge(existing: const [], incoming: [debit]);
    final repeated = reconciler.merge(existing: first, incoming: [debit]);

    expect(repeated.single.balanceChanges.spentByMe, Decimal.parse('12.5'));
    expect(repeated.single.balanceChanges.netChange, Decimal.parse('-12.5'));
  });

  test('storage preserves richer cross-page address perspectives', () async {
    final storage = InMemoryTransactionStorage();
    const wallet = WalletId(
      name: 'wallet',
      pubkeyHash: 'wallet-pubkey',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );

    await storage.storeTransactions([
      _perspective(custodyCredit: false),
    ], wallet);
    await storage.storeTransactions([
      _perspective(custodyCredit: true),
    ], wallet);

    final page = await storage.getTransactions(
      _perspective(custodyCredit: false).assetId,
      wallet,
    );
    final merged = page.transactions.single;
    expect(merged.balanceChanges.spentByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.receivedByMe, Decimal.parse('12.5'));
    expect(merged.balanceChanges.netChange, Decimal.zero);
  });

  group('confirmations', () {
    final dgb = AssetId(
      id: 'DGB',
      name: 'DigiByte',
      symbol: AssetSymbol(assetConfigId: 'DGB'),
      chainId: AssetChainId(chainId: 0),
      derivationPath: null,
      subClass: CoinSubClass.utxo,
    );
    const wallet = WalletId(
      name: 'wallet',
      pubkeyHash: 'wallet-pubkey',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    );

    // A send as the V2 strategy delivers it: 0 while unconfirmed (KDF's
    // tip + 1 is dropped there). A stream event carries no confirmations
    // and defaults to 0 (tx_history_event.dart:23).
    Transaction send({required int blockHeight, required int confs}) =>
        TransactionInfo(
          txHash: 'sent-hash',
          from: const ['DMine'],
          to: const ['DThem', 'DChange'],
          myBalanceChange: '-1.0226',
          blockHeight: blockHeight,
          confirmations: confs,
          timestamp: blockHeight == 0 ? 0 : 1791100000,
          feeDetails: null,
          coin: 'DGB',
          internalId: 'sent-hash',
          spentByMe: '10',
          receivedByMe: '8.9774',
          memo: null,
        ).asTransaction(dgb);

    // What a device already stored before the fix: the pending-era tip + 1
    // max-merged with the later block height (tx1 from the 0.3.0 run).
    Transaction poisoned() => Transaction(
      id: 'sent-hash',
      internalId: 'sent-hash',
      assetId: dgb,
      balanceChanges: BalanceChanges(
        netChange: Decimal.parse('-1.0226'),
        receivedByMe: Decimal.parse('8.9774'),
        spentByMe: Decimal.parse('10'),
        totalAmount: Decimal.parse('10'),
      ),
      timestamp: DateTime.utc(2026, 10, 6),
      confirmations: 24342205,
      blockHeight: 24342204,
      from: const ['DMine'],
      to: const ['DThem', 'DChange'],
      txHash: 'sent-hash',
    );

    // Broadcast seen in the mempool, refresh, mined in 24342220, a stream
    // event, then two more refreshes.
    List<Transaction> lifecycle() => [
      send(blockHeight: 0, confs: 0),
      send(blockHeight: 0, confs: 0),
      send(blockHeight: 24342220, confs: 1),
      send(blockHeight: 24342220, confs: 0),
      send(blockHeight: 24342220, confs: 3),
      send(blockHeight: 24342220, confs: 8),
    ];

    test('a send seen while pending follows the chain afterwards', () {
      final reconciler = TransactionListReconciler();
      var merged = <Transaction>[];
      final seen = <int>[];
      for (final update in lifecycle()) {
        merged = reconciler.merge(existing: merged, incoming: [update]);
        seen.add(merged.single.confirmations);
      }
      expect(seen, [0, 0, 1, 1, 3, 8]);
    });

    test('storage never keeps the pending-era tip', () async {
      final storage = InMemoryTransactionStorage();
      final seen = <int>[];
      for (final update in lifecycle()) {
        await storage.storeTransactions([update], wallet);
        final page = await storage.getTransactions(dgb, wallet);
        seen.add(page.transactions.single.confirmations);
      }
      expect(seen, [0, 0, 1, 1, 3, 8]);
    });

    test('a stored tip-sized value heals on the next KDF refresh', () async {
      final reconciler = TransactionListReconciler();
      final stored = reconciler.merge(
        existing: const [],
        incoming: [poisoned()],
      );
      final fresh = reconciler.merge(
        existing: stored,
        incoming: [send(blockHeight: 24342204, confs: 2)],
      );
      expect(fresh.single.confirmations, 2);

      final storage = InMemoryTransactionStorage();
      await storage.storeTransactions([poisoned()], wallet);
      await storage.storeTransactions([
        send(blockHeight: 24342204, confs: 2),
      ], wallet);
      final page = await storage.getTransactions(dgb, wallet);
      expect(page.transactions.single.confirmations, 2);
    });

    // A 0.3.0-stored pending row: KDF's tip + 1 without a block.
    Transaction legacyPending() =>
        poisoned().copyWith(blockHeight: 0, confirmations: 24342220);

    test('a stored pending row with the tip stays pending', () {
      final reconciler = TransactionListReconciler();
      final stored = reconciler.merge(
        existing: const [],
        incoming: [legacyPending()],
      );
      final merged = reconciler.merge(
        existing: stored,
        incoming: [send(blockHeight: 0, confs: 0)],
      );
      expect(merged.single.confirmations, 0);
    });

    test('a stored pending row with the tip, then a stream event', () async {
      final reconciler = TransactionListReconciler();
      final stored = reconciler.merge(
        existing: const [],
        incoming: [legacyPending()],
      );
      final merged = reconciler.merge(
        existing: stored,
        incoming: [send(blockHeight: 24342220, confs: 0)],
      );
      expect(merged.single.confirmations, 0);
      expect(merged.single.blockHeight, 24342220);

      final storage = InMemoryTransactionStorage();
      await storage.storeTransactions([legacyPending()], wallet);
      await storage.storeTransactions([
        send(blockHeight: 24342220, confs: 0),
      ], wallet);
      final page = await storage.getTransactions(dgb, wallet);
      expect(page.transactions.single.confirmations, 0);
    });

    test('a stream event without confirmations keeps the known count', () {
      final reconciler = TransactionListReconciler();
      final known = reconciler.merge(
        existing: const [],
        incoming: [send(blockHeight: 24342204, confs: 5)],
      );
      final merged = reconciler.merge(
        existing: known,
        incoming: [send(blockHeight: 24342204, confs: 0)],
      );
      expect(merged.single.confirmations, 5);
    });

    test('a mined tx never merges down to 0', () async {
      final updates = [
        send(blockHeight: 24342204, confs: 0),
        send(blockHeight: 0, confs: 0),
        send(blockHeight: 24342203, confs: 0),
        send(blockHeight: 24342203, confs: 1),
      ];
      final reconciler = TransactionListReconciler();
      var merged = reconciler.merge(
        existing: const [],
        incoming: [send(blockHeight: 24342204, confs: 5)],
      );
      final storage = InMemoryTransactionStorage();
      await storage.storeTransactions([
        send(blockHeight: 24342204, confs: 5),
      ], wallet);
      for (final update in updates) {
        merged = reconciler.merge(existing: merged, incoming: [update]);
        expect(merged.single.confirmations, 5);
        await storage.storeTransactions([update], wallet);
        final page = await storage.getTransactions(dgb, wallet);
        expect(page.transactions.single.confirmations, 5);
      }
    });

    test('a confirmed row without a block (TRC20) stays confirmed', () async {
      // TronGrid TRC20 rows: blockHeight 0, confirmations 1.
      final trc20 = legacyPending().copyWith(confirmations: 1);
      final reconciler = TransactionListReconciler();
      var merged = reconciler.merge(existing: const [], incoming: [trc20]);
      merged = reconciler.merge(existing: merged, incoming: [trc20]);
      expect(merged.single.confirmations, 1);

      final storage = InMemoryTransactionStorage();
      await storage.storeTransactions([trc20], wallet);
      await storage.storeTransactions([trc20], wallet);
      final page = await storage.getTransactions(dgb, wallet);
      expect(page.transactions.single.confirmations, 1);
    });
  });
}
