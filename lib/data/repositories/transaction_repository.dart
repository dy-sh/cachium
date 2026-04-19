import '../../core/database/app_database.dart' as db;
import '../../core/database/services/encryption_service.dart';
import '../../core/exceptions/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../features/transactions/data/models/transaction.dart' as ui;
import '../encryption/transaction_data.dart';
import 'corruption_tracker.dart';
import 'decryption_cache.dart';
import 'encrypted_repository_helpers.dart';

const _log = AppLogger('TransactionRepo');

/// Repository for managing encrypted transaction storage.
///
/// Converts between UI Transaction models and encrypted database records.
/// All sensitive data is encrypted before storage and decrypted on retrieval.
///
/// Error Handling:
/// - Throws [RepositoryException] for database/encryption failures
/// - Throws [EntityNotFoundException] when requested entity doesn't exist
/// - Returns null from getTransaction() if not found (for optional lookups)
class TransactionRepository with CorruptionTracker {
  final db.AppDatabase database;
  final EncryptionService encryptionService;
  final _decryptionCache = DecryptionCache<ui.Transaction>(maxEntries: 2000);

  static const _entityType = 'Transaction';

  TransactionRepository({
    required this.database,
    required this.encryptionService,
  });

  /// Convert UI Transaction to internal TransactionData for encryption
  TransactionData _toData(ui.Transaction transaction) {
    return TransactionData(
      id: transaction.id,
      amount: transaction.amount,
      categoryId: transaction.categoryId,
      accountId: transaction.accountId,
      type: transaction.type.name, // 'income', 'expense', or 'transfer'
      note: transaction.note,
      merchant: transaction.merchant,
      destinationAccountId: transaction.destinationAccountId,
      assetId: transaction.assetId,
      isAcquisitionCost: transaction.isAcquisitionCost,
      currency: transaction.currencyCode,
      conversionRate: transaction.conversionRate,
      destinationAmount: transaction.destinationAmount,
      mainCurrencyCode: transaction.mainCurrencyCode,
      mainCurrencyAmount: transaction.mainCurrencyAmount,
      dateMillis: transaction.date.millisecondsSinceEpoch,
      createdAtMillis: transaction.createdAt.millisecondsSinceEpoch,
    );
  }

  /// Convert internal TransactionData to UI Transaction
  ui.Transaction _toTransaction(TransactionData data) {
    return ui.Transaction(
      id: data.id,
      amount: data.amount,
      type: ui.TransactionType.values.firstWhere(
        (e) => e.name == data.type,
        orElse: () => ui.TransactionType.expense,
      ),
      categoryId: data.categoryId,
      accountId: data.accountId,
      destinationAccountId: data.destinationAccountId,
      assetId: data.assetId,
      isAcquisitionCost: data.isAcquisitionCost,
      currencyCode: data.currency,
      conversionRate: data.conversionRate,
      destinationAmount: data.destinationAmount,
      mainCurrencyCode: data.mainCurrencyCode,
      mainCurrencyAmount: data.mainCurrencyAmount,
      date: DateTime.fromMillisecondsSinceEpoch(data.dateMillis),
      note: data.note,
      merchant: data.merchant,
      createdAt: DateTime.fromMillisecondsSinceEpoch(data.createdAtMillis),
    );
  }

  /// Create a new transaction (encrypt and insert)
  ///
  /// Throws [RepositoryException] if encryption or database operation fails.
  Future<void> createTransaction(ui.Transaction transaction) async {
    try {
      transaction.validate();
      final data = _toData(transaction);
      final encryptedBlob = await encryptionService.encrypt(data);

      await database.insertTransaction(
        id: transaction.id,
        date: transaction.date.millisecondsSinceEpoch,
        lastUpdatedAt: transaction.createdAt.millisecondsSinceEpoch,
        encryptedBlob: encryptedBlob,
      );
      _decryptionCache.invalidate(transaction.id);
    } catch (e) {
      throw RepositoryException.create(entityType: _entityType, cause: e);
    }
  }

  /// Create or update a transaction (encrypt and upsert)
  ///
  /// Throws [RepositoryException] if encryption or database operation fails.
  Future<void> upsertTransaction(ui.Transaction transaction) async {
    try {
      transaction.validate();
      final data = _toData(transaction);
      final encryptedBlob = await encryptionService.encrypt(data);

      await database.upsertTransaction(
        id: transaction.id,
        date: transaction.date.millisecondsSinceEpoch,
        lastUpdatedAt: transaction.createdAt.millisecondsSinceEpoch,
        encryptedBlob: encryptedBlob,
      );
      _decryptionCache.invalidate(transaction.id);
    } catch (e) {
      throw RepositoryException.create(entityType: _entityType, cause: e);
    }
  }

