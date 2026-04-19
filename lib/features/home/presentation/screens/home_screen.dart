import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../design_system/components/buttons/circular_button.dart';
import '../../../../design_system/animations/staggered_list.dart';
import '../../../../design_system/components/feedback/notification.dart';
import '../../../../navigation/app_router.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../../bills/presentation/providers/bill_provider.dart';
import '../../../bills/presentation/widgets/upcoming_bills_list.dart';
import '../../../budgets/presentation/providers/budget_provider.dart';
import '../widgets/account_preview_list.dart';
import '../widgets/budget_progress_list.dart';
import '../widgets/quick_actions.dart';
import '../widgets/recent_transactions_list.dart';
import '../widgets/total_balance_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(homeConfigProvider);
    final sectionOrder = config.sectionOrder;
    final showAccountsList = config.showAccountsList;
    final showTotalBalance = config.showTotalBalance;
    final showQuickActions = config.showQuickActions;
    final showRecentTransactions = config.showRecentTransactions;
    final showBudgetProgress = config.showBudgetProgress;

    // Bills data — only watch emptiness for visibility
    final hasUpcomingBills = ref.watch(upcomingBillsProvider.select((b) => b.isNotEmpty));
    final hasOverdueBills = ref.watch(overdueBillsProvider.select((b) => b.isNotEmpty));
    final hasBills = hasUpcomingBills || hasOverdueBills;

    // Budget progress data — only watch emptiness for visibility
    final now = DateTime.now();
    final hasBudgetProgress = ref.watch(
      budgetProgressProvider((year: now.year, month: now.month))
          .select((list) => list.isNotEmpty),
    );

    // Map section IDs to visibility and builder
    final sectionVisibility = {
      'accounts': showAccountsList,
      'totalBalance': showTotalBalance,
      'quickActions': showQuickActions,
      'billsDue': hasBills,
      'budgetProgress': showBudgetProgress && hasBudgetProgress,
      'recentTransactions': showRecentTransactions,
    };

    // Build visible sections list for staggered animation indexing
    final visibleSections = <Widget>[];
    int staggerIndex = 0;

    for (final sectionId in sectionOrder) {
      if (!(sectionVisibility[sectionId] ?? false)) continue;

      final widget = _buildSection(context, ref, sectionId, staggerIndex);
      if (widget != null) {
        visibleSections.add(widget);
        visibleSections.add(const SizedBox(height: AppSpacing.xxl));
        staggerIndex++;
      }
    }

    // Remove trailing spacer
    if (visibleSections.isNotEmpty && visibleSections.last is SizedBox) {
      visibleSections.removeLast();
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.lg),
          // Fixed Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good ${_getGreeting()}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cachium',
                      style: AppTypography.h2,
                    ),
                  ],
                ),
                Row(
                  children: [
                    CircularButton(
                      onTap: () => context.push(AppRoutes.calendar),
                      icon: LucideIcons.calendar,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    CircularButton(
                      onTap: () => context.push(AppRoutes.search),
                      icon: LucideIcons.search,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    CircularButton.add(
                      onTap: () => context.push(AppRoutes.transactionForm),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Scrollable Content
          Expanded(
            child: RefreshIndicator(
              color: AppColors.textPrimary,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                try {
                  await Future.wait([
                    ref.read(transactionsProvider.notifier).refresh(),
                    ref.read(accountsProvider.notifier).refresh(),
                  ]);
                } catch (e) {
                  if (context.mounted) {
                    context.showErrorNotification('Refresh failed: $e');
                  }
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppSpacing.bottomNavHeight + AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: visibleSections,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildSection(BuildContext context, WidgetRef ref, String sectionId, int staggerIndex) {
    switch (sectionId) {
      case 'accounts':
        return StaggeredListItem(
          index: staggerIndex,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Accounts', style: AppTypography.h4),
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.accounts),
                      child: Text(
                        'See all',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const AccountPreviewList(),
            ],
          ),
        );
      case 'totalBalance':
        return StaggeredListItem(
          index: staggerIndex,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: TotalBalanceCard(),
          ),
        );
      case 'quickActions':
        return StaggeredListItem(
          index: staggerIndex,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: QuickActions(),
          ),
        );
      case 'billsDue':
        return StaggeredListItem(
          index: staggerIndex,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bills Due', style: AppTypography.h4),
                    GestureDetector(
                      onTap: () => context.push(AppRoutes.bills),
                      child: Text(
                        'See all',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const UpcomingBillsList(),
            ],
          ),
        );
      case 'budgetProgress':
        return StaggeredListItem(
          index: staggerIndex,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Budget', style: AppTypography.h4),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const BudgetProgressList(),
            ],
          ),
        );
      case 'recentTransactions':
        return StaggeredListItem(
          index: staggerIndex,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Transactions', style: AppTypography.h4),
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.transactions),
                      child: Text(
                        'See all',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const RecentTransactionsList(),
            ],
          ),
        );
      default:
        return null;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }
}
