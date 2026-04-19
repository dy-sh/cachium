import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/providers/async_value_extensions.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/providers/exchange_rate_provider.dart';
import '../../../../core/providers/optimistic_notifier.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../data/models/account.dart';
import '../../data/services/account_deletion_service.dart';

/// Notifier for managing account state.
///
/// Error Handling:
/// - build() lets exceptions propagate to set AsyncValue.error()
/// - Mutation methods catch exceptions and set state to AsyncValue.error()
/// - RepositoryException provides detailed error context
class AccountsNotifier extends AsyncNotifier<List<Account>>
    with OptimisticAsyncNotifier<Account> {
  final _uuid = const Uuid();
  /// Per-account chain of pending balance updates. Each new caller awaits the
  /// previous future, then installs its own. Entries are intentionally not
  /// removed: account-id cardinality is bounded, and awaiting an already-
  /// completed future is a no-op so stale entries cost nothing.
  final Map<String, Future<void>> _balanceLocks = {};

  @override
  Future<List<Account>> build() async {
    final repo = ref.watch(accountRepositoryProvider);
    return repo.getAllAccounts();
  }

  /// Add a new account.
  ///
  /// Returns the new account's ID.
  /// Throws [RepositoryException] on failure, which is caught and
  /// converted to AsyncValue.error().
  Future<String> addAccount({
    required String name,
    required AccountType type,
    required double initialBalance,
    String currencyCode = 'USD',
    Color? customColor,
  }) async {
    final account = Account(
      id: _uuid.v4(),
      name: name,
      type: type,
      balance: initialBalance,
      initialBalance: initialBalance,
      currencyCode: currencyCode,
      customColor: customColor,
      createdAt: DateTime.now(),
    );

    await runOptimistic(
      update: (accounts) => [account, ...accounts],
      action: () => ref.read(accountRepositoryProvider).createAccount(account),
      onError: (e) => RepositoryException.create(entityType: 'Account', cause: e),
    );

    return account.id;
  }

  /// Update an existing account.
  ///
  /// Throws [RepositoryException] on failure.
  Future<void> updateAccount(Account account) async {
    await runOptimistic(
      update: (accounts) =>
          accounts.map((a) => a.id == account.id ? account : a).toList(),
      action: () => ref.read(accountRepositoryProvider).updateAccount(account),
      onError: (e) => RepositoryException.update(entityType: 'Account', entityId: account.id, cause: e),
    );
  }

  /// Delete an account.
  ///
  /// Throws [RepositoryException] on failure.
  Future<void> deleteAccount(String id) async {
    await runOptimistic(
      update: (accounts) => accounts.where((a) => a.id != id).toList(),
      action: () => ref.read(accountRepositoryProvider).deleteAccount(id),
      onError: (e) => RepositoryException.delete(entityType: 'Account', entityId: id, cause: e),
    );
  }

  /// Delete account along with all its transactions (cascading to recurring
  /// rules, templates, savings goals). Delegates to [AccountDeletionService].
  ///
  /// Throws [RepositoryException] on failure.
  Future<void> deleteAccountWithTransactions(String accountId) async {
    final previousState = state;
    try {
      // Optimistically update local state.
      state = state.whenData(
        (accounts) => accounts.where((a) => a.id != accountId).toList(),
      );
      await ref
          .read(accountDeletionServiceProvider)
          .deleteAccountWithTransactions(accountId);
      ref.invalidate(transactionsProvider);
    } catch (e, st) {
      state = previousState;
      Error.throwWithStackTrace(
        e is AppException
            ? e
            : RepositoryException.delete(
                entityType: 'Account', entityId: accountId, cause: e),
        st,
      );
    }
  }

  /// Move all transactions from [sourceAccountId] to [targetAccountId], then
  /// delete the source. Delegates to [AccountDeletionService].
  ///
  /// Throws [RepositoryException] on failure.
  Future<void> deleteAccountMovingTransactions(
    String sourceAccountId,
    String targetAccountId,
  ) async {
    final previousState = state;
    try {
      final accounts = state.valueOrNull;
      if (accounts == null) return;

      final targetAccount =
          accounts.where((a) => a.id == targetAccountId).firstOrNull;
      if (targetAccount == null) {
        throw RepositoryException.update(
          entityType: 'Account',
          entityId: targetAccountId,
          cause: StateError('Target account $targetAccountId not found'),
        );
      }

      final totalEffect = await ref
          .read(accountDeletionServiceProvider)
          .moveAndDelete(
            sourceAccountId: sourceAccountId,
            targetAccountId: targetAccountId,
            targetAccount: targetAccount,
          );

      // Reflect the move in local state.
      state = state.whenData((accts) {
        return accts
            .where((a) => a.id != sourceAccountId)
            .map((a) => a.id == targetAccountId
                ? a.copyWith(balance: a.balance + totalEffect)
                : a)
            .toList();
      });

      ref.invalidate(transactionsProvider);
    } catch (e, st) {
      state = previousState;
      Error.throwWithStackTrace(
        e is AppException
            ? e
            : RepositoryException.delete(
                entityType: 'Account', entityId: sourceAccountId, cause: e),
        st,
      );
    }
  }

  /// Update an account's balance by a delta amount.
  ///
  /// Uses a per-account lock to serialize concurrent updates and prevent
  /// read-modify-write races on the same account.
  /// Throws [RepositoryException] on failure.
  Future<void> updateBalance(String accountId, double amount) async {
    // Chain behind any pending update for the same account
    final previous = _balanceLocks[accountId] ?? Future.value();
    final completer = Completer<void>();
    _balanceLocks[accountId] = completer.future;
    await previous;

    final previousState = state;

    try {
      final currentState = state.valueOrNull;
      if (currentState == null) {
        throw RepositoryException.update(
          entityType: 'Account',
          entityId: accountId,
          cause: StateError('Accounts not loaded — cannot update balance'),
        );
      }

      final accountIndex =
          currentState.indexWhere((a) => a.id == accountId);
      if (accountIndex == -1) {
        throw RepositoryException.update(
          entityType: 'Account',
          entityId: accountId,
          cause: StateError('Account $accountId not found — cannot update balance'),
        );
      }

      final account = currentState[accountIndex];
      final updatedAccount =
          account.copyWith(balance: account.balance + amount);

      // Update in database first, then update local state
      final repo = ref.read(accountRepositoryProvider);
      await repo.updateAccount(updatedAccount);

      state = state.whenData(
        (accounts) =>
            accounts.map((a) => a.id == accountId ? updatedAccount : a).toList(),
      );
    } catch (e, st) {
      state = previousState;
      Error.throwWithStackTrace(
        e is AppException ? e : RepositoryException.update(entityType: 'Account', entityId: accountId, cause: e),
        st,
      );
    } finally {
      completer.complete();
    }
  }

  /// Reorder an account to a new position within its type group.
  Future<void> reorderAccount(int oldIndex, int newIndex, AccountType type) async {
    final previousState = state;
    final accounts = state.valueOrNull;
    if (accounts == null) return;

    try {
      // Get accounts of the same type, sorted by sortOrder
      final typeAccounts = accounts
          .where((a) => a.type == type)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      if (oldIndex < 0 || oldIndex >= typeAccounts.length) return;
      if (newIndex < 0 || newIndex >= typeAccounts.length) return;

      final item = typeAccounts.removeAt(oldIndex);
      typeAccounts.insert(newIndex, item);

      // Assign new sort orders
      final db = ref.read(databaseProvider);
      final repo = ref.read(accountRepositoryProvider);

      // Optimistically update local state
      final updatedAccounts = <Account>[];
      for (int i = 0; i < typeAccounts.length; i++) {
        updatedAccounts.add(typeAccounts[i].copyWith(sortOrder: i));
      }

      state = state.whenData((all) {
        return all.map((a) {
          if (a.type != type) return a;
          final updated = updatedAccounts.firstWhere((u) => u.id == a.id, orElse: () => a);
          return updated;
        }).toList();
      });

      await db.transaction(() async {
        for (int i = 0; i < updatedAccounts.length; i++) {
          await repo.updateAccount(updatedAccounts[i]);
        }
      });
    } catch (e, st) {
      state = previousState;
      Error.throwWithStackTrace(
        e is AppException ? e : RepositoryException.update(entityType: 'Account', entityId: '', cause: e),
        st,
      );
    }
  }

  /// Refresh accounts from database
  ///
  /// Sets state to AsyncValue.error() on failure.
  Future<void> refresh() async {
    try {
      final repo = ref.read(accountRepositoryProvider);
      state = AsyncData(await repo.getAllAccounts());
    } catch (e, st) {
      state = AsyncError(
        e is AppException ? e : RepositoryException.fetch(entityType: 'Account', cause: e),
        st,
      );
    }
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, List<Account>>(() {
  return AccountsNotifier();
});

final totalBalanceProvider = Provider<double>((ref) {
  final accountsAsync = ref.watch(accountsProvider);
  final accounts = accountsAsync.valueOrNull;
  if (accounts == null) return 0.0;

  final mainCurrency = ref.watch(mainCurrencyCodeProvider);
  final rates = ref.watch(exchangeRatesProvider).valueOrNull;

  return accounts.fold(0.0, (sum, account) {
    if (account.currencyCode == mainCurrency || rates == null) {
      return sum + account.balance;
    }
    return sum + convertToMainCurrency(
      account.balance,
      account.currencyCode,
      mainCurrency,
      rates,
    );
  });
});

double _sumConverted(
  Iterable<Account> accounts,
  String mainCurrency,
  Map<String, double>? rates, {
  bool absolute = false,
}) {
  return accounts.fold(0.0, (sum, a) {
    final value = absolute ? a.balance.abs() : a.balance;
    if (a.currencyCode == mainCurrency || rates == null) {
      return sum + value;
    }
    return sum + convertToMainCurrency(value, a.currencyCode, mainCurrency, rates);
  });
}

/// Total holdings across all non-liability accounts, converted to the main
/// currency. Memoized so home-screen rebuilds don't re-fold on every widget
/// tick — only fires when the list, main currency, or rates actually change.
final totalHoldingsProvider = Provider<double>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull;
  if (accounts == null) return 0.0;
  final mainCurrency = ref.watch(mainCurrencyCodeProvider);
  final rates = ref.watch(exchangeRatesProvider).valueOrNull;
  return _sumConverted(
    accounts.where((a) => a.type.isHolding),
    mainCurrency,
    rates,
  );
});

