import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../feedback/confirmation_dialog.dart';

/// A reusable PopScope that shows a confirmation dialog when the user
/// tries to navigate away with unsaved changes.
class UnsavedWorkPopScope extends StatelessWidget {
  final bool hasUnsavedWork;
  final Widget child;

  const UnsavedWorkPopScope({
    super.key,
    required this.hasUnsavedWork,
    required this.child,
  });

  /// Navigate away from a form screen, checking for unsaved work first.
  ///
  /// Use this instead of `context.go()` or `context.push()` from within
  /// form screens wrapped in [UnsavedWorkPopScope] to ensure the discard
  /// confirmation dialog is shown when there are unsaved changes.
  static Future<bool> navigateAwayGuarded({
    required BuildContext context,
    required bool hasUnsavedWork,
    required VoidCallback navigate,
  }) async {
    FocusScope.of(context).unfocus();
    if (!hasUnsavedWork) {
      navigate();
      return true;
    }
    final shouldDiscard = await showConfirmationDialog(
      context: context,
      title: 'Discard changes?',
      message: 'You have unsaved changes. Are you sure you want to leave?',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep Editing',
      isDestructive: true,
    );
    if (shouldDiscard && context.mounted) {
      navigate();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasUnsavedWork,
      onPopInvokedWithResult: (didPop, _) async {
        FocusScope.of(context).unfocus();
        if (didPop) return;
        final shouldDiscard = await showConfirmationDialog(
          context: context,
          title: 'Discard changes?',
          message: 'You have unsaved changes. Are you sure you want to go back?',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep Editing',
          isDestructive: true,
        );
        if (shouldDiscard && context.mounted) {
          context.pop();
        }
      },
      child: child,
    );
  }
}
