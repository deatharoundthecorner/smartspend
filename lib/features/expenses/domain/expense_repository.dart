import 'expense.dart';
import '../../analytics/domain/monthly_summary.dart';

abstract interface class ExpenseRepository
    implements MonthlyAnalyticsRepository {
  Stream<List<Expense>> watchExpenses({String? query, String? categoryId});
  Stream<List<Expense>> watchExpensesInRange({
    required DateTime start,
    required DateTime endExclusive,
    String? categoryId,
    String? query,
  });
  Future<Expense> addExpense(ExpenseDraft draft);
  Future<void> updateExpense(Expense expense);
  Future<void> deleteExpense(String id);
}
