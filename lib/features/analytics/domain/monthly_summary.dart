import '../../../core/formatting/money.dart';

class MonthlySummary {
  const MonthlySummary({
    required this.month,
    required this.totalMinor,
    required this.transactionCount,
    required this.previousTotalMinor,
  });
  final DateTime month;
  final int totalMinor;
  final int transactionCount;
  final int previousTotalMinor;
  int get differenceMinor => totalMinor - previousTotalMinor;
  int? get changeInBasisPoints =>
      changeBasisPoints(totalMinor, previousTotalMinor);
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.categoryName,
    required this.totalMinor,
    required this.transactionCount,
  });
  final String categoryId;
  final String categoryName;
  final int totalMinor;
  final int transactionCount;
}

abstract interface class MonthlyAnalyticsRepository {
  Stream<MonthlySummary> watchMonthlySummary(DateTime month);
  Stream<List<CategoryTotal>> watchCategoryTotals(DateTime month);
}
