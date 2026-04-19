import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/database_providers.dart';
import '../../data/models/advanced_transaction_filter.dart';
import '../../data/models/transaction.dart';
import 'transactions_provider.dart';

// Filter, search, and derived-view providers for the transactions list.
// These were extracted from transactions_provider.dart so that file can
// focus on the TransactionsNotifier CRUD surface. Every provider here is a
// pure read over `transactionsProvider` — no mutating state — which is why
// the split is safe and doesn't change behavior.

enum TransactionFilter { all, income, expense, transfer }

final transactionFilterProvider = StateProvider<TransactionFilter>((ref) {
  return TransactionFilter.all;
});

class AdvancedTransactionFilterNotifier extends Notifier<AdvancedTransactionFilter> {
  @override
  AdvancedTransactionFilter build() => const AdvancedTransactionFilter();

  void setAmountRange({double? min, double? max}) {
    state = state.copyWith(
      minAmount: min,
      clearMinAmount: min == null,
      maxAmount: max,
      clearMaxAmount: max == null,
    );
  }

  void setDateRange({DateTime? start, DateTime? end}) {
    state = state.copyWith(
      startDate: start,
      clearStartDate: start == null,
      endDate: end,
      clearEndDate: end == null,
    );
  }

  void toggleCategory(String categoryId) {
    final current = Set<String>.from(state.selectedCategoryIds);
    if (current.contains(categoryId)) {
      current.remove(categoryId);
    } else {
      current.add(categoryId);
    }
    state = state.copyWith(selectedCategoryIds: current);
  }

  void setCategories(Set<String> ids) {
    state = state.copyWith(selectedCategoryIds: ids);
  }

  void toggleAccount(String accountId) {
    final current = Set<String>.from(state.selectedAccountIds);
    if (current.contains(accountId)) {
      current.remove(accountId);
    } else {
      current.add(accountId);
    }
    state = state.copyWith(selectedAccountIds: current);
  }

  void setAccounts(Set<String> ids) {
    state = state.copyWith(selectedAccountIds: ids);
  }

  void clearAll() {
    state = const AdvancedTransactionFilter();
  }
}

final advancedTransactionFilterProvider =
    NotifierProvider<AdvancedTransactionFilterNotifier, AdvancedTransactionFilter>(() {
  return AdvancedTransactionFilterNotifier();
});

final activeFilterCountProvider = Provider<int>((ref) {
  return ref.watch(advancedTransactionFilterProvider).activeFilterCount;
});

final filteredTransactionsProvider = Provider<AsyncValue<List<Transaction>>>((ref) {
  final transactionsAsync = ref.watch(transactionsProvider);
  final filter = ref.watch(transactionFilterProvider);
  final advanced = ref.watch(advancedTransactionFilterProvider);

  return transactionsAsync.whenData((transactions) {
    var result = transactions;

    // Type filter
    switch (filter) {
      case TransactionFilter.income:
        result = result.where((t) => t.type == TransactionType.income).toList();
      case TransactionFilter.expense:
        result = result.where((t) => t.type == TransactionType.expense).toList();
      case TransactionFilter.transfer:
        result = result.where((t) => t.type == TransactionType.transfer).toList();
      case TransactionFilter.all:
        break;
    }

    // Advanced filters
    if (advanced.isActive) {
      result = result.where((t) {
        if (advanced.minAmount != null && t.amount < advanced.minAmount!) return false;
        if (advanced.maxAmount != null && t.amount > advanced.maxAmount!) return false;
        if (advanced.startDate != null && t.date.isBefore(advanced.startDate!)) return false;
        if (advanced.endDate != null) {
          final endOfDay = DateTime(advanced.endDate!.year, advanced.endDate!.month, advanced.endDate!.day, 23, 59, 59);
          if (t.date.isAfter(endOfDay)) return false;
        }
        if (advanced.selectedCategoryIds.isNotEmpty && !advanced.selectedCategoryIds.contains(t.categoryId)) return false;
        if (advanced.selectedAccountIds.isNotEmpty && !advanced.selectedAccountIds.contains(t.accountId)) return false;
        return true;
      }).toList();
    }

    return result;
  });
});

