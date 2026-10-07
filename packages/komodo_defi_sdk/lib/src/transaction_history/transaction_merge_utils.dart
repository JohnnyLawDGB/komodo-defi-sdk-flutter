import 'dart:math';

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Shared helpers for reconciling transaction lifecycle updates in clients.
///
/// This utility keeps identity stable by internal transaction ID while still
/// supporting a Tendermint-specific pending->confirmed bridge when a matching
/// event is re-emitted with a different internal ID.
class TransactionMergeUtils {
  TransactionMergeUtils._();

  static const ListEquality<String> _listEquality = ListEquality<String>();

  /// Canonical lifecycle key for transaction list reconciliation.
  static String transactionKey(Transaction transaction) {
    return transaction.internalId;
  }

  /// Merge commonly-updated fields from [incoming] into [existing].
  static Transaction mergeTransactionFields(
    Transaction existing,
    Transaction incoming,
  ) {
    // Address-backed APIs can return one perspective of the same transfer on
    // different pages (for example Standard EOA debit first, GasFree custody
    // credit later). Merge components monotonically: repeated fetches of the
    // same perspective must not double-count, while the complementary credit
    // turns a consolidation into the correct net-zero internal transfer.
    final spent = _maxDecimal(
      existing.balanceChanges.spentByMe,
      incoming.balanceChanges.spentByMe,
    );
    final received = _maxDecimal(
      existing.balanceChanges.receivedByMe,
      incoming.balanceChanges.receivedByMe,
    );
    final totalAmount = _maxDecimal(
      existing.balanceChanges.totalAmount,
      incoming.balanceChanges.totalAmount,
    );

    return existing.copyWith(
      balanceChanges: BalanceChanges(
        netChange: received - spent,
        receivedByMe: received,
        spentByMe: spent,
        totalAmount: totalAmount,
      ),
      confirmations: _mergeConfirmations(existing, incoming),
      blockHeight: existing.blockHeight > incoming.blockHeight
          ? existing.blockHeight
          : incoming.blockHeight,
      from: <String>{...existing.from, ...incoming.from}.toList(),
      to: <String>{...existing.to, ...incoming.to}.toList(),
      txHash: incoming.txHash ?? existing.txHash,
      fee: incoming.fee ?? existing.fee,
      memo: incoming.memo ?? existing.memo,
      timestamp: existing.timestamp.isAfter(incoming.timestamp)
          ? existing.timestamp
          : incoming.timestamp,
    );
  }

  /// A count reported for a mined transaction at the known (or a newer)
  /// block height is authoritative: it is `tip + 1 - height` at the time
  /// of the fetch, so it replaces whatever was kept before. A larger kept
  /// value may be the tip + 1 that KDF reported while the transaction was
  /// unconfirmed, and keeping the maximum would freeze it.
  ///
  /// Otherwise, when either side has a block, only counts that come with
  /// a block are kept, and the larger wins: a stale re-fetch or a stream
  /// event (which carries no count) never lowers a known one. When neither
  /// side has a block the smaller wins, so a tip-sized pending count gives
  /// way to 0 while a confirmed row without a block (TronGrid TRC20,
  /// confirmations 1) keeps its count.
  static int _mergeConfirmations(Transaction existing, Transaction incoming) {
    if (incoming.blockHeight > 0 &&
        incoming.confirmations > 0 &&
        incoming.blockHeight >= existing.blockHeight) {
      return incoming.confirmations;
    }
    if (existing.blockHeight == 0 && incoming.blockHeight == 0) {
      return min(existing.confirmations, incoming.confirmations);
    }
    int withBlock(Transaction tx) => tx.blockHeight == 0 ? 0 : tx.confirmations;
    return max(withBlock(existing), withBlock(incoming));
  }

  static Decimal _maxDecimal(Decimal left, Decimal right) =>
      left >= right ? left : right;

  /// Whether [assetId] uses a Tendermint transaction lifecycle.
  static bool isTendermintAsset(AssetId assetId) {
    return assetId.subClass == CoinSubClass.tendermint ||
        assetId.subClass == CoinSubClass.tendermintToken;
  }

  /// Whether [transaction] has received an authoritative confirmation.
  static bool isConfirmed(Transaction transaction) {
    return transaction.confirmations > 0 || transaction.blockHeight > 0;
  }

  /// Whether [transaction] is still awaiting its first confirmation.
  static bool isPending(Transaction transaction) {
    return transaction.confirmations <= 0 && transaction.blockHeight == 0;
  }