  /// Create or update a transaction with raw sync metadata.
  ///
  /// Use this for imports that need to preserve sync-critical fields like
  /// lastUpdatedAt and currency from the source data.
  ///
  /// Throws [RepositoryException] if encryption or database operation fails.
  Future<void> upsertTransactionRaw(
    ui.Transaction transaction, {
    int? lastUpdatedAt,
    bool isDeleted = false,
    String currency = 'USD',
    double conversionRate = 1.0,
    double? destinationAmount,
    String? mainCurrencyCode,
    double? mainCurrencyAmount,
  }) async {
    try {
      final data = TransactionData(
        id: transaction.id,
        amount: transaction.amount,
        categoryId: transaction.categoryId,
        accountId: transaction.accountId,
        type: transaction.type.name,
        note: transaction.note,
        merchant: transaction.merchant,
        destinationAccountId: transaction.destinationAccountId,
        assetId: transaction.assetId,
        isAcquisitionCost: transaction.isAcquisitionCost,
        currency: currency,
        conversionRate: conversionRate,
        destinationAmount: destinationAmount ?? transaction.destinationAmount,
        mainCurrencyCode: mainCurrencyCode ?? transaction.mainCurrencyCode,
        mainCurrencyAmount: mainCurrencyAmount ?? transaction.mainCurrencyAmount,
        dateMillis: transaction.date.millisecondsSinceEpoch,
        createdAtMillis: transaction.createdAt.millisecondsSinceEpoch,
      );
      final encryptedBlob = await encryptionService.encrypt(data);

      final effectiveLastUpdatedAt = lastUpdatedAt ?? DateTime.now().millisecondsSinceEpoch;

      await database.upsertTransaction(
        id: transaction.id,
        date: transaction.date.millisecondsSinceEpoch,
        lastUpdatedAt: effectiveLastUpdatedAt,
        encryptedBlob: encryptedBlob,
        isDeleted: isDeleted,
      );
      _decryptionCache.invalidate(transaction.id);
    } catch (e) {
      throw RepositoryException.create(entityType: _entityType, cause: e);
    }
  }

  /// Get a single transaction by ID (fetch, decrypt, verify)
  ///
  /// Returns null if transaction doesn't exist.
  /// Throws [RepositoryException] if decryption fails.
  Future<ui.Transaction?> getTransaction(String id) async {
    final row = await database.getTransaction(id);
    if (row == null) return null;

    try {
      final cached = _decryptionCache.get(row.id, row.encryptedBlob);
      if (cached != null) return cached;
      final data = await encryptionService.decrypt(
        row.encryptedBlob,
        expectedId: row.id,
        expectedDateMillis: row.date,
      );
      final result = _toTransaction(data);
      _decryptionCache.put(row.id, row.encryptedBlob, result);
      return result;
    } catch (e) {
      throw RepositoryException.decryption(
        entityType: _entityType,
        entityId: id,
        cause: e,
      );
    }
  }

  /// Get a single transaction by ID, throwing if not found.
  ///
  /// Throws [EntityNotFoundException] if transaction doesn't exist.
  /// Throws [RepositoryException] if decryption fails.
  Future<ui.Transaction> getTransactionOrThrow(String id) async {
    final transaction = await getTransaction(id);
    if (transaction == null) {
      throw EntityNotFoundException(entityType: _entityType, entityId: id);
    }
    return transaction;
  }

  Future<({List<ui.Transaction> entities, int corruptedCount})> _decryptRows(
      List<db.Transaction> rows) {
    return decryptRowsWithCache<ui.Transaction, TransactionData, db.Transaction>(
      rows: rows,
      rowId: (row) => row.id,
      rowBlob: (row) => row.encryptedBlob,
      decryptRow: (row) => encryptionService.decrypt(
        row.encryptedBlob,
        expectedId: row.id,
        expectedDateMillis: row.date,
      ),
      toEntity: _toTransaction,
      cache: _decryptionCache,
      log: _log,
      entityType: _entityType,
    );
  }

  /// Get all non-deleted transactions
  ///
  /// Throws [RepositoryException] if fetch or decryption fails.
  Future<List<ui.Transaction>> getAllTransactions() async {
    try {
      final rows = await database.getAllTransactions();
      final result = await _decryptRows(rows);
      updateCorruptedCount(result.corruptedCount);
      return result.entities;
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException.fetch(entityType: _entityType, cause: e);
    }
  }

