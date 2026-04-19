import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/constants/app_radius.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../design_system/components/feedback/notification.dart';
import '../../../../design_system/components/layout/page_layout.dart';
import '../../../../design_system/components/layout/unsaved_work_pop_scope.dart';
import '../../../categories/data/models/category.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../categories/presentation/providers/categories_provider.dart';
import '../../../../core/constants/currencies.dart';
import '../../../../core/utils/currency_conversion.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/models/budget.dart';
import '../../data/models/budget_progress.dart';
import '../providers/budget_provider.dart';

class BudgetSettingsScreen extends ConsumerStatefulWidget {
  const BudgetSettingsScreen({super.key});

  @override
  ConsumerState<BudgetSettingsScreen> createState() =>
      _BudgetSettingsScreenState();
}

class _BudgetSettingsScreenState extends ConsumerState<BudgetSettingsScreen> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
  }

  @override
  Widget build(BuildContext context) {
    final colorIntensity = ref.watch(colorIntensityProvider);
    final mainCurrencyCode = ref.watch(mainCurrencyCodeProvider);
    final currencySymbol = Currency.symbolFromCode(mainCurrencyCode);

    final progressList = ref.watch(budgetProgressProvider(
      (year: _selectedYear, month: _selectedMonth),
    ));

    return PageLayout(
      title: 'Budgets',
      showBackButton: true,
      body: CustomScrollView(
        slivers: [
          // Month selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.chevronLeft, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () {
                      setState(() {
                        if (_selectedMonth == 1) {
                          _selectedMonth = 12;
                          _selectedYear--;
                        } else {
                          _selectedMonth--;
                        }
                      });
                    },
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    DateFormat('MMMM yyyy')
                        .format(DateTime(_selectedYear, _selectedMonth)),
                    style: AppTypography.h4,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  IconButton(
                    icon: const Icon(LucideIcons.chevronRight, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () {
                      setState(() {
                        if (_selectedMonth == 12) {
                          _selectedMonth = 1;
                          _selectedYear++;
                        } else {
                          _selectedMonth++;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // Budget list
          if (progressList.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.card,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.target,
                        size: 40,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No budgets for this month',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _AddBudgetButton(
                        year: _selectedYear,
                        month: _selectedMonth,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final progress = progressList[index];
                  return _BudgetProgressTile(
                    progress: progress,
                    currencySymbol: currencySymbol,
                    colorIntensity: colorIntensity,
                    onDelete: () async {
                      await ref
                          .read(budgetsProvider.notifier)
                          .deleteBudget(progress.budget.id);
                    },
                    onEdit: () =>
                        _showBudgetForm(context, budget: progress.budget),
                  );
                },
                childCount: progressList.length,
              ),
            ),

          if (progressList.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: _AddBudgetButton(
                  year: _selectedYear,
                  month: _selectedMonth,
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(
              height: AppSpacing.bottomNavHeight + AppSpacing.lg,
            ),
          ),
        ],
      ),
    );
  }

  void _showBudgetForm(BuildContext context, {Budget? budget}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
        year: _selectedYear,
        month: _selectedMonth,
        editBudget: budget,
      ),
    );
  }
}

class _AddBudgetButton extends ConsumerWidget {
  final int year;
  final int month;

  const _AddBudgetButton({required this.year, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = ref.watch(accentColorProvider);

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _BudgetFormSheet(year: year, month: month),
        );
      },
      child: Container(
        height: AppSpacing.buttonHeight,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: AppRadius.button,
          border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 18, color: accentColor),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Add Budget',
              style: AppTypography.button.copyWith(color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetProgressTile extends StatelessWidget {
  final BudgetProgress progress;
  final String currencySymbol;
  final ColorIntensity colorIntensity;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _BudgetProgressTile({
    required this.progress,
    required this.currencySymbol,
    required this.colorIntensity,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = progress.percentage < 75
        ? AppColors.getTransactionColor('income', colorIntensity)
        : progress.percentage <= 100
            ? AppColors.yellow
            : AppColors.getTransactionColor('expense', colorIntensity);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.xs,
      ),
      child: GestureDetector(
        onTap: onEdit,
        onLongPress: onDelete,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(progress.categoryIcon,
                      size: 18, color: progress.categoryColor),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      progress.categoryName,
                      style: AppTypography.labelLarge,
                    ),
                  ),
                  Text(
                    '$currencySymbol${progress.spent.toStringAsFixed(0)} / $currencySymbol${progress.effectiveBudget.toStringAsFixed(0)}',
                    style: AppTypography.moneyTiny.copyWith(
                      color: progressColor,
                    ),
                  ),
                ],
              ),
              if (progress.rolloverAmount > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$currencySymbol${progress.budget.amount.toStringAsFixed(0)} budget + $currencySymbol${progress.rolloverAmount.toStringAsFixed(0)} rollover = $currencySymbol${progress.effectiveBudget.toStringAsFixed(0)} effective',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              // Progress bar
              ClipRRect(
                borderRadius: AppRadius.fullAll,
                child: LinearProgressIndicator(
                  value: (progress.percentage / 100).clamp(0.0, 1.0),
                  backgroundColor: AppColors.border,
                  color: progressColor,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${progress.percentage.toStringAsFixed(0)}%',
                    style: AppTypography.labelSmall.copyWith(
                      color: progressColor,
                    ),
                  ),
                  Text(
                    progress.isOverBudget
                        ? 'Over by $currencySymbol${(-progress.remaining).toStringAsFixed(0)}'
                        : '$currencySymbol${progress.remaining.toStringAsFixed(0)} left',
                    style: AppTypography.labelSmall.copyWith(
                      color: progress.isOverBudget
                          ? progressColor
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetFormSheet extends ConsumerStatefulWidget {
  final int year;
  final int month;
  final Budget? editBudget;

  const _BudgetFormSheet({
    required this.year,
    required this.month,
    this.editBudget,
  });

  @override
  ConsumerState<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<_BudgetFormSheet> {
  final _amountController = TextEditingController();
  String? _selectedCategoryId;
  bool _rolloverEnabled = false;
  bool _showValidationErrors = false;
  bool _isSaving = false;

  String _initialAmountText = '';
  String? _initialCategoryId;
  bool _initialRollover = false;

  @override
  void initState() {
    super.initState();
    final budget = widget.editBudget;
    if (budget != null) {
      _selectedCategoryId = budget.categoryId;
      final mainCurrency = ref.read(mainCurrencyCodeProvider);
      final decimals = currencyDecimalPlaces(mainCurrency);
      _amountController.text =
          roundCurrency(budget.amount, currencyCode: mainCurrency)
              .toStringAsFixed(decimals);
      _rolloverEnabled = budget.rolloverEnabled;
    }
    _initialAmountText = _amountController.text;
    _initialCategoryId = _selectedCategoryId;
    _initialRollover = _rolloverEnabled;
  }

  bool get _hasUnsavedWork {
    if (_isSaving) return false;
    return _amountController.text != _initialAmountText ||
        _selectedCategoryId != _initialCategoryId ||
        _rolloverEnabled != _initialRollover;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final accentColor = ref.watch(accentColorProvider);
    final colorIntensity = ref.watch(colorIntensityProvider);

    final expenseCategories = categoriesAsync.valueOrNull
            ?.where((c) => c.type == CategoryType.expense)
            .toList() ??
        [];

    return UnsavedWorkPopScope(
      hasUnsavedWork: _hasUnsavedWork,
      child: Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          topRight: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadius.fullAll,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              widget.editBudget != null ? 'Edit Budget' : 'Add Budget',
              style: AppTypography.h4,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Category selector
            Text('Category', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: expenseCategories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final cat = expenseCategories[index];
                  final isSelected = _selectedCategoryId == cat.id;
                  final catColor = cat.getColor(colorIntensity);

                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCategoryId = cat.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? catColor.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: AppRadius.chip,
                        border: Border.all(
                          color: isSelected ? catColor : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cat.icon, size: 14, color: catColor),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            cat.name,
                            style: AppTypography.labelMedium.copyWith(
                              color: isSelected
                                  ? catColor
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_showValidationErrors && _selectedCategoryId == null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Select a category',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.red),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            // Amount input
            Text('Budget Amount', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTypography.input,
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: AppTypography.inputHint,
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.input,
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.input,
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.input,
                  borderSide: BorderSide(color: accentColor),
                ),
              ),
            ),
            if (_showValidationErrors && (double.tryParse(_amountController.text) ?? 0) <= 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Enter an amount greater than zero',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.red),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            // Rollover toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rollover', style: AppTypography.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Carry unused budget to next month',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _rolloverEnabled,
                  onChanged: (value) =>
                      setState(() => _rolloverEnabled = value),
                  activeTrackColor: accentColor,
                  activeThumbColor: AppColors.background,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // Save button
            SizedBox(
              width: double.infinity,
              height: AppSpacing.buttonHeight,
              child: ElevatedButton(
                onPressed: () => _save(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: AppColors.background,
                  disabledBackgroundColor: AppColors.border,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.button,
                  ),
                ),
                child: Text(
                  widget.editBudget != null ? 'Update' : 'Save',
                  style: AppTypography.button.copyWith(
                    color: AppColors.background,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || _selectedCategoryId == null) {
      setState(() => _showValidationErrors = true);
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(budgetsProvider.notifier);

      if (widget.editBudget != null) {
        await notifier.updateBudget(widget.editBudget!.copyWith(
          categoryId: _selectedCategoryId,
          amount: amount,
          rolloverEnabled: _rolloverEnabled,
        ));
      } else {
        await notifier.addBudget(Budget(
          id: const Uuid().v4(),
          categoryId: _selectedCategoryId!,
          amount: amount,
          year: widget.year,
          month: widget.month,
          rolloverEnabled: _rolloverEnabled,
          createdAt: DateTime.now(),
        ));
      }

      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        context.showErrorNotification(
          e is AppException ? e.userMessage : 'Failed to save budget',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
