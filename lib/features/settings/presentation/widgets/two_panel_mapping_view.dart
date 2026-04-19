import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/field_mapping_options.dart';
import '../../data/models/flexible_csv_import_config.dart';
import '../../data/models/flexible_csv_import_state.dart';
import '../providers/flexible_csv_import_providers.dart';
import '../providers/settings_provider.dart';
import 'csv_column_list_item.dart';
import 'expandable_amount_item.dart';
import 'expandable_target_field_item.dart';
import 'mapping_connection.dart';
import 'mapping_connection_painter.dart';
import 'target_field_list_item.dart';

part 'two_panel_mapping_view_preview.dart';

/// A two-panel view for mapping CSV columns to app fields.
/// Left panel: Target app fields
/// Right panel: CSV columns with sample values
class TwoPanelMappingView extends ConsumerStatefulWidget {
  /// The list of app field definitions.
  final List<AppFieldDefinition> fields;

  const TwoPanelMappingView({
    super.key,
    required this.fields,
  });

  @override
  ConsumerState<TwoPanelMappingView> createState() =>
      _TwoPanelMappingViewState();
}

class _TwoPanelMappingViewState extends ConsumerState<TwoPanelMappingView> {
  // Scroll controllers for both panels
  final _leftScrollController = ScrollController();
  final _rightScrollController = ScrollController();

  // Keys for tracking element positions
  final _rowKey = GlobalKey();
  final _gapKey = GlobalKey();

  // Keys for left panel items
  final Map<String, GlobalKey> _leftItemKeys = {};
  // Keys for right panel items (CSV columns)
  final Map<String, GlobalKey> _rightItemKeys = {};

  // Cached positions for drawing connections
  Map<String, double> _leftItemPositions = {};
  Map<String, double> _rightItemPositions = {};
  double _gapStart = 0;
  double _gapEnd = 0;
  double _contentTop = 0;
  double _contentBottom = 0;

  // Preview state (when holding an element)
  String? _previewFieldKey;
  String? _previewCsvColumn;

  @override
  void initState() {
    super.initState();
    _leftScrollController.addListener(_onScroll);
    _rightScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _leftScrollController.removeListener(_onScroll);
    _rightScrollController.removeListener(_onScroll);
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _updatePositions();
  }

  void _updatePositions() {
    if (!mounted) return;

    // Get the row's RenderBox for reference
    final rowRenderBox =
        _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowRenderBox == null) return;

    // Get gap position
    final gapRenderBox =
        _gapKey.currentContext?.findRenderObject() as RenderBox?;
    if (gapRenderBox != null) {
      final gapOffset = gapRenderBox.localToGlobal(Offset.zero);
      final rowOffset = rowRenderBox.localToGlobal(Offset.zero);
      _gapStart = gapOffset.dx - rowOffset.dx;
      _gapEnd = _gapStart + gapRenderBox.size.width;
    }

    // Calculate content bounds (the area where list content is visible)
    final rowOffset = rowRenderBox.localToGlobal(Offset.zero);
    // Account for the panel headers (approximately 40 pixels including spacing)
    _contentTop = 40;
    _contentBottom = rowRenderBox.size.height;

