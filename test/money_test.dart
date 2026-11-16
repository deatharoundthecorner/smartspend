import 'package:flutter_test/flutter_test.dart';
import 'package:smartspend/core/formatting/money.dart';
import 'package:smartspend/core/errors/app_exception.dart';
import 'package:smartspend/core/utils/month_range.dart';
import 'package:smartspend/features/budgets/domain/budget.dart';

void main() {
  test('parses exact decimals, whitespace and grouped amounts', () {
    expect(parseLkr('1,250.00'), 125000);
    expect(parseLkr(' 0.01 '), 1);
    expect(parseLkr('15.5'), 1550);
    expect(parseLkr('0001'), 100);
    expect(parseLkr('92233720368547758.07'), maxMoneyMinor);
  });
  test('rejects zero, negatives, malformed and overflowing values', () {
    for (final input in [
      '',
      '0',
      '0.00',
      '-1',
      '+1',
      '1e3',
      'NaN',
      'Infinity',
      '1.001',
      '1.',
      '1,25',
      'LKR 2',
      '92233720368547758.08',
    ]) {
      expect(
        () => parseLkr(input),
        throwsA(isA<ValidationException>()),
        reason: input,
      );
    }
  });
  test('formats large values without floating point precision loss', () {
    expect(formatLkr(125000), 'LKR 1,250.00');
    expect(formatLkr(1), 'LKR 0.01');
    expect(formatLkr(0), 'LKR 0.00');
    expect(formatLkr(maxMoneyMinor), 'LKR 92,233,720,368,547,758.07');
  });
  test('checked aggregation and exact comparison', () {
    expect(sumMoney([1, 2, 3]), 6);
    expect(sumMoney([]), 0);
    expect(
      () => sumMoney([maxMoneyMinor, 1]),
      throwsA(isA<ValidationException>()),
    );
    expect(() => sumMoney([-1]), throwsA(isA<ValidationException>()));
    expect(changeBasisPoints(150, 100), 5000);
    expect(changeBasisPoints(50, 100), -5000);
    expect(changeBasisPoints(100, 0), isNull);
    expect(changeBasisPoints(0, 100), -10000);
  });
  test('month boundaries use local calendar and handle leap/year rollover', () {
    final feb = MonthRange(DateTime(2024, 2, 20));
    expect(feb.start, DateTime(2024, 2));
    expect(feb.endExclusive, DateTime(2024, 3));
    expect(MonthRange(DateTime(2026, 1)).previousMonth, DateTime(2025, 12));
    expect(MonthRange(DateTime(2026, 12)).endExclusive, DateTime(2027, 1));
    expect(feb.key, '2024-02');
  });
  test('budget usage is exact and permits overspending', () {
    const usage = BudgetUsage(
      budget: Budget(id: 'x', month: '2026-11', amountMinor: 10000),
      spentMinor: 12500,
    );
    expect(usage.usedBasisPoints, 12500);
    expect(usage.remainingMinor, -2500);
    expect(usage.isExceeded, isTrue);
  });
}
