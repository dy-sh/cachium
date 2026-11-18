# AGENTS.md

Instructions for AI agents (Claude Code, Codex, etc.) working on this repository.

## Critical Rules

1. **No git commits.** Never run `git commit`, `git add`, or use `--commit` flags. The user handles all git operations.
2. **No SnackBar/ScaffoldMessenger.** Use the custom notification system instead (see Notifications below).
3. **No migration logic needed.** The app is not released — just modify the schema directly in `app_database.dart` and bump `schemaVersion`. No `onUpgrade` logic required.
4. **Keep AGENTS.md in sync.** When you add or change rules, conventions, or architectural patterns in this file, ensure changes are reflected here. If you notice AGENTS.md is outdated relative to the codebase, update it proactively.
5. **Run `feature-docs-updater` agent** after completing a new feature to update `docs/features.md` and `docs/features_new.md`.

## Project Overview

**Cachium** — Flutter mobile personal finance app with dark/light theme support.

**Stack:** Flutter (Dart ^3.9.0), Riverpod 2.5.1, GoRouter 14.2.0, Material Design 3, SQLite3, lucide_icons, google_fonts

**Commands:**
```bash
flutter pub get          # Install deps
flutter run              # Debug mode
flutter analyze          # Lint
flutter test             # Tests
./run.sh                 # Run on macOS with log output to /tmp/cachium_log.txt
run.bat                  # Run on Windows with log output to C:\Temp\cachium_log.txt
```

## Architecture

```
lib/
├── main.dart                 # Entry point (ProviderScope)
├── app.dart                  # Theme, routing config
├── core/
│   ├── constants/            # AppColors, AppTypography, AppSpacing, AppRadius
│   ├── database/services/    # Metrics, Export, Import services
│   ├── providers/            # Database & repository providers
│   └── utils/                # Formatters, currency_conversion, haptic_helper
├── data/
│   ├── encryption/           # DTOs for encrypted storage
│   └── repositories/         # Repository classes
├── design_system/            # Reusable components (barrel: design_system.dart)
├── features/                 # Feature modules: accounts, bills, categories, home, settings, transactions
│   └── {feature}/
│       ├── data/models/      # Domain models + enum extensions
│       └── presentation/     # Screens, providers, widgets
└── navigation/               # GoRouter setup, NavigationShell
```

## State Management

- **AsyncNotifier** for entity lists (accounts, transactions, categories)
- **Notifier<T>** for settings and form state
- **Provider** for computed/derived values
- **Provider.family** for parameterized lookups (e.g. `accountByIdProvider`)
- Use `ref.watch()` in ConsumerWidget for reactive updates

## Key Conventions

- **Design system naming:** Semantic names without prefixes (`PrimaryButton`, `SecondaryButton`, `DestructiveButton`, `Surface`, `InputField`, `PageLayout`)
- **Button variants:** `PrimaryButton` (filled accent), `SecondaryButton` (outlined), `DestructiveButton` (red, filled or outlined)
- **Model equality:** `==` and `hashCode` based on `id` only; all models use `copyWith()`
- **Model validation:** Models use `assert()` for invariants (non-negative amounts, valid currency codes, valid month/year ranges). These fire in debug mode to catch bad data early.
- **Enum extensions:** All enums have `displayName`, `color`, `icon` extensions
- **Categories:** Support `parentId` for hierarchy; `DefaultCategories` provides presets
- **Accounts:** Support `customColor`/`customIcon` overrides via `getColorWithIntensity()`
- **Credential hashing:** PIN/password stored as `pbkdf2:<iterations>:<base64-salt>:<base64-hash>` via `CredentialHasher`. Never store plaintext. Use `CredentialHasher.verify()` for comparisons (handles legacy `sha256:` and plaintext fallback). New credentials always use PBKDF2 with 100k iterations.
- **PopScope for forms:** All form screens must wrap their Scaffold in `PopScope` with unsaved-work detection and confirmation dialog.
- **Provider lookups:** Use `accountMapProvider`/`categoryMapProvider` for O(1) lookups by ID. Prefer `accountByIdProvider`/`categoryByIdProvider` which use these maps.
- **Error handling:** Wrap all async operations in try-catch with `context.showErrorNotification()` in screens. Settings provider uses optimistic updates with rollback on error.