    // Update left item positions
    final newLeftPositions = <String, double>{};
    for (final entry in _leftItemKeys.entries) {
      final key = entry.value;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final itemOffset = renderBox.localToGlobal(Offset.zero);
        final relativeY = itemOffset.dy - rowOffset.dy + renderBox.size.height / 2;
        newLeftPositions[entry.key] = relativeY;
      }
    }

    // Update right item positions
    final newRightPositions = <String, double>{};
    for (final entry in _rightItemKeys.entries) {
      final key = entry.value;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final itemOffset = renderBox.localToGlobal(Offset.zero);
        final relativeY = itemOffset.dy - rowOffset.dy + renderBox.size.height / 2;
        newRightPositions[entry.key] = relativeY;
      }
    }

    // Only rebuild if positions actually changed
    if (_positionsChanged(newLeftPositions, newRightPositions)) {
      setState(() {
        _leftItemPositions = newLeftPositions;
        _rightItemPositions = newRightPositions;
      });
    }
  }

  bool _positionsChanged(
    Map<String, double> newLeft,
    Map<String, double> newRight,
  ) {
    if (newLeft.length != _leftItemPositions.length) return true;
    if (newRight.length != _rightItemPositions.length) return true;

    for (final entry in newLeft.entries) {
      if (_leftItemPositions[entry.key] != entry.value) return true;
    }
    for (final entry in newRight.entries) {
      if (_rightItemPositions[entry.key] != entry.value) return true;
    }
    return false;
  }

  GlobalKey _getLeftItemKey(String key) {
    return _leftItemKeys.putIfAbsent(key, () => GlobalKey());
  }

  GlobalKey _getRightItemKey(String column) {
    return _rightItemKeys.putIfAbsent(column, () => GlobalKey());
  }

  void _setPreviewField(String? fieldKey) {
    if (_previewFieldKey != fieldKey) {
      setState(() {
        _previewFieldKey = fieldKey;
        _previewCsvColumn = null;
      });
    }
  }

  void _setPreviewCsvColumn(String? csvColumn) {
    if (_previewCsvColumn != csvColumn) {
      setState(() {
        _previewCsvColumn = csvColumn;
        _previewFieldKey = null;
      });
    }
  }

  void _clearPreview() {
    if (_previewFieldKey != null || _previewCsvColumn != null) {
      setState(() {
        _previewFieldKey = null;
        _previewCsvColumn = null;
      });
    }
  }

  // Preview-state lookups (_getCsvColumnForPreviewField,
  // _getFieldKeyForPreviewCsvColumn, _getSectionForCsvColumn,
  // _getSectionForFieldKey) live in two_panel_mapping_view_preview.dart.

  List<MappingConnection> _buildConnections(
    FlexibleCsvImportState state,
    Map<String, int> fieldColorIndices,
    List<AppFieldDefinition> displayFields,
    ColorIntensity intensity,
    bool isTransaction,
    Map<String, String> csvColumnFieldKey,
  ) {
    final connections = <MappingConnection>[];
    final selectedFieldKey = state.selectedFieldKey;

    // Determine the active section (for FK/Amount, we show all connections in the section)
    final String? activeSection = _previewFieldKey != null
        ? _getSectionForFieldKey(_previewFieldKey!)
        : _previewCsvColumn != null
            ? _getSectionForCsvColumn(_previewCsvColumn!, state)
            : selectedFieldKey != null
                ? _getSectionForFieldKey(selectedFieldKey)
                : null;

    // Determine the active filter (preview takes priority over selection)
    final String? activeFieldKey;
    final String? activeCsvColumn;

    if (_previewFieldKey != null) {
      activeFieldKey = _previewFieldKey;
      activeCsvColumn = _getCsvColumnForPreviewField(_previewFieldKey!, state);
    } else if (_previewCsvColumn != null) {
      activeCsvColumn = _previewCsvColumn;
      activeFieldKey = _getFieldKeyForPreviewCsvColumn(
        _previewCsvColumn!,
        state,
        csvColumnFieldKey,
      );
    } else if (selectedFieldKey != null) {
      activeFieldKey = selectedFieldKey;
      activeCsvColumn = _getCsvColumnForPreviewField(selectedFieldKey, state);
    } else {
      activeFieldKey = null;
      activeCsvColumn = null;
    }

    // Helper to check if a connection should be shown
    bool shouldShowConnection(String fieldKey, String csvColumn) {
      // If nothing is active, show all connections
      if (activeFieldKey == null && activeCsvColumn == null) return true;

      // If we have an active section (FK/Amount), show ALL connections in that section
      if (activeSection != null) {
        final connectionSection = _getSectionForFieldKey(fieldKey);
        if (connectionSection == activeSection) return true;
      }

      // Check if this connection matches the active field or CSV column
      if (activeFieldKey != null) {
        if (fieldKey == activeFieldKey) return true;

        // For header keys, check if the active field is a sub-field
        if (fieldKey == 'amount:header' &&
            activeFieldKey.startsWith('amount:')) {
          return true;
        }
        if (fieldKey == 'fk:category:header' &&
            activeFieldKey.startsWith('fk:category:')) {
          return true;
        }
        if (fieldKey == 'fk:account:header' &&
            activeFieldKey.startsWith('fk:account:')) {
          return true;
        }
      }

      if (activeCsvColumn != null && csvColumn == activeCsvColumn) {
        return true;
      }

      return false;
    }

    // Build connections for regular fields
    for (final field in displayFields) {
      final csvColumn = state.getCsvColumnForField(field.key);
      if (csvColumn != null) {
        if (!shouldShowConnection(field.key, csvColumn)) continue;

        final leftY = _leftItemPositions[field.key];
        final rightY = _rightItemPositions[csvColumn];
        if (leftY != null && rightY != null) {
          final colorIndex = fieldColorIndices[field.key] ?? 1;
          connections.add(MappingConnection(
            fieldKey: field.key,
            csvColumn: csvColumn,
            leftY: leftY,
            rightY: rightY,
            color: getFieldColor(field.key, colorIndex, intensity),
          ));
        }
      }
    }

    // Build connections for FK/Amount sections (transactions only)
    if (isTransaction) {
      // Amount section
      final amountConfig = state.amountConfig;
      final amountColor = getAmountColor(intensity);

      // Amount column connection
      if (amountConfig.amountColumn != null) {
        final String leftKey;
        if (state.expandedForeignKey == 'amount') {
          leftKey = 'amount:amount';
        } else {
          leftKey = 'amount:header';
        }

        if (shouldShowConnection(leftKey, amountConfig.amountColumn!)) {
          final leftY = _leftItemPositions[leftKey];
          final rightY = _rightItemPositions[amountConfig.amountColumn];
          if (leftY != null && rightY != null) {
            connections.add(MappingConnection(
              fieldKey: leftKey,
              csvColumn: amountConfig.amountColumn!,
              leftY: leftY,
              rightY: rightY,
              color: amountColor,
            ));
          }
        }
      }

      // Type column connection
      if (amountConfig.mode == AmountResolutionMode.separateAmountAndType &&
          amountConfig.typeColumn != null) {
        final String leftKey;
        if (state.expandedForeignKey == 'amount') {
          leftKey = 'amount:type';
        } else {
          leftKey = 'amount:header';
        }

        if (shouldShowConnection(leftKey, amountConfig.typeColumn!)) {
          final leftY = _leftItemPositions[leftKey];
          final rightY = _rightItemPositions[amountConfig.typeColumn];
          if (leftY != null && rightY != null) {
            connections.add(MappingConnection(
              fieldKey: leftKey,
              csvColumn: amountConfig.typeColumn!,
              leftY: leftY,
              rightY: rightY,
              color: amountColor,
            ));
          }
        }
      }

      // Category FK section
      final categoryConfig = state.categoryConfig;
      if (categoryConfig.mode == ForeignKeyResolutionMode.mapFromCsv) {
        final categoryColor = getForeignKeyColor('category', intensity);

        if (categoryConfig.nameColumn != null) {
          final String leftKey;
          if (state.expandedForeignKey == 'category') {
            leftKey = 'fk:category:name';
          } else {
            leftKey = 'fk:category:header';
          }

          if (shouldShowConnection(leftKey, categoryConfig.nameColumn!)) {
            final leftY = _leftItemPositions[leftKey];
            final rightY = _rightItemPositions[categoryConfig.nameColumn];
            if (leftY != null && rightY != null) {
              connections.add(MappingConnection(
                fieldKey: leftKey,
                csvColumn: categoryConfig.nameColumn!,
                leftY: leftY,
                rightY: rightY,
                color: categoryColor,
              ));
            }
          }
        }

        if (categoryConfig.idColumn != null) {
          final String leftKey;
          if (state.expandedForeignKey == 'category') {
            leftKey = 'fk:category:id';
          } else {
            leftKey = 'fk:category:header';
          }

          if (shouldShowConnection(leftKey, categoryConfig.idColumn!)) {
            final leftY = _leftItemPositions[leftKey];
            final rightY = _rightItemPositions[categoryConfig.idColumn];
            if (leftY != null && rightY != null) {
              connections.add(MappingConnection(
                fieldKey: leftKey,
                csvColumn: categoryConfig.idColumn!,
                leftY: leftY,
                rightY: rightY,
                color: categoryColor,
              ));
            }
          }
        }
      }

      // Account FK section
      final accountConfig = state.accountConfig;
      if (accountConfig.mode == ForeignKeyResolutionMode.mapFromCsv) {
        final accountColor = getForeignKeyColor('account', intensity);

        if (accountConfig.nameColumn != null) {
          final String leftKey;
          if (state.expandedForeignKey == 'account') {
            leftKey = 'fk:account:name';
          } else {
            leftKey = 'fk:account:header';
          }

          if (shouldShowConnection(leftKey, accountConfig.nameColumn!)) {
            final leftY = _leftItemPositions[leftKey];
            final rightY = _rightItemPositions[accountConfig.nameColumn];
            if (leftY != null && rightY != null) {
              connections.add(MappingConnection(
                fieldKey: leftKey,
                csvColumn: accountConfig.nameColumn!,
                leftY: leftY,
                rightY: rightY,
                color: accountColor,
              ));
            }
          }
        }

        if (accountConfig.idColumn != null) {
          final String leftKey;
          if (state.expandedForeignKey == 'account') {
            leftKey = 'fk:account:id';
          } else {
            leftKey = 'fk:account:header';
          }

          if (shouldShowConnection(leftKey, accountConfig.idColumn!)) {
            final leftY = _leftItemPositions[leftKey];
            final rightY = _rightItemPositions[accountConfig.idColumn];
            if (leftY != null && rightY != null) {
              connections.add(MappingConnection(
                fieldKey: leftKey,
                csvColumn: accountConfig.idColumn!,
                leftY: leftY,
                rightY: rightY,
                color: accountColor,
              ));
            }
          }
        }
      }
    }

    return connections;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flexibleCsvImportProvider);
    final intensity = ref.watch(colorIntensityProvider);
    final selectedFieldKey = state.selectedFieldKey;
    final expandedForeignKey = state.expandedForeignKey;

    if (state.config == null) return const SizedBox.shrink();

    final config = state.config!;
    final csvHeaders = config.csvHeaders;
    final isTransaction = config.entityType == ImportEntityType.transaction;

    // For transactions, filter out individual FK fields and amount/type fields
    // (we show consolidated Category/Account/Amount sections instead)
    final displayFields = isTransaction
        ? widget.fields
            .where(
                (f) => !f.isForeignKey && f.key != 'amount' && f.key != 'type')
            .toList()
        : widget.fields;

    // Build field color indices (fixed based on position in list)
    final fieldColorIndices = <String, int>{};
    for (var i = 0; i < displayFields.length; i++) {
      fieldColorIndices[displayFields[i].key] =
          i + 1; // 1-based for getFieldBadgeColor
    }

    // Build CSV column -> field info maps (for showing which field a column is mapped to)
    final csvColumnColorIndex = <String, int>{};
    final csvColumnFieldKey = <String, String>{};
    for (final field in displayFields) {
      final csvColumn = state.getCsvColumnForField(field.key);
      if (csvColumn != null) {
        csvColumnColorIndex[csvColumn] = fieldColorIndices[field.key]!;
        csvColumnFieldKey[csvColumn] = field.key;
      }
    }

    // Build the list of items for the left panel (target fields)
    final leftPanelItems = <Widget>[];

    // For transactions, add Amount, Category, and Account at the top
    if (isTransaction) {
      // Check if Amount section should be highlighted
      final amountConfig = state.amountConfig;
      final isAmountHighlighted =
          // Highlighted when holding this header
          (_previewFieldKey == 'amount:header' ||
              _previewFieldKey?.startsWith('amount:') == true) ||
          // Highlighted when holding a paired CSV column
          (_previewCsvColumn != null &&
              (_previewCsvColumn == amountConfig.amountColumn ||
                  _previewCsvColumn == amountConfig.typeColumn));

      // Check if Category section should be highlighted
      final categoryConfig = state.categoryConfig;
      final isCategoryHighlighted =
          // Highlighted when holding this header
          (_previewFieldKey == 'fk:category:header' ||
              _previewFieldKey?.startsWith('fk:category:') == true) ||
          // Highlighted when holding a paired CSV column
          (_previewCsvColumn != null &&
              (_previewCsvColumn == categoryConfig.nameColumn ||
                  _previewCsvColumn == categoryConfig.idColumn));

      // Check if Account section should be highlighted
      final accountConfig = state.accountConfig;
      final isAccountHighlighted =
          // Highlighted when holding this header
          (_previewFieldKey == 'fk:account:header' ||
              _previewFieldKey?.startsWith('fk:account:') == true) ||
          // Highlighted when holding a paired CSV column
          (_previewCsvColumn != null &&
              (_previewCsvColumn == accountConfig.nameColumn ||
                  _previewCsvColumn == accountConfig.idColumn));

      leftPanelItems.add(
        GestureDetector(
          onLongPressStart: (_) => _setPreviewField('amount:header'),
          onLongPressEnd: (_) => _clearPreview(),
          onLongPressCancel: _clearPreview,
          child: _PositionTrackingWrapper(
            itemKey: _getLeftItemKey('amount:header'),
            child: ExpandableAmountItem(
              isExpanded: expandedForeignKey == 'amount',
              onToggleExpand: () => _handleToggleExpandedSection(ref, 'amount'),
              intensity: intensity,
              hasCsvColumnSelected: selectedFieldKey != null ||
                  _previewFieldKey != null ||
                  _previewCsvColumn != null,
              isHighlighted: isAmountHighlighted,
              getPositionKey: _getLeftItemKey,
              onPreviewStart: _setPreviewField,
              onPreviewEnd: _clearPreview,
            ),
          ),
        ),
      );
      leftPanelItems.add(const SizedBox(height: AppSpacing.xs));
      leftPanelItems.add(
        GestureDetector(
          onLongPressStart: (_) => _setPreviewField('fk:category:header'),
          onLongPressEnd: (_) => _clearPreview(),
          onLongPressCancel: _clearPreview,
          child: _PositionTrackingWrapper(
            itemKey: _getLeftItemKey('fk:category:header'),
            child: ExpandableForeignKeyItem(
              foreignKey: 'category',
              displayName: 'Category',
              icon: LucideIcons.tag,
              isExpanded: expandedForeignKey == 'category',
              onToggleExpand: () =>
                  _handleToggleExpandedSection(ref, 'category'),
              intensity: intensity,
              hasCsvColumnSelected: selectedFieldKey != null ||
                  _previewFieldKey != null ||
                  _previewCsvColumn != null,
              isHighlighted: isCategoryHighlighted,
              getPositionKey: _getLeftItemKey,
              onPreviewStart: _setPreviewField,
              onPreviewEnd: _clearPreview,
            ),
          ),
        ),
      );
      leftPanelItems.add(const SizedBox(height: AppSpacing.xs));
      leftPanelItems.add(
        GestureDetector(
          onLongPressStart: (_) => _setPreviewField('fk:account:header'),
          onLongPressEnd: (_) => _clearPreview(),
          onLongPressCancel: _clearPreview,
          child: _PositionTrackingWrapper(
            itemKey: _getLeftItemKey('fk:account:header'),
            child: ExpandableForeignKeyItem(
              foreignKey: 'account',
              displayName: 'Account',
              icon: LucideIcons.wallet,
              isExpanded: expandedForeignKey == 'account',
              onToggleExpand: () => _handleToggleExpandedSection(ref, 'account'),
              intensity: intensity,
              hasCsvColumnSelected: selectedFieldKey != null ||
                  _previewFieldKey != null ||
                  _previewCsvColumn != null,
              isHighlighted: isAccountHighlighted,
              getPositionKey: _getLeftItemKey,
              onPreviewStart: _setPreviewField,
              onPreviewEnd: _clearPreview,
            ),
          ),
        ),
      );
      leftPanelItems.add(const SizedBox(height: AppSpacing.sm));
      leftPanelItems.add(
        Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
      );
      leftPanelItems.add(const SizedBox(height: AppSpacing.sm));
    }

    // Build connections for the painter
    final connections = _buildConnections(
      state,
      fieldColorIndices,
      displayFields,
      intensity,
      isTransaction,
      csvColumnFieldKey,
    );

    // Schedule position update after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePositions();
    });

    return Stack(
      children: [
        Row(
          key: _rowKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left panel - Target Fields
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PanelHeader(
                    title: 'Target Fields',
                    intensity: intensity,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ListView(
                      controller: _leftScrollController,
                      children: [
                        // FK items (for transactions)
                        ...leftPanelItems,

                        // Regular fields
                        ...displayFields.map((field) {
                          final csvColumn =
                              state.getCsvColumnForField(field.key);
                          final isMapped = csvColumn != null;
                          final colorIndex = fieldColorIndices[field.key]!;
                          final isSelected = selectedFieldKey == field.key;
                          final isPreview = _previewFieldKey == field.key;
                          // Highlight if this field's CSV column is being previewed
                          final isPairedPreview = _previewCsvColumn != null &&
                              csvColumn == _previewCsvColumn;

                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: GestureDetector(
                              onLongPressStart: (_) =>
                                  _setPreviewField(field.key),
                              onLongPressEnd: (_) => _clearPreview(),
                              onLongPressCancel: _clearPreview,
                              child: _PositionTrackingWrapper(
                                itemKey: _getLeftItemKey(field.key),
                                child: TargetFieldListItem(
                                  fieldName: field.displayName,
                                  fieldKey: field.key,
                                  isRequired: field.isRequired,
                                  isMapped: isMapped,
                                  mappedCsvColumn: csvColumn,
                                  isSelected:
                                      isSelected || isPreview || isPairedPreview,
                                  colorIndex: colorIndex,
                                  hasAnySelected: selectedFieldKey != null ||
                                      _previewFieldKey != null ||
                                      _previewCsvColumn != null,
                                  intensity: intensity,
                                  onTap: () => _handleFieldTap(
                                      ref, field.key, isMapped, isSelected),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Gap between panels (used for drawing connections)
            SizedBox(
              key: _gapKey,
              width: AppSpacing.md,
            ),
            // Right panel - CSV Columns
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PanelHeader(
                    title: 'CSV Columns',
                    intensity: intensity,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ListView.separated(
                      controller: _rightScrollController,
                      itemCount: csvHeaders.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final column = csvHeaders[index];
                        final sampleValues = config.getSampleValues(column);

                        // Check which FK or amount this column is mapped to (if any)
                        // Only show FK as mapped when mode is mapFromCsv
                        final categoryConfig = state.categoryConfig;
                        final accountConfig = state.accountConfig;
                        final amountConfig = state.amountConfig;
                        String? fkMappedTo;
                        bool isAmountMapped = false;
                        if (categoryConfig.mode ==
                                ForeignKeyResolutionMode.mapFromCsv &&
                            (column == categoryConfig.nameColumn ||
                                column == categoryConfig.idColumn)) {
                          fkMappedTo = 'category';
                        } else if (accountConfig.mode ==
                                ForeignKeyResolutionMode.mapFromCsv &&
                            (column == accountConfig.nameColumn ||
                                column == accountConfig.idColumn)) {
                          fkMappedTo = 'account';
                        } else if (column == amountConfig.amountColumn ||
                            (amountConfig.mode ==
                                    AmountResolutionMode.separateAmountAndType &&
                                column == amountConfig.typeColumn)) {
                          isAmountMapped = true;
                        }

                        // Get the fixed color index and field key from the mapped field (if mapped to a regular field)
                        final mappedColorIndex = csvColumnColorIndex[column];
                        final mappedFieldKey = csvColumnFieldKey[column];
                        final isMapped = mappedColorIndex != null ||
                            fkMappedTo != null ||
                            isAmountMapped;

                        final isPreview = _previewCsvColumn == column;
                        // Highlight if this column's mapped field is being previewed
                        bool isPairedPreview = false;
                        if (_previewFieldKey != null) {
                          // Check if previewing an FK/Amount field that this column belongs to
                          if (_previewFieldKey!.startsWith('amount:') ||
                              _previewFieldKey == 'amount:header') {
                            // Highlight all amount-related columns
                            isPairedPreview =
                                column == state.amountConfig.amountColumn ||
                                    column == state.amountConfig.typeColumn;
                          } else if (_previewFieldKey!.startsWith('fk:category:') ||
                              _previewFieldKey == 'fk:category:header') {
                            // Highlight all category-related columns
                            isPairedPreview =
                                column == state.categoryConfig.nameColumn ||
                                    column == state.categoryConfig.idColumn;
                          } else if (_previewFieldKey!.startsWith('fk:account:') ||
                              _previewFieldKey == 'fk:account:header') {
                            // Highlight all account-related columns
                            isPairedPreview =
                                column == state.accountConfig.nameColumn ||
                                    column == state.accountConfig.idColumn;
                          } else {
                            // Regular field - check direct mapping
                            isPairedPreview =
                                _getCsvColumnForPreviewField(
                                    _previewFieldKey!, state) ==
                                column;
                          }
                        } else if (_previewCsvColumn != null && _previewCsvColumn != column) {
                          // Check if the previewed CSV column belongs to the same FK/Amount section
                          final previewedSection = _getSectionForCsvColumn(_previewCsvColumn!, state);
                          if (previewedSection != null) {
                            final thisSection = _getSectionForCsvColumn(column, state);
                            isPairedPreview = previewedSection == thisSection;
                          }
                        }

                        return GestureDetector(
                          onLongPressStart: (_) => _setPreviewCsvColumn(column),
                          onLongPressEnd: (_) => _clearPreview(),
                          onLongPressCancel: _clearPreview,
                          child: _PositionTrackingWrapper(
                            itemKey: _getRightItemKey(column),
                            child: CsvColumnListItem(
                              columnName: column,
                              sampleValues: sampleValues,
                              isSelected: isPreview || isPairedPreview,
                              hasAnySelected: selectedFieldKey != null ||
                                  _previewFieldKey != null ||
                                  _previewCsvColumn != null,
                              isMapped: isMapped,
                              mappedFieldColorIndex:
                                  (fkMappedTo != null || isAmountMapped)
                                      ? null
                                      : mappedColorIndex,
                              mappedFieldKey:
                                  (fkMappedTo != null || isAmountMapped)
                                      ? null
                                      : mappedFieldKey,
                              fkMappedTo: isAmountMapped ? 'amount' : fkMappedTo,
                              intensity: intensity,
                              onTap: () => _handleCsvColumnTap(
                                ref,
                                column,
                                mappedColorIndex,
                                isAmountMapped ? 'amount' : fkMappedTo,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Connection lines overlay
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: MappingConnectionPainter(
                connections: connections,
                gapStart: _gapStart,
                gapEnd: _gapEnd,
                topClip: _contentTop,
                bottomClip: _contentBottom,
                isPreviewActive:
                    _previewFieldKey != null || _previewCsvColumn != null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleFieldTap(
      WidgetRef ref, String fieldKey, bool isMapped, bool isSelected) {
    final notifier = ref.read(flexibleCsvImportProvider.notifier);

    if (isMapped) {
      // Already mapped - clear the connection
      notifier.clearConnectionForField(fieldKey);
    } else if (isSelected) {
      // Already selected - deselect
      notifier.selectField(null);
    } else {
      // Select this field
      notifier.selectField(fieldKey);
    }
  }

  void _handleCsvColumnTap(
    WidgetRef ref,
    String column,
    int? mappedColorIndex,
    String? mappedTo, // 'category', 'account', 'amount', or null
  ) {
    final notifier = ref.read(flexibleCsvImportProvider.notifier);
    final state = ref.read(flexibleCsvImportProvider);
    final selectedFieldKey = state.selectedFieldKey;

    if (mappedTo == 'amount') {
      // Already mapped to amount - clear from amount config
      final amountConfig = state.amountConfig;
      if (column == amountConfig.amountColumn) {
        notifier.clearAmountField('amount');
      } else if (column == amountConfig.typeColumn) {
        notifier.clearAmountField('type');
      }
    } else if (mappedTo == 'category' || mappedTo == 'account') {
      // Already mapped to FK - clear from FK config
      final fkKey = mappedTo!; // Safe since we checked above
      final config =
          fkKey == 'category' ? state.categoryConfig : state.accountConfig;
      if (column == config.nameColumn) {
        notifier.clearForeignKeyField(fkKey, 'name');
      } else if (column == config.idColumn) {
        notifier.clearForeignKeyField(fkKey, 'id');
      }
    } else if (mappedColorIndex != null) {
      // Already mapped to a regular field - clear the connection
      notifier.clearConnectionForCsvColumn(column);
    } else if (selectedFieldKey != null) {
      // A field is selected - connect this CSV column to it
      if (selectedFieldKey.startsWith('fk:')) {
        // Selected field is a FK sub-field
        notifier.connectCsvColumnToForeignKey(column);
      } else if (selectedFieldKey.startsWith('amount:')) {
        // Selected field is an amount sub-field
        notifier.connectCsvColumnToAmount(column);
      } else {
        // Selected field is a regular field
        notifier.connectToCsvColumn(column);
      }
    }
  }

  void _handleToggleExpandedSection(WidgetRef ref, String section) {
    final notifier = ref.read(flexibleCsvImportProvider.notifier);
    notifier.toggleExpandedForeignKey(section);
  }
}

/// A wrapper widget that allows tracking the position of its child.
class _PositionTrackingWrapper extends StatelessWidget {
  final GlobalKey itemKey;
  final Widget child;

  const _PositionTrackingWrapper({
    required this.itemKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: itemKey,
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final ColorIntensity intensity;

  const _PanelHeader({
    required this.title,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.textTertiary,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
