import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../settings/data/models/app_settings.dart';

enum AccountType {
  bank,
  creditCard,
  cash,
  savings,
  investment,
  wallet,
}

extension AccountTypeExtension on AccountType {
  String get displayName {
    switch (this) {
      case AccountType.bank:
        return 'Bank';
      case AccountType.creditCard:
        return 'Credit Card';
      case AccountType.cash:
        return 'Cash';
      case AccountType.savings:
        return 'Savings';
      case AccountType.investment:
        return 'Investment';
      case AccountType.wallet:
        return 'Wallet';
    }
  }

  bool get isLiability => this == AccountType.creditCard;

  bool get isHolding => !isLiability;

  bool get isLiquid {
    switch (this) {
      case AccountType.bank:
      case AccountType.cash:
      case AccountType.savings:
      case AccountType.wallet:
        return true;
      case AccountType.creditCard:
      case AccountType.investment:
        return false;
    }
  }

  Color get color {
    switch (this) {
      case AccountType.bank:
        return AppColors.accountBank;
      case AccountType.creditCard:
        return AppColors.accountCreditCard;
      case AccountType.cash:
        return AppColors.accountCash;
      case AccountType.savings:
        return AppColors.accountSavings;
      case AccountType.investment:
        return AppColors.accountInvestment;
      case AccountType.wallet:
        return AppColors.accountWallet;
    }
  }

  IconData get icon {
    switch (this) {
      case AccountType.bank:
        return Icons.account_balance;
      case AccountType.creditCard:
        return Icons.credit_card;
      case AccountType.cash:
        return Icons.payments;
      case AccountType.savings:
        return Icons.savings;
      case AccountType.investment:
        return Icons.trending_up;
      case AccountType.wallet:
        return Icons.account_balance_wallet;
    }
  }
}

class Account {
  final String id;
  final String name;
  final AccountType type;
  final double balance;
  final double initialBalance;
  final String currencyCode;
  final Color? customColor;
  final IconData? customIcon;
  final DateTime createdAt;
  final int sortOrder;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.initialBalance,
    this.currencyCode = 'USD',
    this.customColor,
    this.customIcon,
    required this.createdAt,
    this.sortOrder = 0,
  })  : assert(name.isNotEmpty, 'Account name must not be empty'),
        assert(_isValidCurrencyCode(currencyCode),
            'Currency code must be 3 uppercase ASCII letters'),
        assert(sortOrder >= 0, 'Sort order must be non-negative');

  static bool _isValidCurrencyCode(String code) {
    if (code.length != 3) return false;
    for (var i = 0; i < 3; i++) {
      final c = code.codeUnitAt(i);
      if (c < 0x41 || c > 0x5A) return false; // A..Z
    }
    return true;
  }

  Color get color => customColor ?? type.color;
  IconData get icon => customIcon ?? type.icon;

  /// Returns the account color with the specified intensity.
  /// If the account has a custom color, it returns that color unchanged.
  Color getColorWithIntensity(ColorIntensity intensity) {
    return customColor ?? AppColors.getAccountColor(type.name, intensity);
  }

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    double? balance,
    double? initialBalance,
    String? currencyCode,
    Color? customColor,
    IconData? customIcon,
    DateTime? createdAt,
    int? sortOrder,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      initialBalance: initialBalance ?? this.initialBalance,
      currencyCode: currencyCode ?? this.currencyCode,
      customColor: customColor ?? this.customColor,
      customIcon: customIcon ?? this.customIcon,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Validates critical invariants at save-time.
  /// Throws [ValidationException] for invalid state.
  void validate() {
    if (id.isEmpty) {
      throw const ValidationException(message: 'Account ID must not be empty', field: 'id');
    }
    if (name.isEmpty) {
      throw const ValidationException(message: 'Account name must not be empty', field: 'name');
    }
    if (!_isValidCurrencyCode(currencyCode)) {
      throw const ValidationException(
        message: 'Currency code must be 3 uppercase ASCII letters',
        field: 'currencyCode',
      );
    }
    if (sortOrder < 0) {
      throw const ValidationException(message: 'Sort order must be non-negative', field: 'sortOrder');
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Account && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
