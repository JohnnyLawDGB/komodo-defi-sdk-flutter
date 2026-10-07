import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Factory for creating appropriate transaction history strategies
class TransactionHistoryStrategyFactory {
  TransactionHistoryStrategyFactory(
    PubkeyManager pubkeyManager,
    KomodoDefiLocalAuth auth, {
    List<TransactionHistoryStrategy>? strategies,
    bool Function(AssetId assetId)? includeGaslessCustody,
  }) : _strategies =
           strategies ??
           [
             EtherscanTransactionStrategy(pubkeyManager: pubkeyManager),
             // Ordered after the proxy strategy so chains the proxy already
             // serves keep using it, and before the legacy strategy so the
             // chains it does not serve stop falling through to a KDF history
             // store that activation leaves disabled for every EVM asset.
             BlockscoutTransactionStrategy(pubkeyManager: pubkeyManager),
             TronGridTransactionStrategy(
               pubkeyManager: pubkeyManager,
               includeGaslessCustody: includeGaslessCustody,
             ),
             V2TransactionStrategy(auth),
             const LegacyTransactionStrategy(),
             const ZhtlcTransactionStrategy(),
           ];

  final List<TransactionHistoryStrategy> _strategies;

  TransactionHistoryStrategy forAsset(Asset asset) {
    final strategy = _strategies.firstWhere(
      (strategy) => strategy.supportsAsset(asset),
      orElse: () =>
          throw UnsupportedError('No strategy found for asset ${asset.id.id}'),
    );

    return strategy;
  }
}

/// Strategy for fetching transaction history using the v2 API
class V2TransactionStrategy extends TransactionHistoryStrategy {
  const V2TransactionStrategy(this._auth);

  final KomodoDefiLocalAuth _auth;

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  // TODO: Consider for the future how multi-account support will be handled.
  // The HistoryTarget could be added to the abstract strategy, but only if
  // it's applicable to all/most strategies.
  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
    // {required HistoryTarget? target,}
  ) async {
    validatePagination(pagination);

    final isHdWallet = (await _auth.currentUser)?.isHd ?? false;

    final response = await switch (pagination) {
      final PagePagination p => client.rpc.transactionHistory.myTxHistory(
        coin: asset.id.id,
        limit: p.itemsPerPage,
        pagingOptions: Pagination(pageNumber: p.pageNumber),
        target: isHdWallet
            ? const HdHistoryTarget.accountId(0)
            : IguanaHistoryTarget(),
      ),
      final TransactionBasedPagination t =>
        client.rpc.transactionHistory.myTxHistory(
          coin: asset.id.id,
          limit: t.itemCount,
          pagingOptions: Pagination(fromId: t.fromId),
          target: isHdWallet
              ? const HdHistoryTarget.accountId(0)
              : IguanaHistoryTarget(),
        ),
      _ => throw UnsupportedError(
        'Pagination mode ${pagination.runtimeType} not supported',
      ),
    };
    return _withoutTipConfirmations(response);
  }

  /// KDF's my_tx_history v2 returns `current_block + 1 - block_height`
  /// (my_tx_history_v2.rs), which is the chain tip + 1 for an unconfirmed
  /// transaction (block_height 0). Without a block there are none.
  static MyTxHistoryResponse _withoutTipConfirmations(
    MyTxHistoryResponse response,
  ) {
    if (!response.transactions.any(
      (tx) => tx.blockHeight == 0 && tx.confirmations != 0,
    )) {
      return response;
    }
    return MyTxHistoryResponse(
      mmrpc: response.mmrpc,
      currentBlock: response.currentBlock,
      fromId: response.fromId,
      limit: response.limit,
      skipped: response.skipped,
      syncStatus: response.syncStatus,
      total: response.total,
      totalPages: response.totalPages,
      pageNumber: response.pageNumber,
      pagingOptions: response.pagingOptions,
      transactions: [
        for (final tx in response.transactions)
          tx.blockHeight == 0 && tx.confirmations != 0
              ? TransactionInfo(
                  txHash: tx.txHash,
                  from: tx.from,
                  to: tx.to,
                  myBalanceChange: tx.myBalanceChange,
                  blockHeight: 0,
                  confirmations: 0,
                  timestamp: tx.timestamp,
                  feeDetails: tx.feeDetails,
                  coin: tx.coin,
                  internalId: tx.internalId,
                  memo: tx.memo,
                  spentByMe: tx.spentByMe,
                  receivedByMe: tx.receivedByMe,
                  transactionFee: tx.transactionFee,
                )
              : tx,
      ],
    );
  }

  static const List<Type> _supportedProtocols = [
    UtxoProtocol,
    QtumProtocol,
    TendermintProtocol,
  ];

  @override
  bool supportsAsset(Asset asset) =>
      _supportedProtocols.any((type) => asset.protocol.runtimeType == type);

  @override
  bool requiresKdfTransactionHistory(Asset asset) => true;
}

/// Strategy for fetching transaction history using the legacy API
class LegacyTransactionStrategy extends TransactionHistoryStrategy {
  const LegacyTransactionStrategy();

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) async {
    validatePagination(pagination);

    return switch (pagination) {
      final PagePagination p => client.rpc.transactionHistory.myTxHistoryLegacy(
        coin: asset.id.id,
        limit: p.itemsPerPage,
        pageNumber: p.pageNumber,
      ),
      final TransactionBasedPagination t =>
        client.rpc.transactionHistory.myTxHistoryLegacy(
          coin: asset.id.id,
          limit: t.itemCount,
          fromId: t.fromId,
        ),
      _ => throw UnsupportedError(
        'Pagination mode ${pagination.runtimeType} not supported',
      ),
    };
  }

  @override
  bool supportsAsset(Asset asset) => asset.protocol is! ZhtlcProtocol;

  @override
  bool requiresKdfTransactionHistory(Asset asset) => true;
}

/// Strategy for fetching ZHTLC transaction history

///
