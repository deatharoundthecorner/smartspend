import 'package:intl/intl.dart';

import '../errors/app_exception.dart';

/// Fits signed SQLite INTEGER. BigInt intermediates prevent Dart int wrapping.
const maxMoneyMinor = 9223372036854775807;
final _max = BigInt.from(maxMoneyMinor);

int checkedMoney(BigInt value, {bool allowZero = true}) {
  if (value < BigInt.zero ||
      value > _max ||
      (!allowZero && value == BigInt.zero)) {
    throw const ValidationException(
      'Amount must be positive and fit a 64-bit integer.',
    );
  }
  return value.toInt();
}

void validateAmount(int value) =>
    checkedMoney(BigInt.from(value), allowZero: false);

/// Accepts plain decimals or correctly grouped thousands, e.g. 1,250.00.
/// Currency symbols, exponents, signs and excess decimal digits are rejected.
int parseLkr(String input) {
  final text = input.trim();
  if (!RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$')
      .hasMatch(text)) {
    throw const ValidationException(
      'Enter an LKR amount with at most two decimal places.',
    );
  }
  final parts = text.replaceAll(',', '').split('.');
  final whole = BigInt.parse(parts[0]);
  final cents = parts.length == 2
      ? BigInt.parse(parts[1].padRight(2, '0'))
      : BigInt.zero;
  return checkedMoney(whole * BigInt.from(100) + cents, allowZero: false);
}

String formatLkr(int amountMinor) {
  checkedMoney(BigInt.from(amountMinor));
  final digits = (amountMinor ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return 'LKR $buffer.${(amountMinor % 100).toString().padLeft(2, '0')}';
}

int sumMoney(Iterable<int> amounts) {
  var sum = BigInt.zero;
  for (final amount in amounts) {
    checkedMoney(BigInt.from(amount));
    sum += BigInt.from(amount);
  }
  return checkedMoney(sum);
}

/// Exact integer hundredths of a percent. Null means no previous spending.
int? changeBasisPoints(int current, int previous) {
  checkedMoney(BigInt.from(current));
  checkedMoney(BigInt.from(previous));
  if (previous == 0) return null;
  final result =
      (BigInt.from(current) - BigInt.from(previous)) *
      BigInt.from(10000) ~/
      BigInt.from(previous);
  if (result.abs() > _max) {
    throw const ValidationException('Percentage exceeds supported range.');
  }
  return result.toInt();
}

String formatMonth(DateTime month) =>
    DateFormat('MMMM yyyy', 'en').format(month.toLocal());