/// Total liabilities across all liability accounts, expressed as a positive
/// magnitude, converted to the main currency. Memoized for the same reason
/// as [totalHoldingsProvider].
final totalLiabilitiesProvider = Provider<double>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull;
  if (accounts == null) return 0.0;
  final mainCurrency = ref.watch(mainCurrencyCodeProvider);
  final rates = ref.watch(exchangeRatesProvider).valueOrNull;
  return _sumConverted(
    accounts.where((a) => a.type.isLiability),
    mainCurrency,
    rates,
    absolute: true,
  );
});

final accountsByTypeProvider =
    Provider<Map<AccountType, List<Account>>>((ref) {
  final accountsAsync = ref.watch(accountsProvider);
  final accounts = accountsAsync.valueOrEmpty;
  final Map<AccountType, List<Account>> grouped = {};

  for (final account in accounts) {
    grouped.putIfAbsent(account.type, () => []).add(account);
  }

  // Sort each group by sortOrder
  for (final type in grouped.keys) {
    grouped[type]!.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  return grouped;
});

/// Computed map for O(1) account lookups. Rebuilt only when the account list changes.
final accountMapProvider = Provider<Map<String, Account>>((ref) {
  final accountsAsync = ref.watch(accountsProvider);
  final accounts = accountsAsync.valueOrNull;
  if (accounts == null) return {};
  return {for (final a in accounts) a.id: a};
});

final accountByIdProvider = Provider.autoDispose.family<Account?, String>((ref, id) {
  return ref.watch(accountMapProvider)[id];
});

/// Maps each account ID to its most recent transaction date.
/// Only rebuilds when the account-to-date mapping actually changes,
/// not on every transaction field change.
final _transactionAccountUsageProvider = Provider<Map<String, DateTime>>((ref) {
  final transactions = ref.watch(transactionsProvider).valueOrNull;
  if (transactions == null) return {};
  final map = <String, DateTime>{};
  for (final tx in transactions) {
    final current = map[tx.accountId];
    if (current == null || tx.createdAt.isAfter(current)) {
      map[tx.accountId] = tx.createdAt;
    }
  }
  return map;
});

/// Returns account IDs sorted by most recent transaction usage.
/// Accounts without transactions appear last, sorted by creation date.
final recentlyUsedAccountIdsProvider = Provider<List<String>>((ref) {
  final lastUsedMap = ref.watch(_transactionAccountUsageProvider);
  final accounts = ref.watch(accountsProvider).valueOrNull;
  if (accounts == null || accounts.isEmpty) return [];

  // Sort accounts: recently used first, then by account creation date
  final sortedAccounts = List<Account>.from(accounts);
  sortedAccounts.sort((a, b) {
    final aLastUsed = lastUsedMap[a.id];
    final bLastUsed = lastUsedMap[b.id];

    // Both have transactions - sort by last used
    if (aLastUsed != null && bLastUsed != null) {
      return bLastUsed.compareTo(aLastUsed);
    }
    // Only a has transactions
    if (aLastUsed != null) return -1;
    // Only b has transactions
    if (bLastUsed != null) return 1;
    // Neither has transactions - sort by creation date (newest first)
    return b.createdAt.compareTo(a.createdAt);
  });

  return sortedAccounts.map((a) => a.id).toList();
});

/// Checks if an account name already exists (case-insensitive).
/// Returns true if duplicate exists, excluding the account with excludeId.
final accountNameExistsProvider = Provider.family<bool, ({String name, String? excludeId})>((ref, params) {
  final accountsAsync = ref.watch(accountsProvider);
  final accounts = accountsAsync.valueOrEmpty;
  final nameLower = params.name.trim().toLowerCase();
  return accounts.any((a) =>
    a.name.toLowerCase() == nameLower && a.id != params.excludeId
  );
});