final groupedTransactionsProvider = Provider<AsyncValue<List<TransactionGroup>>>((ref) {
  final filteredAsync = ref.watch(filteredTransactionsProvider);

  return filteredAsync.whenData((transactions) {
    // Sort by date descending
    final sorted = List<Transaction>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    // Group by date
    final Map<DateTime, List<Transaction>> grouped = {};
    for (final tx in sorted) {
      final dateKey = DateTime(tx.date.year, tx.date.month, tx.date.day);
      grouped.putIfAbsent(dateKey, () => []).add(tx);
    }

    return grouped.entries
        .map((e) => TransactionGroup(date: e.key, transactions: e.value))
        .toList();
  });
});

/// Five most recent transactions for the home dashboard.
///
/// Prefers the in-memory transactions list when it has already loaded —
/// that's the steady-state path and avoids redundant DB work. On cold start,
/// when [transactionsProvider] hasn't resolved yet, falls back to a paged
/// DB fetch so the home screen can paint without waiting for the full list.
final recentTransactionsProvider =
    FutureProvider<List<Transaction>>((ref) async {
  final transactionsAsync = ref.watch(transactionsProvider);
  final loaded = transactionsAsync.valueOrNull;
  if (loaded != null) {
    final sorted = List<Transaction>.from(loaded)
      ..sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(5).toList();
  }
  if (transactionsAsync.hasError) {
    throw transactionsAsync.error!;
  }
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.getTransactionsPaged(limit: 5);
});

final transactionDateBoundsProvider = Provider<({DateTime? earliest, DateTime? latest})>((ref) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null || transactions.isEmpty) {
    return (earliest: null, latest: null);
  }
  DateTime earliest = transactions.first.date;
  DateTime latest = transactions.first.date;
  for (final tx in transactions) {
    if (tx.date.isBefore(earliest)) earliest = tx.date;
    if (tx.date.isAfter(latest)) latest = tx.date;
  }
  return (earliest: earliest, latest: latest);
});

final transactionSearchQueryProvider = StateProvider<String>((ref) => '');

/// Indexed map of all transactions by ID for O(1) lookups.
final transactionMapProvider = Provider<Map<String, Transaction>>((ref) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return {};
  return {for (final t in transactions) t.id: t};
});

final transactionByIdProvider = Provider.autoDispose.family<Transaction?, String>((ref, id) {
  return ref.watch(transactionMapProvider)[id];
});

final transactionsByAccountProvider = Provider.family<List<Transaction>, String>((ref, accountId) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return [];
  return transactions
      .where((t) => t.accountId == accountId || t.destinationAccountId == accountId)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

final transactionCountByAccountProvider = Provider.family<int, String>((ref, accountId) {
  return ref.watch(transactionsByAccountProvider(accountId)).length;
});

/// This-month income and expense totals for an account, in that account's
/// native currency. Memoized: only recomputes when the transactions list
/// changes. Use instead of folding over transactions in widget builds.
class AccountMonthlyStats {
  final double income;
  final double expense;
  const AccountMonthlyStats({required this.income, required this.expense});
  static const zero = AccountMonthlyStats(income: 0, expense: 0);
}

final accountMonthlyStatsProvider =
    Provider.family<AccountMonthlyStats, String>((ref, accountId) {
  final transactions = ref.watch(transactionsByAccountProvider(accountId));
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  double income = 0;
  double expense = 0;
  for (final tx in transactions) {
    // Only count when this account is the source — destination-only legs are
    // excluded so transfers don't inflate the "this-account" view.
    if (tx.accountId != accountId) continue;
    if (tx.date.isBefore(monthStart)) continue;
    if (tx.type == TransactionType.income) {
      income += tx.amount;
    } else if (tx.type == TransactionType.expense) {
      expense += tx.amount;
    }
  }
  return AccountMonthlyStats(income: income, expense: expense);
});

final transactionsByCategoryProvider = Provider.family<List<Transaction>, String>((ref, categoryId) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return [];
  return transactions.where((t) => t.categoryId == categoryId).toList();
});

final transactionCountByCategoryProvider = Provider.family<int, String>((ref, categoryId) {
  return ref.watch(transactionsByCategoryProvider(categoryId)).length;
});

