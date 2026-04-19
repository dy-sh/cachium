import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/providers/exchange_rate_provider.dart';
import '../../../../core/utils/balance_calculation.dart';
import '../../../../core/utils/currency_conversion.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../../categories/presentation/providers/categories_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/models/transaction.dart';

// Re-export the derived query/filter/search providers so existing callers
// that `import 'transactions_provider.dart'` keep working after the split.
export 'transaction_queries.dart';

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  final _uuid = const Uuid();

  @override
  Future<List<Transaction>> build() async {
    final repo = ref.watch(transactionRepositoryProvider);
    return repo.getAllTransactions();
  }

  /// Apply per-account balance deltas after a transaction commit. Each call
  /// goes through [AccountsNotifier.updateBalance], which serializes per
  /// account and updates both the database row and the in-memory provider
  /// state. Runs sequentially so the per-account locks chain cleanly.
  ///
  /// On failure, the transaction-table commit has already succeeded, so the
  /// caller should surface a loud error and prompt the user to refresh.
  Future<void> _applyBalanceDeltas(Map<String, double> deltas) async {
    final accountsNotifier = ref.read(accountsProvider.notifier);
    for (final entry in deltas.entries) {
      await accountsNotifier.updateBalance(entry.key, entry.value);
    }
  }

  Future<Transaction> addTransaction({
    required double amount,
    required TransactionType type,
    required String categoryId,
    required String accountId,
    String? destinationAccountId,
    String? assetId,
    bool isAcquisitionCost = false,
    String currencyCode = 'USD',
    double conversionRate = 1.0,
    double? destinationAmount,
    String mainCurrencyCode = 'USD',
    double? mainCurrencyAmount,
    required DateTime date,
    String? note,
    String? merchant,
  }) async {
    if (conversionRate <= 0 || !conversionRate.isFinite) {
      throw ValidationException.outOfRange('conversionRate', min: 0);
    }

    // Validate referenced entities exist. Await the async notifiers so a
    // cold-start race can't make a real entity look missing.
    final accounts = await ref.read(accountsProvider.future);
    final categories = await ref.read(categoriesProvider.future);
    final accountsById = {for (final a in accounts) a.id: a};
    final srcAccount = accountsById[accountId];
    if (srcAccount == null) {
      throw EntityNotFoundException(entityType: 'Account', entityId: accountId);
    }
    if (!categories.any((c) => c.id == categoryId)) {
      throw EntityNotFoundException(entityType: 'Category', entityId: categoryId);
    }

    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);

    final effectiveMainCurrencyAmount = mainCurrencyAmount ??
        (currencyCode == mainCurrencyCode
            ? amount
            : roundCurrency(amount * conversionRate));

    final transaction = Transaction(
      id: _uuid.v4(),
      amount: amount,
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
      assetId: assetId,
      isAcquisitionCost: isAcquisitionCost,
      currencyCode: currencyCode,
      conversionRate: conversionRate,
      destinationAmount: destinationAmount,
      mainCurrencyCode: mainCurrencyCode,
      mainCurrencyAmount: effectiveMainCurrencyAmount,
      date: date,
      note: note,
      merchant: merchant,
      createdAt: DateTime.now(),
    );

    // Capture account state before entering transaction to avoid race conditions
    if (type == TransactionType.transfer && destinationAccountId != null) {
      final dstAccount = accountsById[destinationAccountId];
      if (dstAccount == null) {
        throw EntityNotFoundException(
            entityType: 'Account', entityId: destinationAccountId);
      }
      if (destinationAmount == null &&
          srcAccount.currencyCode != dstAccount.currencyCode) {
        throw const ValidationException(
          message: 'Cross-currency transfer requires destinationAmount',
          field: 'destinationAmount',
          rule: 'required',
        );
      }
    }

    // Persist the transaction row first, then sync account balances. Keeping
    // balance updates outside the drift transaction avoids nesting per-account
    // locks inside drift's write zone and keeps in-memory state in sync.
    await db.transaction(() async {
      await repo.createTransaction(transaction);
    });

    await _applyBalanceDeltas(transactionDeltas(transaction));

    state = state.whenData((transactions) => [transaction, ...transactions]);

    return transaction;
  }

  Future<void> updateTransaction(Transaction transaction) async {
    // Validate referenced entities exist. Await the async notifiers so a
    // cold-start race can't make a real entity look missing.
    final accounts = await ref.read(accountsProvider.future);
    final categories = await ref.read(categoriesProvider.future);
    final accountsById = {for (final a in accounts) a.id: a};
    if (!accountsById.containsKey(transaction.accountId)) {
      throw EntityNotFoundException(entityType: 'Account', entityId: transaction.accountId);
    }
    if (!categories.any((c) => c.id == transaction.categoryId)) {
      throw EntityNotFoundException(entityType: 'Category', entityId: transaction.categoryId);
    }

    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Get original transaction to calculate balance difference
    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    final index = currentState.indexWhere((t) => t.id == transaction.id);
    if (index == -1) {
      throw EntityNotFoundException(entityType: 'Transaction', entityId: transaction.id);
    }
    final originalTransaction = currentState[index];

    // Validate cross-currency transfer before entering transaction
    if (transaction.type == TransactionType.transfer &&
        transaction.destinationAccountId != null) {
      final srcAcct = accountsById[transaction.accountId]!;
      final dstAcct = accountsById[transaction.destinationAccountId!];
      if (dstAcct == null) {
        throw EntityNotFoundException(
            entityType: 'Account', entityId: transaction.destinationAccountId!);
      }
      if (transaction.destinationAmount == null &&
          srcAcct.currencyCode != dstAcct.currencyCode) {
        throw const ValidationException(
          message: 'Cross-currency transfer requires destinationAmount',
          field: 'destinationAmount',
          rule: 'required',
        );
      }
    }

    // Combine reverse + forward deltas so each account is touched once after
    // commit, minimizing the in-flight window where DB and balance state
    // could disagree.
    final combinedDeltas = <String, double>{};
    for (final entry in reverseTransactionDeltas(originalTransaction).entries) {
      combinedDeltas.update(entry.key, (v) => v + entry.value,
          ifAbsent: () => entry.value);
    }
    for (final entry in transactionDeltas(transaction).entries) {
      combinedDeltas.update(entry.key, (v) => v + entry.value,
          ifAbsent: () => entry.value);
    }

    await db.transaction(() async {
      await repo.updateTransaction(transaction);
    });

    await _applyBalanceDeltas(combinedDeltas);

    state = state.whenData(
      (transactions) =>
          transactions.map((t) => t.id == transaction.id ? transaction : t).toList(),
    );
  }

  Future<void> deleteTransaction(String id) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Get transaction before deleting for balance reversal
    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    final deleteIndex = currentState.indexWhere((t) => t.id == id);
    if (deleteIndex == -1) {
      throw EntityNotFoundException(entityType: 'Transaction', entityId: id);
    }
    final transaction = currentState[deleteIndex];

    // Drift transaction covers transaction-row delete plus attachment/tag
    // cleanup (both repos share the same drift database, so they enlist in
    // the zone). Balance updates run after commit through the locked path.
    await db.transaction(() async {
      await repo.deleteTransaction(id);
      await ref.read(attachmentRepositoryProvider).deleteAttachmentsForTransaction(id);
      await ref.read(tagRepositoryProvider).removeTagsForTransaction(id);
    });

    await _applyBalanceDeltas(reverseTransactionDeltas(transaction));

    state = state.whenData(
      (transactions) => transactions.where((t) => t.id != id).toList(),
    );

    ref.invalidate(deletedTransactionsProvider);
  }

  /// Restore a previously soft-deleted transaction
  Future<void> restoreTransaction(Transaction transaction) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Validate referenced accounts still exist
    final sourceAccount = ref.read(accountByIdProvider(transaction.accountId));
    if (sourceAccount == null) {
      throw EntityNotFoundException(
        entityType: 'Account',
        entityId: transaction.accountId,
      );
    }
    if (transaction.type == TransactionType.transfer &&
        transaction.destinationAccountId != null) {
      final destAccount = ref.read(accountByIdProvider(transaction.destinationAccountId!));
      if (destAccount == null) {
        throw EntityNotFoundException(
          entityType: 'Account',
          entityId: transaction.destinationAccountId!,
        );
      }
    }

    await db.transaction(() async {
      await repo.restoreTransaction(transaction.id);
    });

    await _applyBalanceDeltas(transactionDeltas(transaction));

    state = state.whenData((transactions) {
      final updated = [transaction, ...transactions];
      updated.sort((a, b) => b.date.compareTo(a.date));
      return updated;
    });

    ref.invalidate(deletedTransactionsProvider);
  }

  /// Batch delete multiple transactions
  Future<void> deleteTransactions(List<String> ids) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);

    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    // Resolve transactions up front so we can compute combined deltas, and so
    // a missing id fails before any DB write.
    final toDelete = <Transaction>[];
    for (final id in ids) {
      final batchIndex = currentState.indexWhere((t) => t.id == id);
      if (batchIndex == -1) {
        throw EntityNotFoundException(entityType: 'Transaction', entityId: id);
      }
      toDelete.add(currentState[batchIndex]);
    }

    final combinedDeltas = <String, double>{};
    for (final tx in toDelete) {
      for (final entry in reverseTransactionDeltas(tx).entries) {
        combinedDeltas.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }

    await db.transaction(() async {
      for (final tx in toDelete) {
        await repo.deleteTransaction(tx.id);
        await ref.read(attachmentRepositoryProvider).deleteAttachmentsForTransaction(tx.id);
        await ref.read(tagRepositoryProvider).removeTagsForTransaction(tx.id);
      }
    });

    await _applyBalanceDeltas(combinedDeltas);

    // Update local state
    final idSet = ids.toSet();
    state = state.whenData(
      (transactions) => transactions.where((t) => !idSet.contains(t.id)).toList(),
    );

    ref.invalidate(deletedTransactionsProvider);
  }

  /// Batch restore multiple previously soft-deleted transactions
  Future<void> restoreTransactions(List<Transaction> transactionsToRestore) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);

    // Validate all referenced accounts still exist before starting
    for (final transaction in transactionsToRestore) {
      final sourceAccount = ref.read(accountByIdProvider(transaction.accountId));
      if (sourceAccount == null) {
        throw EntityNotFoundException(
          entityType: 'Account',
          entityId: transaction.accountId,
        );
      }
      if (transaction.type == TransactionType.transfer &&
          transaction.destinationAccountId != null) {
        final destAccount = ref.read(accountByIdProvider(transaction.destinationAccountId!));
        if (destAccount == null) {
          throw EntityNotFoundException(
            entityType: 'Account',
            entityId: transaction.destinationAccountId!,
          );
        }
      }
    }

    final combinedDeltas = <String, double>{};
    for (final tx in transactionsToRestore) {
      for (final entry in transactionDeltas(tx).entries) {
        combinedDeltas.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }

    await db.transaction(() async {
      for (final transaction in transactionsToRestore) {
        await repo.restoreTransaction(transaction.id);
      }
    });

    await _applyBalanceDeltas(combinedDeltas);

    // Re-insert into local state
    state = state.whenData((transactions) {
      final updated = [...transactionsToRestore, ...transactions];
      updated.sort((a, b) => b.date.compareTo(a.date));
      return updated;
    });

    ref.invalidate(deletedTransactionsProvider);
  }

  /// Refresh transactions from database
  Future<void> refresh() async {
    final repo = ref.read(transactionRepositoryProvider);
    state = AsyncData(await repo.getAllTransactions());
  }

  /// Move all transactions from one account to another
  Future<void> moveTransactionsToAccount(String fromAccountId, String toAccountId) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);
    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    final transactionsToMove = currentState.where((t) => t.accountId == fromAccountId).toList();

    if (transactionsToMove.isEmpty) return;

    // Get account currencies for cross-currency conversion
    final fromAccount = ref.read(accountByIdProvider(fromAccountId));
    final toAccount = ref.read(accountByIdProvider(toAccountId));
    final isCrossCurrency = fromAccount != null && toAccount != null &&
        fromAccount.currencyCode != toAccount.currencyCode;

    // Get exchange rate if cross-currency
    double crossRate = 1.0;
    if (isCrossCurrency) {
      crossRate = ref.read(exchangeRateProvider((
        from: fromAccount.currencyCode,
        to: toAccount.currencyCode,
      )));
    }

    // Calculate total balance effect on source account (in source currency)
    // and prepare updated transactions
    double sourceEffect = 0;
    double destEffect = 0;
    final updatedTransactions = <Transaction>[];

    for (final tx in transactionsToMove) {
      final sign = tx.type == TransactionType.income ? 1.0 : -1.0;
      // For transfers, the source debit was -amount (already applied)
      if (tx.type == TransactionType.transfer) {
        sourceEffect -= tx.amount; // Source was debited by -amount
      } else {
        sourceEffect += sign * tx.amount;
      }

      if (isCrossCurrency) {
        // Convert amount to destination currency
        final convertedAmount = roundCurrency(tx.amount * crossRate);
        final convertedDestAmount = tx.destinationAmount != null
            ? roundCurrency(tx.destinationAmount! * crossRate)
            : null;

        if (tx.type == TransactionType.transfer) {
          destEffect -= convertedAmount;
        } else {
          destEffect += sign * convertedAmount;
        }

        // Recalculate conversionRate for cross-currency move, but preserve historical mainCurrency snapshot
        final mainCurrency = ref.read(mainCurrencyCodeProvider);
        final rates = ref.read(exchangeRatesProvider).valueOrNull ?? {};
        final newConversionRate = (toAccount.currencyCode != mainCurrency && rates[toAccount.currencyCode] != null)
            ? 1.0 / rates[toAccount.currencyCode]!
            : tx.conversionRate;
        updatedTransactions.add(tx.copyWith(
          accountId: toAccountId,
          amount: convertedAmount,
          currencyCode: toAccount.currencyCode,
          conversionRate: newConversionRate,
          destinationAmount: convertedDestAmount,
          mainCurrencyCode: tx.mainCurrencyCode,
          mainCurrencyAmount: tx.mainCurrencyAmount,
        ));
      } else {
        if (tx.type == TransactionType.transfer) {
          destEffect -= tx.amount;
        } else {
          destEffect += sign * tx.amount;
        }
        updatedTransactions.add(tx.copyWith(accountId: toAccountId));
      }
    }

    await db.transaction(() async {
      for (final tx in updatedTransactions) {
        await repo.updateTransaction(tx);
      }
    });

    final moveDeltas = <String, double>{};
    moveDeltas.update(fromAccountId, (v) => v - sourceEffect,
        ifAbsent: () => -sourceEffect);
    moveDeltas.update(toAccountId, (v) => v + destEffect,
        ifAbsent: () => destEffect);
    await _applyBalanceDeltas(moveDeltas);

    // Update local state for transactions
    final updatedMap = {for (final tx in updatedTransactions) tx.id: tx};
    state = state.whenData(
      (transactions) => transactions.map((t) {
        return updatedMap[t.id] ?? t;
      }).toList(),
    );
  }

  /// Delete all transactions for a specific account and reverse balance effects
  Future<void> deleteTransactionsForAccount(String accountId) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);
    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    // Find transactions where this account is the source
    final sourceTransactions = currentState.where((t) => t.accountId == accountId).toList();
    // Find transactions where this account is the transfer destination
    final destTransactions = currentState.where(
      (t) => t.destinationAccountId == accountId && t.accountId != accountId,
    ).toList();

    // Compute deltas for accounts *other than* the one being deleted. The
    // account itself is presumed to be removed by the caller, so its own
    // balance does not need reversing.
    final combinedDeltas = <String, double>{};
    for (final tx in sourceTransactions) {
      if (tx.type == TransactionType.transfer &&
          tx.destinationAccountId != null &&
          tx.destinationAccountId != accountId) {
        final delta = -(tx.destinationAmount ?? tx.amount);
        combinedDeltas.update(tx.destinationAccountId!, (v) => v + delta,
            ifAbsent: () => delta);
      }
    }
    for (final tx in destTransactions) {
      combinedDeltas.update(tx.accountId, (v) => v + tx.amount,
          ifAbsent: () => tx.amount);
    }

    await db.transaction(() async {
      for (final tx in sourceTransactions) {
        await repo.deleteTransaction(tx.id);
        await ref.read(attachmentRepositoryProvider).deleteAttachmentsForTransaction(tx.id);
        await ref.read(tagRepositoryProvider).removeTagsForTransaction(tx.id);
      }
      for (final tx in destTransactions) {
        await repo.deleteTransaction(tx.id);
        await ref.read(attachmentRepositoryProvider).deleteAttachmentsForTransaction(tx.id);
        await ref.read(tagRepositoryProvider).removeTagsForTransaction(tx.id);
      }
    });

    await _applyBalanceDeltas(combinedDeltas);

    // Update local state — remove transactions where this account is source or destination
    final destIds = destTransactions.map((t) => t.id).toSet();
    state = state.whenData(
      (transactions) => transactions.where(
        (t) => t.accountId != accountId && !destIds.contains(t.id),
      ).toList(),
    );
  }

  /// Move all transactions from one category to another
  Future<void> moveTransactionsToCategory(String fromCategoryId, String toCategoryId) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);
    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    final transactionsToMove = currentState.where((t) => t.categoryId == fromCategoryId).toList();

    if (transactionsToMove.isEmpty) return;

    // Wrap in database transaction to prevent locking issues
    await db.transaction(() async {
      // Update transactions in database
      for (final tx in transactionsToMove) {
        final updatedTx = tx.copyWith(categoryId: toCategoryId);
        await repo.updateTransaction(updatedTx);
      }
    });

    // Update local state for transactions
    state = state.whenData(
      (transactions) => transactions.map((t) {
        if (t.categoryId == fromCategoryId) {
          return t.copyWith(categoryId: toCategoryId);
        }
        return t;
      }).toList(),
    );
  }

  /// Delete all transactions for a specific category and reverse account balances
  Future<void> deleteTransactionsForCategory(String categoryId) async {
    final repo = ref.read(transactionRepositoryProvider);
    final db = ref.read(databaseProvider);
    final currentState = state.valueOrNull;
    if (currentState == null) {
      throw RepositoryException.fetch(entityType: 'Transaction');
    }

    final transactionsToDelete = currentState.where((t) => t.categoryId == categoryId).toList();

    final combinedDeltas = <String, double>{};
    for (final tx in transactionsToDelete) {
      for (final entry in reverseTransactionDeltas(tx).entries) {
        combinedDeltas.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }

    await db.transaction(() async {
      for (final tx in transactionsToDelete) {
        await repo.deleteTransaction(tx.id);
        await ref.read(attachmentRepositoryProvider).deleteAttachmentsForTransaction(tx.id);
        await ref.read(tagRepositoryProvider).removeTagsForTransaction(tx.id);
      }
    });

    await _applyBalanceDeltas(combinedDeltas);

    // Update local state
    state = state.whenData(
      (transactions) => transactions.where((t) => t.categoryId != categoryId).toList(),
    );
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(() {
  return TransactionsNotifier();
});

final deletedTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.getAllDeletedTransactions();
});

