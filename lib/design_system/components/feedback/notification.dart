import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/animations/haptic_helper.dart';
import '../../../core/constants/app_animations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../features/settings/data/models/app_settings.dart';
import '../../../features/settings/presentation/providers/settings_provider.dart';

/// Notification type determines the color scheme and icon.
enum FMNotificationType {
  success,
  error,
  warning,
  info,
}

extension FMNotificationTypeExtension on FMNotificationType {
  Color get color => colorForIntensity(ColorIntensity.zen);

  Color colorForIntensity(ColorIntensity intensity) {
    switch (this) {
      case FMNotificationType.success:
        return AppColors.getTransactionColor('income', intensity);
      case FMNotificationType.error:
        return AppColors.getTransactionColor('expense', intensity);
      case FMNotificationType.warning:
        switch (intensity) {
          case ColorIntensity.zen: return AppColors.yellow;
          case ColorIntensity.prism: return AppColors.yellowPrism;
          case ColorIntensity.neon: return AppColors.yellowNeon;
        }
      case FMNotificationType.info:
        switch (intensity) {
          case ColorIntensity.zen: return AppColors.cyan;
          case ColorIntensity.prism: return AppColors.cyanPrism;
          case ColorIntensity.neon: return AppColors.cyanNeon;
        }
    }
  }

  IconData get icon {
    switch (this) {
      case FMNotificationType.success:
        return LucideIcons.checkCircle2;
      case FMNotificationType.error:
        return LucideIcons.xCircle;
      case FMNotificationType.warning:
        return LucideIcons.alertTriangle;
      case FMNotificationType.info:
        return LucideIcons.info;
    }
  }
}

/// A notification widget matching the Cachium design system.
/// Appears from the top with slide + fade animation.
class Notification extends ConsumerStatefulWidget {
  final String message;
  final FMNotificationType type;
  final Duration duration;
  final VoidCallback? onDismiss;
  final bool showCloseButton;
  final String? actionLabel;
  final VoidCallback? onAction;

  const Notification({
    super.key,
    required this.message,
    this.type = FMNotificationType.info,
    this.duration = const Duration(seconds: 3),
    this.onDismiss,
    this.showCloseButton = true,
    this.actionLabel,
    this.onAction,
  });

  @override
  ConsumerState<Notification> createState() => _FMNotificationState();
}

