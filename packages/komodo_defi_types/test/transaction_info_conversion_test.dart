import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  test('uses non-zero spent amount when received amount is zero', () {
    final info = TransactionInfo(
      txHash: 'hash',
      from: const ['source'],
      to: const ['recipient', 'provider'],
      myBalanceChange: '-11.5',
      blockHeight: 1,
      confirmations: 1,
      timestamp: 1,
      feeDetails: null,
      coin: 'USDT-TRC20',
      internalId: 'hash',
      spentByMe: '11.5',
      receivedByMe: '0',
      memo: null,
    );

    final transaction = info.asTransaction(
      AssetId(
        id: 'USDT-TRC20',
        name: 'Tether',
        symbol: AssetSymbol(assetConfigId: 'USDT-TRC20'),
        chainId: AssetChainId(chainId: 728126428, decimalsValue: 6),
        derivationPath: "m/44'/195'",
        subClass: CoinSubClass.trc20,
      ),
    );

    expect(transaction.balanceChanges.totalAmount.toString(), '11.5');
  });

  group('confirmations from KDF my_tx_history v2', () {
    // KDF computes `current_block + 1 - block_height`
    // (my_tx_history_v2.rs:492-496), so an unconfirmed transaction
    // (block_height 0) comes back with the chain tip + 1.
    TransactionInfo info({required int blockHeight, required int confs}) =>
        TransactionInfo(
          txHash: 'hash',
          from: const ['DMine'],
          to: const ['DThem'],
          myBalanceChange: '-1.0226',
          blockHeight: blockHeight,
          confirmations: confs,
          timestamp: 1,
          feeDetails: null,
          coin: 'DGB',
          internalId: 'hash',
          spentByMe: '10',
          receivedByMe: '8.9774',
          memo: null,
        );
    final dgb = AssetId(
      id: 'DGB',
      name: 'DigiByte',
      symbol: AssetSymbol(assetConfigId: 'DGB'),
      chainId: AssetChainId(chainId: 0),
      derivationPath: null,
      subClass: CoinSubClass.utxo,
    );

    test('an unconfirmed transaction has zero, never the chain tip', () {
      final tx = info(blockHeight: 0, confs: 24342220).asTransaction(dgb);
      expect(tx.confirmations, 0);
      expect(tx.blockHeight, 0);
    });

    test('a mined transaction keeps the KDF value', () {
      final tx = info(blockHeight: 24342204, confs: 2).asTransaction(dgb);
      expect(tx.confirmations, 2);
      expect(tx.blockHeight, 24342204);
    });
  });
}
