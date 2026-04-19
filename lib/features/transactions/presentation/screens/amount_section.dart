import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/providers/exchange_rate_provider.dart';
import '../../../../design_system/components/feedback/notification.dart';
import '../../../../design_system/components/inputs/amount_input.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/transaction_form_provider.dart';

class AmountSection extends ConsumerWidget {
  final TransactionFormState formState;
  final bool isEditing;
  final ValueChanged<double> onAmountChanged;

  const AmountSection({
    super.key,
    required this.formState,
    required this.isEditing,
    required this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mainCurrency = ref.watch(mainCurrencyCodeProvider);
    final isStale = ref.watch(exchangeRatesStaleProvider);
    final rateAge = ref.watch(exchangeRateAgeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AmountInput(
          key: ValueKey('amount_${formState.editingTransactionId}_${formState.currencyCode}'),
          initialValue: formState.amount > 0 ? formState.amount : null,
          transactionType: formState.type.name,
          currencyCode: formState.currencyCode,
          autofocus: !isEditing,
          onChanged: onAmountChanged,
        ),
        if (formState.amountError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              formState.amountError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.expense),
            ),
          ),
        if (formState.currencyCode != mainCurrency && isStale)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: GestureDetector(
              onTap: () async {
                await ref.read(exchangeRatesProvider.notifier).refresh();
                if (context.mounted) {
                  context.showSuccessNotification('Exchange rates refreshed');
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  const Icon(LucideIcons.alertTriangle, size: 14, color: AppColors.yellow),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    rateAge != null
                        ? 'Rates outdated ($rateAge) — tap to refresh'
                        : 'Rates outdated — tap to refresh',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.yellow),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