## Notifications

Use context extensions — never SnackBar:
```dart
context.showSuccessNotification('Done');
context.showErrorNotification('Failed');
context.showWarningNotification('Warning');
context.showInfoNotification('Info');
```
Located in `lib/design_system/components/feedback/notification.dart`.

## Multi-Currency

- Per-account and per-transaction `currencyCode` independent of main currency
- `conversionRate` multiplier: `amount * conversionRate ~ mainCurrencyAmount`
- `destinationAmount` for cross-currency transfers
- `mainCurrencyCode` / `mainCurrencyAmount` — historical snapshots persisted at save time; never leave null on new records
- Use `roundCurrency()` from `currency_conversion.dart` for all rounding (not inline `toStringAsFixed`). Pass `currencyCode` for currency-aware decimal places (e.g., JPY=0, KWD=3). Use `currencyDecimalPlaces()` to get the correct decimals for a currency.
- Use `conversionGainLoss()` for all gain/loss calculations (returns `double?`, handle null)
- Aggregated totals always in main currency; foreign items show "~ $X,XXX" subtitle
- Exchange rates: Open ER-API (free) or Manual rates at `/settings/formats/manual-rates`

## Theme System

- **Dark/Light/System** theme modes via `ThemeModeOption` enum in `app_settings.dart`
- `AppColors` uses a static `isDarkMode` flag — theme-dependent colors are getters, not `const`
- **Do NOT use `const`** with theme-dependent `AppColors` values: `background`, `surface`, `surfaceLight`, `border`, `borderSelected`, `textPrimary`, `textSecondary`, `textTertiary`, `accentPrimary`, `selectionGlow`, `navActive`, `navInactive`
- Hue-based colors (red, green, cyan, etc.) remain `static const` and are safe in `const` contexts
- `CachiumApp.applyThemeMode()` sets `AppColors.isDarkMode` and updates system chrome
- `themeModeProvider` provides the current theme mode setting

## Color System

`ColorIntensity` enum (`prism`/`zen`/`neon`) in `app_settings.dart` drives global color saturation.

Key `AppColors` methods: `getAccountColor()`, `getTransactionColor()`, `getCategoryColors()`, `getAccentColor()`, plus opacity and color manipulation helpers.

## Bills & Reminders

- Bill model in `lib/features/bills/data/models/bill.dart` with due dates, frequency, reminder settings
- Encrypted storage like other entities (BillData freezed DTO)
- `billsProvider` (AsyncNotifier), `upcomingBillsProvider`, `overdueBillsProvider`
- `markAsPaid` creates an expense transaction and generates the next recurring bill
- Routes: `/settings/bills`, `/bill/new`, `/bill/:id/edit`

## Budget Rollover

- Per-budget `rolloverEnabled` flag (default: false)
- Effective budget = current month amount + rollover from previous months
- Cascading rollover up to 12 months; overspending produces zero rollover (clamped)
- `BudgetProgress.effectiveBudget` used for progress calculations

## Security

- **SQLite exports are always encrypted.** `DatabaseExportService.exportToSqlite` has no plaintext code path. CSV exports can be plaintext (for spreadsheet analysis) but `export_screen.dart` shows a hard warning dialog before writing.
- **PBKDF2 iteration bounds on verify.** `CredentialHasher` caps the iteration count read from a stored hash at `[1000, 1_000_000]`. Outside that range, verify returns false — defense-in-depth against tampered storage.
- **Exchange rate HTTP client is hardened.** `exchange_rate_service.dart` uses an `HttpClient` with explicit `badCertificateCallback` rejection, connection and request timeouts, and a hostname allowlist. No SPKI pinning yet (see TODO in file) — requires a cert-watch process for the upstream APIs.
- **Screen protection (Android FLAG_SECURE).** User-togglable via `hideFromScreenshots` setting, default on. Routed through `ScreenSecurityService` → `MethodChannel('cachium/security')` → `MainActivity.kt`. `MainActivity.onCreate` applies FLAG_SECURE before Flutter attaches so the first frame is also hidden. Toggling flows through `settingsProvider.setHideFromScreenshots` and is reconciled on app gate build via `ref.listen`. iOS has no equivalent per-activity flag — TODO: blur-overlay on background.
- **Auto-lock lifecycle.** `AppLockStateNotifier.onBackground()` preserves the *earliest* background timestamp across rapid background/foreground cycles via `_backgroundedAt ??= DateTime.now()`. `lock()` clears the timestamp so re-backgrounding starts a fresh timer. `app.dart` routes `paused` and `hidden` lifecycle states to `onBackground`; `inactive` is ignored (iOS fires it on control-center pulldowns).
- **Startup is non-blocking.** `main.dart` kicks off the encryption key pre-warm, settings load, credential migration, and notification init as `unawaited` futures after `runApp`, so first paint is not blocked by secure-storage latency. The app gate's existing `shouldShowWelcomeProvider` loading state covers the window until settings resolve.