final searchedTransactionsProvider = Provider<AsyncValue<List<TransactionGroup>>>((ref) {
  final groupsAsync = ref.watch(groupedTransactionsProvider);
  final query = ref.watch(transactionSearchQueryProvider).toLowerCase();

  return groupsAsync.whenData((groups) {
    if (query.isEmpty) return groups;

    return groups.map((group) {
      final filteredTxs = group.transactions.where((tx) {
        final note = tx.note?.toLowerCase() ?? '';
        final merchant = tx.merchant?.toLowerCase() ?? '';
        return note.contains(query) || merchant.contains(query);
      }).toList();

      return TransactionGroup(date: group.date, transactions: filteredTxs);
    }).where((group) => group.transactions.isNotEmpty).toList();
  });
});

/// Number of transactions to show per page.
const _transactionPageSize = 50;

/// Controls how many transactions are currently displayed.
/// Incremented by [loadMoreTransactions] when the user scrolls to the bottom.
final transactionDisplayCountProvider = StateProvider<int>((ref) {
  // Reset when the underlying data changes (search, filter, etc.)
  ref.watch(searchedTransactionsProvider);
  return _transactionPageSize;
});

/// Whether more transactions are available beyond the current display count.
final hasMoreTransactionsProvider = Provider<bool>((ref) {
  final displayCount = ref.watch(transactionDisplayCountProvider);
  final groups = ref.watch(searchedTransactionsProvider).valueOrNull ?? [];
  final totalCount = groups.fold<int>(0, (sum, g) => sum + g.transactions.length);
  return displayCount < totalCount;
});

/// Paginated transaction groups: only includes enough groups to fill
/// [transactionDisplayCountProvider] transactions.
final paginatedTransactionsProvider = Provider<AsyncValue<List<TransactionGroup>>>((ref) {
  final groupsAsync = ref.watch(searchedTransactionsProvider);
  final displayCount = ref.watch(transactionDisplayCountProvider);

  return groupsAsync.whenData((groups) {
    int remaining = displayCount;
    final result = <TransactionGroup>[];

    for (final group in groups) {
      if (remaining <= 0) break;

      if (group.transactions.length <= remaining) {
        result.add(group);
        remaining -= group.transactions.length;
      } else {
        // Partial group: take only the first `remaining` transactions
        result.add(TransactionGroup(
          date: group.date,
          transactions: group.transactions.sublist(0, remaining),
        ));
        remaining = 0;
      }
    }

    return result;
  });
});

final transactionsByAssetProvider = Provider.family<List<Transaction>, String>((ref, assetId) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return [];
  return transactions.where((t) => t.assetId == assetId).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
});

/// Maps lowercase merchant names to their most frequently used category ID.
/// Excludes transfers. Used for auto-categorization.
final merchantCategoryMapProvider = Provider<Map<String, String>>((ref) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return {};

  // Count category usage per merchant
  final merchantCategoryCounts = <String, Map<String, int>>{};
  for (final tx in transactions) {
    if (tx.type == TransactionType.transfer) continue;
    final merchant = tx.merchant?.trim().toLowerCase();
    if (merchant == null || merchant.isEmpty) continue;
    final categoryId = tx.categoryId;
    if (categoryId.isEmpty) continue;

    merchantCategoryCounts.putIfAbsent(merchant, () => {});
    merchantCategoryCounts[merchant]![categoryId] =
        (merchantCategoryCounts[merchant]![categoryId] ?? 0) + 1;
  }

  // Pick the most frequent category for each merchant
  final result = <String, String>{};
  for (final entry in merchantCategoryCounts.entries) {
    final counts = entry.value;
    String? bestId;
    int bestCount = 0;
    for (final catEntry in counts.entries) {
      if (catEntry.value > bestCount) {
        bestCount = catEntry.value;
        bestId = catEntry.key;
      }
    }
    if (bestId != null) {
      result[entry.key] = bestId;
    }
  }

  return result;
});

/// Provides distinct merchant names from transaction history, sorted by frequency.
final merchantSuggestionsProvider = Provider<List<String>>((ref) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return [];

  final frequency = <String, int>{};
  for (final tx in transactions) {
    final merchant = tx.merchant?.trim();
    if (merchant != null && merchant.isNotEmpty) {
      frequency[merchant] = (frequency[merchant] ?? 0) + 1;
    }
  }

  final sorted = frequency.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sorted.map((e) => e.key).toList();
});