class _FMNotificationState extends ConsumerState<Notification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  void resetTimer() {
    _dismissTimer?.cancel();
    if (widget.duration > Duration.zero) {
      _dismissTimer = Timer(widget.duration, _dismiss);
    }
    // Pulse animation to acknowledge duplicate
    _pulseAcknowledge();
  }

  void _pulseAcknowledge() {
    if (!mounted) return;
    _controller.animateTo(0.7, duration: const Duration(milliseconds: 100)).then((_) {
      if (mounted) {
        _controller.animateTo(1.0, duration: const Duration(milliseconds: 100));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.slow,
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.sharpCurve,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.defaultCurve,
    ));

    _controller.forward();

    if (widget.duration > Duration.zero) {
      _dismissTimer = Timer(widget.duration, _dismiss);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _dismissTimer?.cancel();
    await _controller.reverse();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    final intensity = ref.watch(colorIntensityProvider);
    final color = widget.type.colorForIntensity(intensity);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 100),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
            _dismiss();
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: color.withValues(alpha: AppColors.opacityMedium),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: AppColors.opacityMedium),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon indicator
              Container(
                width: AppSpacing.notificationIconSize,
                height: AppSpacing.notificationIconSize,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: AppColors.opacityLight),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(
                  widget.type.icon,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Message
              Expanded(
                child: Text(
                  widget.message,
                  style: AppTypography.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Action button
              if (widget.actionLabel != null && widget.onAction != null) ...[
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: () {
                    widget.onAction!();
                    _dismiss();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: AppColors.opacityLight),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Text(
                      widget.actionLabel!,
                      style: AppTypography.labelMedium.copyWith(
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
              // Close button
              if (widget.showCloseButton) ...[
                const SizedBox(width: AppSpacing.sm),
                Semantics(
                  label: 'Dismiss notification',
                  button: true,
                  child: GestureDetector(
                    onTap: _dismiss,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Container(
                          width: AppSpacing.notificationCloseSize,
                          height: AppSpacing.notificationCloseSize,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: AppRadius.smAll,
                          ),
                          child: Icon(
                            LucideIcons.x,
                            color: AppColors.textSecondary,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Manages showing notifications as overlays.
class NotificationOverlay {
  static final NotificationOverlay _instance = NotificationOverlay._();
  static NotificationOverlay get instance => _instance;

  NotificationOverlay._();

  OverlayEntry? _currentEntry;
  String? _currentMessage;
  FMNotificationType? _currentType;
  final GlobalKey<_FMNotificationState> _notificationKey = GlobalKey();
  final List<_NotificationItem> _queue = [];
  bool _isShowing = false;

  /// Shows a notification with the given message and type.
  void show(
    BuildContext context,
    String message, {
    FMNotificationType type = FMNotificationType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // If the same message+type is already showing, just reset the timer
    if (_isShowing && _currentMessage == message && _currentType == type) {
      _notificationKey.currentState?.resetTimer();
      // Also drop any queued duplicates of this message+type
      _queue.removeWhere((item) => item.message == message && item.type == type);
      return;
    }

    // Also deduplicate from the queue (same message+type only)
    _queue.removeWhere((item) => item.message == message && item.type == type);

    // Capture OverlayState eagerly while context is still valid
    final overlayState = Overlay.of(context);

    _queue.add(_NotificationItem(
      overlayState: overlayState,
      message: message,
      type: type,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    ));

    if (!_isShowing) {
      _showNext();
    }
  }

  bool _isProcessingQueue = false;

  void _showNext() {
    if (_queue.isEmpty) {
      _isShowing = false;
      _currentMessage = null;
      _currentType = null;
      _isProcessingQueue = false;
      return;
    }

    // Guard against re-entrant calls
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    _isShowing = true;
    final item = _queue.removeAt(0);
    _currentMessage = item.message;
    _currentType = item.type;

    final overlay = item.overlayState;

    // Verify overlay is still mounted before inserting
    if (!overlay.mounted) {
      _isProcessingQueue = false;
      _showNext();
      return;
    }

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: (MediaQuery.maybeOf(context)?.padding.top ?? 0) + AppSpacing.md,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Notification(
            key: _notificationKey,
            message: item.message,
            type: item.type,
            duration: item.duration,
            actionLabel: item.actionLabel,
            onAction: item.onAction,
            onDismiss: () {
              _currentEntry?.remove();
              _currentEntry = null;
              _currentMessage = null;
              _showNext();
            },
          ),
        ),
      ),
    );

    overlay.insert(_currentEntry!);
    _isProcessingQueue = false;
  }

  /// Shows a success notification.
  void success(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: FMNotificationType.success,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  /// Shows an error notification.
  void error(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: FMNotificationType.error,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  /// Shows a warning notification.
  void warning(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: FMNotificationType.warning,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  /// Shows an info notification.
  void info(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message,
      type: FMNotificationType.info,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  /// Dismisses the current notification immediately.
  void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
    _currentMessage = null;
    _currentType = null;
    _showNext();
  }
}

class _NotificationItem {
  final OverlayState overlayState;
  final String message;
  final FMNotificationType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  _NotificationItem({
    required this.overlayState,
    required this.message,
    required this.type,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });
}

/// Extension for easy access from BuildContext.
extension FMNotificationContext on BuildContext {
  void showNotification(
    String message, {
    FMNotificationType type = FMNotificationType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    NotificationOverlay.instance.show(this, message, type: type, duration: duration);
  }

  void showSuccessNotification(String message, {Duration? duration}) {
    HapticHelper.mediumImpact();
    NotificationOverlay.instance.success(this, message, duration: duration);
  }

  void showErrorNotification(String message, {Duration? duration}) {
    HapticHelper.vibrate();
    NotificationOverlay.instance.error(this, message, duration: duration);
  }

  void showWarningNotification(String message, {Duration? duration}) {
    NotificationOverlay.instance.warning(this, message, duration: duration);
  }

  void showInfoNotification(String message, {Duration? duration}) {
    NotificationOverlay.instance.info(this, message, duration: duration);
  }

  void showUndoNotification(String message, VoidCallback onUndo) {
    NotificationOverlay.instance.show(
      this,
      message,
      type: FMNotificationType.success,
      duration: const Duration(seconds: 5),
      actionLabel: 'Undo',
      onAction: onUndo,
    );
  }
}
