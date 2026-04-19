import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/animations/haptic_helper.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';

/// Result of a confirmation dialog with optional checkbox.
class ConfirmationResult {
  final bool confirmed;
  final bool checkboxValue;

  const ConfirmationResult({
    required this.confirmed,
    this.checkboxValue = false,
  });
}

/// A reusable confirmation dialog matching the Cachium design system.
///
/// Supports:
/// - Custom title and message
/// - Optional icon in the title row
/// - Destructive variant with red confirm button
/// - Optional checkbox (returns [ConfirmationResult] when used)
/// - Custom confirm/cancel button labels
class ConfirmationDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final IconData? icon;
  final String? checkboxLabel;
  final bool initialCheckboxValue;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.isDestructive = false,
    this.icon,
    this.checkboxLabel,
    this.initialCheckboxValue = false,
  });

  @override
  State<ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<ConfirmationDialog> {
  late bool _checkboxValue;

  @override
  void initState() {
    super.initState();
    _checkboxValue = widget.initialCheckboxValue;
  }

  Color get _accentColor =>
      widget.isDestructive ? AppColors.expense : AppColors.accentPrimary;

  void _confirm() {
    // Stronger feedback for confirmed destructive actions, lighter for
    // routine confirmations. Matches existing HapticHelper call sites that
    // fire unconditionally — gating is the OS/device's responsibility.
    if (widget.isDestructive) {
      HapticHelper.heavyImpact();
    } else {
      HapticHelper.mediumImpact();
    }
    if (widget.checkboxLabel != null) {
      Navigator.pop(
        context,
        ConfirmationResult(confirmed: true, checkboxValue: _checkboxValue),
      );
    } else {
      Navigator.pop(context, true);
    }
  }

  void _cancel() {
    if (widget.checkboxLabel != null) {
      Navigator.pop(
        context,
        ConfirmationResult(confirmed: false, checkboxValue: _checkboxValue),
      );
    } else {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
      ),
      title: widget.icon != null
          ? Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: AppColors.opacitySubtle),
                    borderRadius: AppRadius.iconButton,
                  ),
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: _accentColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTypography.h4,
                  ),
                ),
              ],
            )
          : Text(widget.title, style: AppTypography.h4),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (widget.checkboxLabel != null) ...[
            const SizedBox(height: AppSpacing.lg),
            GestureDetector(
              onTap: () {
                setState(() {
                  _checkboxValue = !_checkboxValue;
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _checkboxValue
                          ? _accentColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _checkboxValue
                            ? _accentColor
                            : AppColors.textTertiary,
                        width: 2,
                      ),
                    ),
                    child: _checkboxValue
                        ? Icon(
                            LucideIcons.check,
                            size: 16,
                            color: AppColors.textPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.checkboxLabel!,
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: Text(
            widget.cancelLabel,
            style: AppTypography.button.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: _confirm,
          child: Text(
            widget.confirmLabel,
            style: AppTypography.button.copyWith(
              color: widget.isDestructive
                  ? AppColors.expense
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows a confirmation dialog and returns `true` if confirmed.
///
/// For dialogs with a checkbox, use [showConfirmationDialogWithCheckbox] instead.
Future<bool> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
      icon: icon,
    ),
  );
  return result ?? false;
}

/// Shows a confirmation dialog with a checkbox and returns a [ConfirmationResult].
Future<ConfirmationResult> showConfirmationDialogWithCheckbox({
  required BuildContext context,
  required String title,
  required String message,
  required String checkboxLabel,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
  bool initialCheckboxValue = false,
  IconData? icon,
}) async {
  final result = await showDialog<ConfirmationResult>(
    context: context,
    builder: (context) => ConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
      icon: icon,
      checkboxLabel: checkboxLabel,
      initialCheckboxValue: initialCheckboxValue,
    ),
  );
  return result ?? const ConfirmationResult(confirmed: false);
}
