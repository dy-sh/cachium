import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../savings_goals/presentation/providers/savings_goals_provider.dart';
import '../../../transactions/data/models/transaction.dart';
import '../../../transactions/presentation/providers/recurring_rules_provider.dart';
import '../../../transactions/presentation/providers/transaction_templates_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../presentation/providers/accounts_provider.dart';
import '../models/account.dart';

/// Encapsulates the cross-feature cascading work involved in deleting an
/// account or moving its transactions to another account. The
/// `AccountsNotifier` previously inlined ~120 lines of this orchestration;
/// extracting it here keeps the notifier focused on state and makes the
/// deletion paths individually testable.
class AccountDeletionService {
  final Ref ref;

  AccountDeletionService(this.ref);

  /// Delete [accountId] together with every transaction that references it
  /// (as source or transfer destination), recurring rules, templates, and
  /// linked savings goals.
  ///
  /// Side-account balance updates run *after* the drift transaction commits
  /// so notifier state stays in sync. Throws [RepositoryException] on failure.
  Future<void> deleteAccountWithTransactions(String accountId) async {
    final db = ref.read(databaseProvider);
    final accountRepo = ref.read(accountRepositoryProvider);
    final transactionRepo = ref.read(transactionRepositoryProvider);

    final allTransactions = await ref.read(transactionsProvider.future);
    final outgoingTransactions =
        allTransactions.where((t) => t.accountId == accountId).toList();
    final incomingTransfers = allTransactions.where(
      (t) => t.destinationAccountId == accountId && t.accountId != accountId,
    ).toList();

    final rules = await ref.read(recurringRulesProvider.future);
    final templates = await ref.read(transactionTemplatesProvider.future);

    // Compute side-account deltas before touching the database.
    final sideDeltas = <String, double>{};
    for (final tx in outgoingTransactions) {
      if (tx.type == TransactionType.transfer &&
          tx.destinationAccountId != null &&
          tx.destinationAccountId != accountId) {
        final delta = -(tx.destinationAmount ?? tx.amount);
        sideDeltas.update(tx.destinationAccountId!, (v) => v + delta,
            ifAbsent: () => delta);
      }
    }
    for (final tx in incomingTransfers) {
      sideDeltas.update(tx.accountId, (v) => v + tx.amount,
          ifAbsent: () => tx.amount);
    }

    await db.transaction(() async {
      for (final tx in outgoingTransactions) {
        await transactionRepo.deleteTransaction(tx.id);
      }
      for (final tx in incomingTransfers) {
        await transactionRepo.deleteTransaction(tx.id);
      }
      for (final rule in rules) {
        if (rule.accountId == accountId ||
            rule.destinationAccountId == accountId) {
          await ref.read(recurringRulesProvider.notifier).deleteRule(rule.id);
        }
      }
      for (final template in templates) {
        if (template.accountId == accountId ||
            template.destinationAccountId == accountId) {
          await ref
              .read(transactionTemplatesProvider.notifier)
              .deleteTemplate(template.id);
        }
      }
      await _clearLinkedAccountOnGoals(accountId);
      await accountRepo.deleteAccount(accountId);
    });

    final accountsNotifier = ref.read(accountsProvider.notifier);
    for (final entry in sideDeltas.entries) {
      await accountsNotifier.updateBalance(entry.key, entry.value);
    }
  }

  /// Move all transactions, recurring rules, and templates from
  /// [sourceAccountId] to [targetAccountId], then delete the source account.
  /// Returns the post-move balance delta that should be added to
  /// [targetAccountId]'s in-memory representation.
  ///
  /// Throws [RepositoryException] on failure.
  Future<double> moveAndDelete({
    required String sourceAccountId,
    required String targetAccountId,
    required Account targetAccount,
  }) async {
    final db = ref.read(databaseProvider);
    final accountRepo = ref.read(accountRepositoryProvider);
    final transactionRepo = ref.read(transactionRepositoryProvider);

    final allTransactions = await ref.read(transactionsProvider.future);
    final transactionsToMove =
        allTransactions.where((t) => t.accountId == sourceAccountId).toList();
    final incomingTransfers = allTransactions.where(
      (t) =>
          t.destinationAccountId == sourceAccountId &&
          t.accountId != sourceAccountId,
    ).toList();

    double totalEffect = 0;
    for (final tx in transactionsToMove) {
      if (tx.type == TransactionType.transfer) {
        totalEffect -= tx.amount;
      } else {
        totalEffect +=
            tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
    }
    for (final tx in incomingTransfers) {
      totalEffect += tx.destinationAmount ?? tx.amount;
    }

    final rules = await ref.read(recurringRulesProvider.future);
    final templates = await ref.read(transactionTemplatesProvider.future);

    await db.transaction(() async {
      for (final tx in transactionsToMove) {
        final updatedTx = tx.copyWith(accountId: targetAccountId);
        await transactionRepo.updateTransaction(updatedTx);
      }
      for (final tx in incomingTransfers) {
        final updatedTx = tx.copyWith(destinationAccountId: targetAccountId);
        await transactionRepo.updateTransaction(updatedTx);
      }
      for (final rule in rules) {
        if (rule.accountId == sourceAccountId) {
          await ref.read(recurringRulesProvider.notifier).updateRule(
                rule.copyWith(accountId: targetAccountId),
              );
        } else if (rule.destinationAccountId == sourceAccountId) {
          await ref.read(recurringRulesProvider.notifier).updateRule(
                rule.copyWith(destinationAccountId: targetAccountId),
              );
        }
      }
      for (final template in templates) {
        if (template.accountId == sourceAccountId) {
          await ref.read(transactionTemplatesProvider.notifier).updateTemplate(
                template.copyWith(accountId: targetAccountId),
              );
        } else if (template.destinationAccountId == sourceAccountId) {
          await ref.read(transactionTemplatesProvider.notifier).updateTemplate(
                template.copyWith(destinationAccountId: targetAccountId),
              );
        }
      }
      final updatedTarget =
          targetAccount.copyWith(balance: targetAccount.balance + totalEffect);
      await accountRepo.updateAccount(updatedTarget);
      await _clearLinkedAccountOnGoals(sourceAccountId);
      await accountRepo.deleteAccount(sourceAccountId);
    });

    return totalEffect;
  }

  Future<void> _clearLinkedAccountOnGoals(String accountId) async {
    final goals = await ref.read(savingsGoalsProvider.future);
    for (final goal in goals) {
      if (goal.linkedAccountId == accountId) {
        await ref.read(savingsGoalsProvider.notifier).updateGoal(
              goal.copyWith(clearLinkedAccountId: true),
            );
      }
    }
  }
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  return AccountDeletionService(ref);
});
