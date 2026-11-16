import '../../../core/formatting/money.dart';

class Budget {
  const Budget({
    required this.id,
    required this.month,
    required this.amountMinor,
    this.categoryId,
  });
  final String id;
  final String month;
  final int amountMinor;
  final String? categoryId;
}

class BudgetUsage {
  const BudgetUsage({required this.budget, required this.spentMinor});
  final Budget budget;
  final int spentMinor;
  int get remainingMinor => budget.amountMinor - spentMinor;
  bool get isExceeded => spentMinor > budget.amountMinor;
  int get usedBasisPoints {
    final value =
        BigInt.from(spentMinor) *
        BigInt.from(10000) ~/
        BigInt.from(budget.amountMinor);
    return checkedMoney(value);
  }
}

abstract interface class BudgetRepository {
  Future<Budget> setBudget({
    required DateTime month,
    required int amountMinor,
    String? categoryId,
  });
  Stream<List<BudgetUsage>> watchBudgetUsage(DateTime month);
  Future<void> deleteBudget(String id);
}
