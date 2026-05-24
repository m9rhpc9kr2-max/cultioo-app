import 'package:flutter/services.dart';

int _numberFormatStyleIndex = 0; // 0 = US, 1 = EU

void setNumberFormatStyleIndex(int index) {
  _numberFormatStyleIndex = index == 1 ? 1 : 0;
}

int getNumberFormatStyleIndex() => _numberFormatStyleIndex;

String formatNumberUS(
  num value, {
  int fractionDigits = 2,
}) {
  final useEu = _numberFormatStyleIndex == 1;
  final thousandsSeparator = useEu ? '.' : ',';
  final decimalSeparator = useEu ? ',' : '.';

  final negative = value < 0;
  final absValue = value.abs();
  final fixed = absValue.toStringAsFixed(fractionDigits);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final fracPart = parts.length > 1 ? parts[1] : '';

  final grouped = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    final fromRight = intPart.length - i;
    grouped.write(intPart[i]);
    if (fromRight > 1 && fromRight % 3 == 1) {
      grouped.write(thousandsSeparator);
    }
  }

  final sign = negative ? '-' : '';
  if (fractionDigits <= 0) {
    return '$sign${grouped.toString()}';
  }
  return '$sign${grouped.toString()}$decimalSeparator$fracPart';
}

String formatCurrencyUsd(num value) => '\$${formatNumberUS(value, fractionDigits: 2)}';

/// Parses a formatted number string (e.g. '1,234.56' or '1.234,56') back to double.
double? parseFormattedNumber(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  final isNegative = value.startsWith('-');
  final useEu = _numberFormatStyleIndex == 1;
  final String normalized;
  if (useEu) {
    normalized = value.replaceAll('-', '').replaceAll('.', '').replaceAll(',', '.');
  } else {
    normalized = value.replaceAll('-', '').replaceAll(',', '');
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null) return null;
  return isNegative ? -parsed : parsed;
}

/// RTL (right-to-left) calculator-style formatter.
/// Digits accumulate from the right:
///   1 → 0.01 → 0.12 → 1.23 → 12.34 → 123.45 → 1,234.56
/// Supports optional negative sign and configurable fraction digits.
class RightToLeftDecimalFormatter extends TextInputFormatter {
  final bool signed;
  final int fractionDigits;

  const RightToLeftDecimalFormatter(
      {this.signed = false, this.fractionDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final isNegative = signed && newValue.text.trimLeft().startsWith('-');
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (digits.isEmpty) {
      final s = isNegative ? '-' : '';
      return newValue.copyWith(
        text: s,
        selection: TextSelection.collapsed(offset: s.length),
      );
    }

    String raw = digits.replaceAll(RegExp(r'^0+'), '');
    if (raw.isEmpty) raw = '0';
    while (raw.length <= fractionDigits) {
      raw = '0$raw';
    }

    final intPart = raw.substring(0, raw.length - fractionDigits);
    final fracPart = raw.substring(raw.length - fractionDigits);
    final numericValue = double.parse('$intPart.$fracPart');

    final formatted = (isNegative ? '-' : '') +
        formatNumberUS(numericValue, fractionDigits: fractionDigits);

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