## Performance

- **Holdings and liabilities are memoized.** Use `totalHoldingsProvider` / `totalLiabilitiesProvider` in `accounts_provider.dart` instead of folding over the account list inside widget builds. These only re-run when `accountsProvider`, `mainCurrencyCodeProvider`, or `exchangeRatesProvider` actually change.
- **`_setting` helper uses `.select`.** Every convenience provider in `settings_provider.dart` (e.g., `themeModeProvider`, `mainCurrencyCodeProvider`) is now selective — changing one setting no longer invalidates every derived provider. When adding a new convenience provider, use `_setting((s) => s.field, fallback)`.
- **Paged transaction fetch is available.** `transactionRepository.getTransactionsPaged(limit:, offset:)` and `appDatabase.getTransactionsPaged` exist for callers that can work with a bounded window (recent-transactions widgets, dashboard previews). The main transactions screen still loads all rows because its search/filter/grouping pipeline operates on the full in-memory list.

## File Layout Conventions (Large Files)

When a feature file grows past ~800 lines, prefer one of these splits:

- **Provider queries vs CRUD.** `transactions_provider.dart` holds the `TransactionsNotifier` CRUD surface and re-exports derived query/filter/search providers from `transaction_queries.dart`. Callers that `import 'transactions_provider.dart'` get both.
- **Screen + part widgets.** `assets_screen.dart` uses `part 'assets_screen_widgets.dart'` to split private child widgets into a sibling file while keeping library-private scoping (access to `_AssetTab`, `_AssetsScreenState`, etc.).
- **Orchestrator + concern-specific extension parts.** `csv_importer.dart` keeps the bulk-import path in the main file and has `csv_importer_skip_duplicates.dart` as a `part` file with an `extension CsvImporterSkipDuplicates on CsvImporter` that adds the reconciliation methods.

## Key Files

- `lib/app.dart` — Theme and routing (dark/light ThemeData, gated by welcome/lock/main screens)
- `lib/main.dart` — Entry point (SystemChrome setup, provider container)
- `lib/navigation/app_router.dart` — Routes (`AppRoutes` constants)
- `lib/core/constants/app_colors.dart` — Theme-aware color system (dark/light variants)
- `lib/core/database/app_database.dart` — Database schema (version 28)
- `lib/core/utils/currency_conversion.dart` — `conversionGainLoss()`, `roundCurrency()`
- `lib/core/utils/credential_hasher.dart` — PBKDF2 credential hashing (with legacy SHA-256 and plaintext migration, iteration cap on verify)
- `lib/core/services/screen_security_service.dart` — Android FLAG_SECURE bridge (MethodChannel `cachium/security`)
- `android/app/src/main/kotlin/com/example/cachium/MainActivity.kt` — MethodChannel handler for `setSecure`, defaults to secure on Activity onCreate
- `lib/features/settings/data/models/app_settings.dart` — Settings model + ThemeModeOption + ColorIntensity + AutoLockTimeout + hideFromScreenshots
- `lib/design_system/components/feedback/notification.dart` — Custom notifications
- `lib/core/services/exchange_rate_service.dart` — Exchange rate fetching (hardened HttpClient with timeouts + host allowlist)
- `lib/features/bills/` — Bill reminders feature module
- `lib/features/budgets/` — Budgets with rollover support
