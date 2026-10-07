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

  group('asTransaction confirmations', () {
    TransactionInfo info({required int blockHeight, required int confs}) =>
        TransactionInfo(
          txHash: 'hash',
          from: const ['source'],
          to: const ['recipient'],
          myBalanceChange: '-1.5',
          blockHeight: blockHeight,
          confirmations: confs,
          timestamp: 1,
          feeDetails: null,
          coin: 'COIN',
          internalId: 'hash',
          spentByMe: '1.5',
          receivedByMe: '0',
          memo: null,
        );
    final coin = AssetId(
      id: 'COIN',
      name: 'Coin',
      symbol: AssetSymbol(assetConfigId: 'COIN'),
      chainId: AssetChainId(chainId: 0),
      derivationPath: null,
      subClass: CoinSubClass.utxo,
    );

    // TronGrid TRC20 rows are confirmed with the block unknown
    // (tronscan_transaction_history_strategy.dart, blockHeight 0 and
    // confirmations 1). The KDF tip fix lives in the V2 strategy.
    test('a confirmed row without a block keeps its count', () {
      final tx = info(blockHeight: 0, confs: 1).asTransaction(coin);
      expect(tx.confirmations, 1);
      expect(tx.blockHeight, 0);
    });

    test('a mined row keeps its count', () {
      final tx = info(blockHeight: 24342204, confs: 2).asTransaction(coin);
      expect(tx.confirmations, 2);
      expect(tx.blockHeight, 24342204);
    });
  });
}