  /// Whether two lifecycle records describe the same value transfer.
  static bool matchesTransferFingerprint(
    Transaction first,
    Transaction second,
  ) {
    return _listEquality.equals(first.from, second.from) &&
        _listEquality.equals(first.to, second.to) &&
        first.balanceChanges.netChange == second.balanceChanges.netChange &&
        first.balanceChanges.totalAmount == second.balanceChanges.totalAmount;
  }

  /// Finds a pending transaction key that should be replaced by [incoming].
  ///
  /// This bridge is intentionally limited to Tendermint/TendermintToken assets
  /// with exactly one fingerprint match to avoid collapsing distinct transfers
  /// that share the same hash.
  static String? findPendingReplacementKey({
    required Map<String, Transaction> byKey,
    required Transaction incoming,
  }) {
    if (!isTendermintAsset(incoming.assetId) || !isConfirmed(incoming)) {
      return null;
    }

    final txHash = incoming.txHash;
    if (txHash == null || txHash.isEmpty) {
      return null;
    }

    final matchingEntries = byKey.entries.where((entry) {
      final existing = entry.value;
      return existing.assetId.isSameAsset(incoming.assetId) &&
          isPending(existing) &&
          existing.txHash == txHash &&
          matchesTransferFingerprint(existing, incoming);
    }).toList();

    if (matchingEntries.length != 1) {
      return null;
    }

    return matchingEntries.first.key;
  }
}

/// Stateful reconciler for merging transaction update batches into a list view.
class TransactionListReconciler {
  final Map<String, DateTime> _firstSeenAtByInternalId = <String, DateTime>{};

  /// Clears internal ordering state.
  void reset() => _firstSeenAtByInternalId.clear();

  /// Merges [incoming] updates into [existing] and returns sorted results.
  List<Transaction> merge({
    required List<Transaction> existing,
    required Iterable<Transaction> incoming,
  }) {
    final byKey = <String, Transaction>{
      for (final tx in existing) TransactionMergeUtils.transactionKey(tx): tx,
    };

    for (final tx in incoming) {
      _mergeInPlace(byKey, tx);
      _firstSeenAtByInternalId.putIfAbsent(
        tx.internalId,
        () => tx.timestamp.millisecondsSinceEpoch != 0
            ? tx.timestamp
            : DateTime.now(),
      );
    }

    final merged = byKey.values.toList()..sort(_compareTransactions);
    return merged;
  }

  void _mergeInPlace(Map<String, Transaction> byKey, Transaction incoming) {
    final incomingKey = TransactionMergeUtils.transactionKey(incoming);
    final existing = byKey[incomingKey];

    if (existing != null) {
      byKey[incomingKey] = TransactionMergeUtils.mergeTransactionFields(
        existing,
        incoming,
      );
      return;
    }

    final pendingReplacementKey =
        TransactionMergeUtils.findPendingReplacementKey(
          byKey: byKey,
          incoming: incoming,
        );

    if (pendingReplacementKey != null) {
      final pending = byKey.remove(pendingReplacementKey);
      if (pending != null) {
        final mergedPending = TransactionMergeUtils.mergeTransactionFields(
          pending,
          incoming,
        ).copyWith(internalId: incoming.internalId);

        final pendingFirstSeen = _firstSeenAtByInternalId.remove(
          pendingReplacementKey,
        );
        if (pendingFirstSeen != null) {
          _firstSeenAtByInternalId.putIfAbsent(
            incoming.internalId,
            () => pendingFirstSeen,
          );
        }

        byKey[incomingKey] = mergedPending;
        return;
      }
    }

    byKey[incomingKey] = incoming;
  }

  int _compareTransactions(Transaction left, Transaction right) {
    final unconfirmedTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    final leftIsUnconfirmed = left.timestamp == unconfirmedTimestamp;
    final rightIsUnconfirmed = right.timestamp == unconfirmedTimestamp;

    if (leftIsUnconfirmed && rightIsUnconfirmed) {
      final leftFirstSeen =
          _firstSeenAtByInternalId[left.internalId] ?? unconfirmedTimestamp;
      final rightFirstSeen =
          _firstSeenAtByInternalId[right.internalId] ?? unconfirmedTimestamp;
      final compareByFirstSeen = rightFirstSeen.compareTo(leftFirstSeen);
      if (compareByFirstSeen != 0) {
        return compareByFirstSeen;
      }
      return right.internalId.compareTo(left.internalId);
    }

    if (leftIsUnconfirmed) {
      return -1;
    }

    if (rightIsUnconfirmed) {
      return 1;
    }

    return right.timestamp.compareTo(left.timestamp);
  }
}