  /// Get a page of non-deleted transactions ordered by date descending.
  ///
  /// Note: the transactions screen still uses [getAllTransactions] because
  /// its search/filter/grouping pipeline operates on the full in-memory list.
  /// This method is for callers that can work with a bounded window (recent
  /// transactions widgets, dashboard previews, anything that never needs to
  /// filter across unloaded rows).
  ///
  /// Throws [RepositoryException] if fetch or decryption fails.
  Future<List<ui.Transaction>> getTransactionsPaged({
    required int limit,
    int offset = 0,
  }) async {
    try {
      final rows = await database.getTransactionsPaged(limit: limit, offset: offset);
      final result = await _decryptRows(rows);
      updateCorruptedCount(result.corruptedCount);
      return result.entities;
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException.fetch(entityType: _entityType, cause: e);
    }
  }

  /// Fetch a single transaction by id, decrypted. Returns null if no row
  /// exists or if the row is soft-deleted.
  ///
  /// Use this from edit-mode init paths where you only need one row and
  /// don't want to force a full transactions list load just to look up an id.
  ///
  /// Throws [RepositoryException] if fetch or decryption fails.
  Future<ui.Transaction?> getTransactionById(String id) async {
    try {
      final row = await database.getTransaction(id);
      if (row == null) return null;
      final result = await _decryptRows([row]);
      updateCorruptedCount(result.corruptedCount);
      return result.entities.isEmpty ? null : result.entities.first;
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException.fetch(entityType: _entityType, cause: e);
    }
  }

  /// Get all soft-deleted transactions
  ///
  /// Throws [RepositoryException] if fetch or decryption fails.
  Future<List<ui.Transaction>> getAllDeletedTransactions() async {
    try {
      final rows = await database.getAllDeletedTransactions();
      final result = await _decryptRows(rows);
      updateCorruptedCount(result.corruptedCount);
      return result.entities;
    } catch (e) {
      if (e is RepositoryException) rethrow;
      throw RepositoryException.fetch(entityType: _entityType, cause: e);
    }
  }

  /// Update an existing transaction (re-encrypt and update)
  ///
  /// Throws [RepositoryException] if encryption or database operation fails.
  Future<void> updateTransaction(ui.Transaction transaction) async {
    try {
      transaction.validate();
      final data = _toData(transaction);
      final encryptedBlob = await encryptionService.encrypt(data);

      await database.updateTransaction(
        id: transaction.id,
        date: transaction.date.millisecondsSinceEpoch,
        lastUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        encryptedBlob: encryptedBlob,
      );
      _decryptionCache.invalidate(transaction.id);
    } catch (e) {
      throw RepositoryException.update(
        entityType: _entityType,
        entityId: transaction.id,
        cause: e,
      );
    }
  }

  /// Soft delete a transaction (set isDeleted = true)
  ///
  /// Throws [RepositoryException] if database operation fails.
  Future<void> deleteTransaction(String id) async {
    try {
      await database.softDeleteTransaction(
        id,
        DateTime.now().millisecondsSinceEpoch,
      );
      _decryptionCache.invalidate(id);
    } catch (e) {
      throw RepositoryException.delete(
        entityType: _entityType,
        entityId: id,
        cause: e,
      );
    }
  }

  /// Restore a soft-deleted transaction (set isDeleted = false)
  ///
  /// Throws [RepositoryException] if database operation fails.
  Future<void> restoreTransaction(String id) async {
    try {
      await database.restoreTransaction(
        id,
        DateTime.now().millisecondsSinceEpoch,
      );
      _decryptionCache.invalidate(id);
    } catch (e) {
      throw RepositoryException.update(
        entityType: _entityType,
        entityId: id,
        cause: e,
      );
    }
  }

  /// Watch all transactions (for reactive UI)
  ///
  /// Note: Each emission triggers decryption of all rows.
  /// For large datasets, consider pagination or caching.
  /// Corrupted rows are silently skipped to maintain stream stability.
  Stream<List<ui.Transaction>> watchAllTransactions() {
    return database.watchAllTransactions().asyncMap((rows) async {
      final result = await _decryptRows(rows);
      updateCorruptedCount(result.corruptedCount);
      return result.entities;
    });
  }

  /// Check if any transactions exist in the database
  Future<bool> hasTransactions() async {
    return database.hasTransactions();
  }
}
