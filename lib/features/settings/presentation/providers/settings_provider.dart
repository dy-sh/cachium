import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/database_providers.dart';
import '../../../../core/services/screen_security_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/credential_hasher.dart';
import '../../../transactions/data/models/transaction.dart';
import '../../data/models/app_settings.dart';
import '../../data/services/credential_migration_service.dart';

const _log = AppLogger('SettingsProvider');

final credentialMigrationServiceProvider = Provider<CredentialMigrationService>(
  (ref) => const CredentialMigrationService(),
);

/// Resolves once credential migration has run (or been skipped because no
/// upgrade was needed). Callers that verify credentials — e.g. the lock
/// screen — must await this before letting the user authenticate, otherwise
/// they can race the migration and verify against a legacy hash.
final credentialMigrationReadyProvider = FutureProvider<void>((ref) async {
  await ref.watch(settingsProvider.future);
  await ref.read(settingsProvider.notifier).migrateCredentialsIfNeeded();
});

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repo = ref.watch(settingsRepositoryProvider);

    // Load existing settings from database
    final settings = await repo.loadSettings();

    if (settings != null) {
      final sanitized = _sanitize(settings);
      if (!identical(sanitized, settings)) {
        // Persist the repair so the corrupted value doesn't come back next run.
        await repo.saveSettings(sanitized);
      }
      return sanitized;
    }

    // First run - return defaults and save them
    const defaultSettings = AppSettings();
    await repo.saveSettings(defaultSettings);
    return defaultSettings;
  }

  /// Repair invariants that could silently break downstream logic
  /// (currency lookups, exchange-rate fetches) if a stored value got
  /// corrupted. Returns the same instance if nothing needed repair.
  AppSettings _sanitize(AppSettings s) {
    const defaults = AppSettings();
    var fixed = s;
    final code = s.mainCurrencyCode.trim().toUpperCase();
    final validCode = code.length == 3 && RegExp(r'^[A-Z]{3}$').hasMatch(code);
    if (!validCode) {
      _log.warning('Sanitizing invalid mainCurrencyCode "${s.mainCurrencyCode}" → ${defaults.mainCurrencyCode}');
      fixed = fixed.copyWith(mainCurrencyCode: defaults.mainCurrencyCode);
    } else if (code != s.mainCurrencyCode) {
      fixed = fixed.copyWith(mainCurrencyCode: code);
    }
    return fixed;
  }

  Future<void> _saveAndUpdate(AppSettings newSettings) async {
    final previousState = state;
    try {
      final repo = ref.read(settingsRepositoryProvider);
      state = AsyncData(newSettings);
      await repo.saveSettings(newSettings);
    } catch (e, st) {
      state = previousState;
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> _update(AppSettings Function(AppSettings s) updater) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _saveAndUpdate(updater(current));
  }

  // Appearance
  Future<void> setThemeMode(ThemeModeOption v) => _update((s) => s.copyWith(themeMode: v));
  Future<void> setColorIntensity(ColorIntensity v) => _update((s) => s.copyWith(colorIntensity: v));
  Future<void> setAccentColorIndex(int v) => _update((s) => s.copyWith(accentColorIndex: v));
  Future<void> setAccountCardStyle(AccountCardStyle v) => _update((s) => s.copyWith(accountCardStyle: v));
  Future<void> setTabTransitionsEnabled(bool v) => _update((s) => s.copyWith(tabTransitionsEnabled: v));
  Future<void> setFormAnimationsEnabled(bool v) => _update((s) => s.copyWith(formAnimationsEnabled: v));
  Future<void> setBalanceCountersEnabled(bool v) => _update((s) => s.copyWith(balanceCountersEnabled: v));

  // Formats
  Future<void> setDateFormat(DateFormatOption v) => _update((s) => s.copyWith(dateFormat: v));
  Future<void> setMainCurrencyCode(String v) => _update((s) => s.copyWith(
        mainCurrencyCode: v,
        clearCachedExchangeRates: true,
        lastRateFetchTimestamp: 0,
      ));
  Future<void> setExchangeRateApiOption(ExchangeRateApiOption v) => _update((s) => s.copyWith(exchangeRateApiOption: v));
  Future<void> setLastRateFetchTimestamp(int v) => _update((s) => s.copyWith(lastRateFetchTimestamp: v));
  Future<void> setFirstDayOfWeek(FirstDayOfWeek v) => _update((s) => s.copyWith(firstDayOfWeek: v));

  Future<void> setCachedExchangeRates(String? json) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (json == null) {
      await _saveAndUpdate(current.copyWith(clearCachedExchangeRates: true));
    } else {
      await _saveAndUpdate(current.copyWith(cachedExchangeRates: json));
    }
  }

  // Preferences
  Future<void> setHapticFeedbackEnabled(bool v) => _update((s) => s.copyWith(hapticFeedbackEnabled: v));
  Future<void> setStartScreen(StartScreen v) => _update((s) => s.copyWith(startScreen: v));
  Future<void> setLastUsedAccountId(String? v) => _update((s) => s.copyWith(lastUsedAccountId: v));

  // Transactions
  Future<void> setAutoCategorizeByMerchant(bool v) => _update((s) => s.copyWith(autoCategorizeByMerchant: v));
  Future<void> setSelectLastCategory(bool v) => _update((s) => s.copyWith(selectLastCategory: v));
  Future<void> setSelectLastAccount(bool v) => _update((s) => s.copyWith(selectLastAccount: v));
  Future<void> setAccountsFoldedCount(int v) => _update((s) => s.copyWith(accountsFoldedCount: v));
  Future<void> setCategoriesFoldedCount(int v) => _update((s) => s.copyWith(categoriesFoldedCount: v));
  Future<void> setCategorySortOption(CategorySortOption v) => _update((s) => s.copyWith(categorySortOption: v));
  Future<void> setShowAddAccountButton(bool v) => _update((s) => s.copyWith(showAddAccountButton: v));
  Future<void> setShowAddCategoryButton(bool v) => _update((s) => s.copyWith(showAddCategoryButton: v));
  Future<void> setDefaultTransactionType(TransactionType v) => _update((s) => s.copyWith(defaultTransactionType: v));
  Future<void> setAllowZeroAmount(bool v) => _update((s) => s.copyWith(allowZeroAmount: v));
  Future<void> setTransactionAmountSize(AmountDisplaySize v) => _update((s) => s.copyWith(transactionAmountSize: v));
  Future<void> setAllowSelectParentCategory(bool v) => _update((s) => s.copyWith(allowSelectParentCategory: v));

  Future<void> setLastUsedCategoryId(TransactionType type, String? categoryId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (type == TransactionType.income) {
      await _saveAndUpdate(current.copyWith(lastUsedIncomeCategoryId: categoryId));
    } else {
      await _saveAndUpdate(current.copyWith(lastUsedExpenseCategoryId: categoryId));
    }
  }

  // Assets
  Future<void> setAssetsFoldedCount(int v) => _update((s) => s.copyWith(assetsFoldedCount: v));
  Future<void> setShowAddAssetButton(bool v) => _update((s) => s.copyWith(showAddAssetButton: v));
  Future<void> setAssetSortOption(AssetSortOption v) => _update((s) => s.copyWith(assetSortOption: v));
  Future<void> setShowAssetSelector(bool v) => _update((s) => s.copyWith(showAssetSelector: v));

  // Home Page
  Future<void> setHomeShowAccountsList(bool v) => _update((s) => s.copyWith(homeShowAccountsList: v));
  Future<void> setHomeShowTotalBalance(bool v) => _update((s) => s.copyWith(homeShowTotalBalance: v));
  Future<void> setHomeShowQuickActions(bool v) => _update((s) => s.copyWith(homeShowQuickActions: v));
  Future<void> setHomeShowRecentTransactions(bool v) => _update((s) => s.copyWith(homeShowRecentTransactions: v));
  Future<void> setHomeShowBudgetProgress(bool v) => _update((s) => s.copyWith(homeShowBudgetProgress: v));
  Future<void> setHomeSectionOrder(List<String> v) => _update((s) => s.copyWith(homeSectionOrder: v));
  Future<void> setHomeAccountsTextSize(AmountDisplaySize v) => _update((s) => s.copyWith(homeAccountsTextSize: v));
  Future<void> setHomeTotalBalanceTextSize(AmountDisplaySize v) => _update((s) => s.copyWith(homeTotalBalanceTextSize: v));
  Future<void> setHomeBalancesHiddenByDefault(bool v) => _update((s) => s.copyWith(homeBalancesHiddenByDefault: v));

  // Notifications
  Future<void> setNotificationsEnabled(bool v) => _update((s) => s.copyWith(notificationsEnabled: v));
  Future<void> setBudgetAlertThresholds(List<int> v) => _update((s) => s.copyWith(budgetAlertThresholds: v));
  Future<void> setRecurringRemindersEnabled(bool v) => _update((s) => s.copyWith(recurringRemindersEnabled: v));
  Future<void> setRecurringReminderAdvanceDays(int v) => _update((s) => s.copyWith(recurringReminderAdvanceDays: v));
  Future<void> setWeeklySpendingSummaryEnabled(bool v) => _update((s) => s.copyWith(weeklySpendingSummaryEnabled: v));
  Future<void> setWeeklySpendingSummaryDay(int v) => _update((s) => s.copyWith(weeklySpendingSummaryDay: v));

  // Recurring
  Future<void> setAutoGenerateRecurring(bool v) => _update((s) => s.copyWith(autoGenerateRecurring: v));

  // Security
  Future<void> setAppLockEnabled(bool v) => _update((s) => s.copyWith(appLockEnabled: v));
  Future<void> setAutoLockTimeout(AutoLockTimeout v) => _update((s) => s.copyWith(autoLockTimeout: v));
  Future<void> setBiometricUnlockEnabled(bool v) => _update((s) => s.copyWith(biometricUnlockEnabled: v));

  Future<void> setHideFromScreenshots(bool v) async {
    // Apply to the OS first so toggling off takes effect immediately, even
    // if the save races. Save is still optimistic-with-rollback via _update.
    await const ScreenSecurityService().setSecure(v);
    await _update((s) => s.copyWith(hideFromScreenshots: v));
  }

  Future<void> setAppPinCode(String? pin) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (pin == null) {
      await _saveAndUpdate(current.copyWith(clearAppPinCode: true));
    } else {
      final hashed = await CredentialHasher.hash(pin);
      await _saveAndUpdate(current.copyWith(appPinCode: hashed));
    }
  }

  Future<void> setAppPassword(String? password) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (password == null) {
      await _saveAndUpdate(current.copyWith(clearAppPassword: true));
    } else {
      final hashed = await CredentialHasher.hash(password);
      await _saveAndUpdate(current.copyWith(appPassword: hashed));
    }
  }

  /// Re-hash a credential to PBKDF2 after successful verification.
  /// Called from lock screen when the raw credential is available.
  Future<void> upgradeCredentialIfNeeded({
    String? rawPin,
    String? rawPassword,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final service = ref.read(credentialMigrationServiceProvider);
    final updated = await service.upgradeIfNeeded(
      current,
      rawPin: rawPin,
      rawPassword: rawPassword,
    );
    if (updated == null) return;

    try {
      await _saveAndUpdate(updated);
    } catch (e) {
      _log.warning('Credential PBKDF2 upgrade save failed: $e');
    }
  }

  /// Migrate credentials to current hashing format (PBKDF2).
  /// Handles: plaintext → PBKDF2. SHA-256 is left alone (still verifies).
  /// Called once on app startup if needed.
  Future<void> migrateCredentialsIfNeeded() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final service = ref.read(credentialMigrationServiceProvider);
    final updated = await service.migrateIfNeeded(current);
    if (updated == null) return;

    await _saveAndUpdate(updated);
  }

  // Onboarding
  Future<void> setTutorialCompleted(bool v) => _update((s) => s.copyWith(tutorialCompleted: v));

  Future<void> setOnboardingCompleted(bool completed) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await _saveAndUpdate(current.copyWith(onboardingCompleted: completed));
  }

  /// Refresh settings from database
  Future<void> refresh() async {
    final repo = ref.read(settingsRepositoryProvider);
    final settings = await repo.loadSettings();
    state = AsyncData(settings ?? const AppSettings());
  }

  /// Reset settings to defaults
  Future<void> reset() async {
    const defaultSettings = AppSettings();
    await _saveAndUpdate(defaultSettings);
  }

  /// Reset only settings section (Appearance, Formats, Preferences, Transactions)
  /// Preserves onboardingCompleted
  Future<void> resetSettingsSection() async {
    final current = state.valueOrNull;
    if (current == null) return;

    const defaults = AppSettings();
    final resetSettings = AppSettings(
      // Reset Appearance
      themeMode: defaults.themeMode,
      colorIntensity: defaults.colorIntensity,
      accentColorIndex: defaults.accentColorIndex,
      accountCardStyle: defaults.accountCardStyle,
      tabTransitionsEnabled: defaults.tabTransitionsEnabled,
      formAnimationsEnabled: defaults.formAnimationsEnabled,
      balanceCountersEnabled: defaults.balanceCountersEnabled,
      // Reset Formats
      dateFormat: defaults.dateFormat,
      mainCurrencyCode: defaults.mainCurrencyCode,
      exchangeRateApiOption: defaults.exchangeRateApiOption,
      cachedExchangeRates: defaults.cachedExchangeRates,
      lastRateFetchTimestamp: defaults.lastRateFetchTimestamp,
      firstDayOfWeek: defaults.firstDayOfWeek,
      // Reset Preferences
      hapticFeedbackEnabled: defaults.hapticFeedbackEnabled,
      startScreen: defaults.startScreen,
      lastUsedAccountId: defaults.lastUsedAccountId,
      // Reset Transactions
      autoCategorizeByMerchant: defaults.autoCategorizeByMerchant,
      selectLastCategory: defaults.selectLastCategory,
      selectLastAccount: defaults.selectLastAccount,
      accountsFoldedCount: defaults.accountsFoldedCount,
      categoriesFoldedCount: defaults.categoriesFoldedCount,
      showAddAccountButton: defaults.showAddAccountButton,
      showAddCategoryButton: defaults.showAddCategoryButton,
      defaultTransactionType: defaults.defaultTransactionType,
      allowZeroAmount: defaults.allowZeroAmount,
      categorySortOption: defaults.categorySortOption,
      lastUsedIncomeCategoryId: defaults.lastUsedIncomeCategoryId,
      lastUsedExpenseCategoryId: defaults.lastUsedExpenseCategoryId,
      transactionAmountSize: defaults.transactionAmountSize,
      allowSelectParentCategory: defaults.allowSelectParentCategory,
      // Reset Assets
      assetsFoldedCount: defaults.assetsFoldedCount,
      showAddAssetButton: defaults.showAddAssetButton,
      assetSortOption: defaults.assetSortOption,
      showAssetSelector: defaults.showAssetSelector,
      // Reset Home Page
      homeShowAccountsList: defaults.homeShowAccountsList,
      homeShowTotalBalance: defaults.homeShowTotalBalance,
      homeShowQuickActions: defaults.homeShowQuickActions,
      homeShowRecentTransactions: defaults.homeShowRecentTransactions,
      homeShowBudgetProgress: defaults.homeShowBudgetProgress,
      homeSectionOrder: defaults.homeSectionOrder,
      homeAccountsTextSize: defaults.homeAccountsTextSize,
      homeTotalBalanceTextSize: defaults.homeTotalBalanceTextSize,
      homeBalancesHiddenByDefault: defaults.homeBalancesHiddenByDefault,
      // Reset Security
      appLockEnabled: defaults.appLockEnabled,
      appPinCode: defaults.appPinCode,
      appPassword: defaults.appPassword,
      autoLockTimeout: defaults.autoLockTimeout,
      biometricUnlockEnabled: defaults.biometricUnlockEnabled,
      // Preserve onboarding
      onboardingCompleted: current.onboardingCompleted,
      tutorialCompleted: current.tutorialCompleted,
    );
    await _saveAndUpdate(resetSettings);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

// Helper to reduce boilerplate in convenience providers.
// Falls back to AppSettings defaults when settings haven't loaded yet.
//
// Uses `.select` so each derived provider only rebuilds when its specific
// field changes — without this, changing any one setting would invalidate
// every single convenience provider in the graph, causing a cascade of
// widget rebuilds across the app.
Provider<T> _setting<T>(T Function(AppSettings) select, T fallback) {
  return Provider<T>((ref) {
    return ref.watch(settingsProvider.select((async) {
      final settings = async.valueOrNull;
      return settings != null ? select(settings) : fallback;
    }));
  });
}

// Convenience providers — Appearance
final themeModeProvider = _setting((s) => s.themeMode, ThemeModeOption.dark);
final colorIntensityProvider = _setting((s) => s.colorIntensity, ColorIntensity.prism);
final accentColorProvider = _setting((s) => s.accentColor, const AppSettings().accentColor);
final accountCardStyleProvider = _setting((s) => s.accountCardStyle, AccountCardStyle.dim);
final tabTransitionsEnabledProvider = _setting((s) => s.tabTransitionsEnabled, true);
final formAnimationsEnabledProvider = _setting((s) => s.formAnimationsEnabled, true);
final balanceCountersEnabledProvider = _setting((s) => s.balanceCountersEnabled, true);

// Convenience providers — Formats
final dateFormatProvider = _setting((s) => s.dateFormat, DateFormatOption.mmddyyyy);
final mainCurrencyCodeProvider = _setting((s) => s.mainCurrencyCode, 'USD');
final exchangeRateApiOptionProvider = _setting((s) => s.exchangeRateApiOption, ExchangeRateApiOption.frankfurter);
final firstDayOfWeekProvider = _setting((s) => s.firstDayOfWeek, FirstDayOfWeek.sunday);
final lastRateFetchTimestampProvider = _setting<int?>((s) => s.lastRateFetchTimestamp, null);

// Convenience providers — Preferences
final hapticEnabledProvider = _setting((s) => s.hapticFeedbackEnabled, true);
final startScreenProvider = _setting((s) => s.startScreen, StartScreen.home);
final lastUsedAccountIdProvider = _setting((s) => s.lastUsedAccountId, null);

// Convenience providers — Onboarding
final onboardingCompletedProvider = _setting((s) => s.onboardingCompleted, false);
final tutorialCompletedProvider = _setting((s) => s.tutorialCompleted, false);

// Convenience providers — Transactions
final autoCategorizeByMerchantProvider = _setting((s) => s.autoCategorizeByMerchant, true);
final selectLastCategoryProvider = _setting((s) => s.selectLastCategory, false);
final selectLastAccountProvider = _setting((s) => s.selectLastAccount, true);
final accountsFoldedCountProvider = _setting((s) => s.accountsFoldedCount, 3);
final categoriesFoldedCountProvider = _setting((s) => s.categoriesFoldedCount, 5);
final categorySortOptionProvider = _setting((s) => s.categorySortOption, CategorySortOption.lastUsed);
final showAddAccountButtonProvider = _setting((s) => s.showAddAccountButton, true);
final showAddCategoryButtonProvider = _setting((s) => s.showAddCategoryButton, true);
final defaultTransactionTypeProvider = _setting((s) => s.defaultTransactionType, TransactionType.expense);
final allowZeroAmountProvider = _setting((s) => s.allowZeroAmount, true);
final lastUsedIncomeCategoryIdProvider = _setting((s) => s.lastUsedIncomeCategoryId, null);
final lastUsedExpenseCategoryIdProvider = _setting((s) => s.lastUsedExpenseCategoryId, null);
final transactionAmountSizeProvider = _setting((s) => s.transactionAmountSize, AmountDisplaySize.large);
final allowSelectParentCategoryProvider = _setting((s) => s.allowSelectParentCategory, true);

// Convenience providers — Home Page
final homeShowAccountsListProvider = _setting((s) => s.homeShowAccountsList, true);
final homeShowTotalBalanceProvider = _setting((s) => s.homeShowTotalBalance, true);
final homeShowQuickActionsProvider = _setting((s) => s.homeShowQuickActions, true);
final homeShowRecentTransactionsProvider = _setting((s) => s.homeShowRecentTransactions, true);
final homeShowBudgetProgressProvider = _setting((s) => s.homeShowBudgetProgress, true);
final homeAccountsTextSizeProvider = _setting((s) => s.homeAccountsTextSize, AmountDisplaySize.large);
final homeTotalBalanceTextSizeProvider = _setting((s) => s.homeTotalBalanceTextSize, AmountDisplaySize.large);
final homeBalancesHiddenByDefaultProvider = _setting((s) => s.homeBalancesHiddenByDefault, false);
final homeSectionOrderProvider = _setting((s) => s.homeSectionOrder,
    const ['accounts', 'totalBalance', 'quickActions', 'budgetProgress', 'recentTransactions']);

/// Consolidated home screen configuration to reduce individual provider watches.
class HomeConfig {
  final List<String> sectionOrder;
  final bool showAccountsList;
  final bool showTotalBalance;
  final bool showQuickActions;
  final bool showRecentTransactions;
  final bool showBudgetProgress;

  const HomeConfig({
    this.sectionOrder = const ['accounts', 'totalBalance', 'quickActions', 'budgetProgress', 'recentTransactions'],
    this.showAccountsList = true,
    this.showTotalBalance = true,
    this.showQuickActions = true,
    this.showRecentTransactions = true,
    this.showBudgetProgress = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeConfig &&
          runtimeType == other.runtimeType &&
          _listEquals(sectionOrder, other.sectionOrder) &&
          showAccountsList == other.showAccountsList &&
          showTotalBalance == other.showTotalBalance &&
          showQuickActions == other.showQuickActions &&
          showRecentTransactions == other.showRecentTransactions &&
          showBudgetProgress == other.showBudgetProgress;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sectionOrder),
        showAccountsList,
        showTotalBalance,
        showQuickActions,
        showRecentTransactions,
        showBudgetProgress,
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final homeConfigProvider = Provider<HomeConfig>((ref) {
  return ref.watch(settingsProvider.select((async) {
    final s = async.valueOrNull;
    if (s == null) return const HomeConfig();
    return HomeConfig(
      sectionOrder: s.homeSectionOrder,
      showAccountsList: s.homeShowAccountsList,
      showTotalBalance: s.homeShowTotalBalance,
      showQuickActions: s.homeShowQuickActions,
      showRecentTransactions: s.homeShowRecentTransactions,
      showBudgetProgress: s.homeShowBudgetProgress,
    );
  }));
});

// Convenience providers — Assets
final assetsFoldedCountProvider = _setting((s) => s.assetsFoldedCount, 5);
final showAddAssetButtonProvider = _setting((s) => s.showAddAssetButton, true);
final assetSortOptionProvider = _setting((s) => s.assetSortOption, AssetSortOption.lastUsed);
final showAssetSelectorProvider = _setting((s) => s.showAssetSelector, true);

// Convenience providers — Security
final appLockEnabledProvider = _setting((s) => s.appLockEnabled, false);
final appPinCodeProvider = _setting((s) => s.appPinCode, null);
final appPasswordProvider = _setting((s) => s.appPassword, null);
final autoLockTimeoutProvider = _setting((s) => s.autoLockTimeout, AutoLockTimeout.immediate);
final biometricUnlockEnabledProvider = _setting((s) => s.biometricUnlockEnabled, true);
final hideFromScreenshotsProvider = _setting((s) => s.hideFromScreenshots, true);

// Convenience providers — Recurring
final autoGenerateRecurringProvider = _setting((s) => s.autoGenerateRecurring, false);
