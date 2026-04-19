part of 'two_panel_mapping_view.dart';

/// Pure preview-state lookups extracted from [_TwoPanelMappingViewState].
///
/// These helpers don't touch widget mutable state — they read the import
/// state object and return mapping metadata. Lives here so the main widget
/// file stays focused on layout, scroll synchronization, and rendering.
extension _TwoPanelMappingPreviewLookups on _TwoPanelMappingViewState {
  /// Get the CSV column that a field is mapped to (for preview from left side)
  String? _getCsvColumnForPreviewField(
      String fieldKey, FlexibleCsvImportState state) {
    // Regular field
    final csvColumn = state.getCsvColumnForField(fieldKey);
    if (csvColumn != null) return csvColumn;

    // Amount fields
    if (fieldKey == 'amount:header' || fieldKey == 'amount:amount') {
      return state.amountConfig.amountColumn;
    }
    if (fieldKey == 'amount:type') {
      return state.amountConfig.typeColumn;
    }

    // Category FK
    if (fieldKey == 'fk:category:header' || fieldKey == 'fk:category:name') {
      return state.categoryConfig.nameColumn;
    }
    if (fieldKey == 'fk:category:id') {
      return state.categoryConfig.idColumn;
    }

    // Account FK
    if (fieldKey == 'fk:account:header' || fieldKey == 'fk:account:name') {
      return state.accountConfig.nameColumn;
    }
    if (fieldKey == 'fk:account:id') {
      return state.accountConfig.idColumn;
    }

    return null;
  }

  /// Get the field key that a CSV column is mapped to (for preview from right side)
  String? _getFieldKeyForPreviewCsvColumn(
    String csvColumn,
    FlexibleCsvImportState state,
    Map<String, String> csvColumnFieldKey,
  ) {
    // Check regular fields first
    if (csvColumnFieldKey.containsKey(csvColumn)) {
      return csvColumnFieldKey[csvColumn];
    }

    // Check amount
    if (csvColumn == state.amountConfig.amountColumn) {
      return 'amount:amount';
    }
    if (csvColumn == state.amountConfig.typeColumn) {
      return 'amount:type';
    }

    // Check category FK
    if (csvColumn == state.categoryConfig.nameColumn) {
      return 'fk:category:name';
    }
    if (csvColumn == state.categoryConfig.idColumn) {
      return 'fk:category:id';
    }

    // Check account FK
    if (csvColumn == state.accountConfig.nameColumn) {
      return 'fk:account:name';
    }
    if (csvColumn == state.accountConfig.idColumn) {
      return 'fk:account:id';
    }

    return null;
  }

  /// Get which section (amount, category, account) a CSV column belongs to.
  /// Returns null if not mapped to any FK/Amount section.
  String? _getSectionForCsvColumn(
      String csvColumn, FlexibleCsvImportState state) {
    // Check amount
    if (csvColumn == state.amountConfig.amountColumn ||
        csvColumn == state.amountConfig.typeColumn) {
      return 'amount';
    }

    // Check category FK
    if (csvColumn == state.categoryConfig.nameColumn ||
        csvColumn == state.categoryConfig.idColumn) {
      return 'category';
    }

    // Check account FK
    if (csvColumn == state.accountConfig.nameColumn ||
        csvColumn == state.accountConfig.idColumn) {
      return 'account';
    }

    return null;
  }

  /// Get which section (amount, category, account) a field key belongs to.
  /// Returns null if it's a regular field.
  String? _getSectionForFieldKey(String fieldKey) {
    if (fieldKey.startsWith('amount:')) return 'amount';
    if (fieldKey.startsWith('fk:category:')) return 'category';
    if (fieldKey.startsWith('fk:account:')) return 'account';
    return null;
  }
}
