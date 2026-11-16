import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/database/app_database.dart' show AppDatabase;
import '../features/expenses/data/drift_expense_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/expenses/domain/expense.dart';
import '../features/categories/data/drift_category_repository.dart';
import '../features/categories/domain/category.dart';
import '../features/budgets/data/drift_budget_repository.dart';
import '../features/budgets/domain/budget.dart';
import '../features/analytics/domain/monthly_summary.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'smartspend'));
  ref.onDispose(() {
    db.close();
  });
  return db;
});
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => DriftExpenseRepository(ref.watch(databaseProvider)),
);
final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => DriftCategoryRepository(ref.watch(databaseProvider)),
);
final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => DriftBudgetRepository(ref.watch(databaseProvider)),
);
final monthlyAnalyticsRepositoryProvider = Provider<MonthlyAnalyticsRepository>(
  (ref) => ref.watch(expenseRepositoryProvider),
);
final expensesProvider = StreamProvider<List<Expense>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchExpenses(),
);
final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchCategories(),
);
final monthlySummaryProvider = StreamProvider.autoDispose
    .family<MonthlySummary, DateTime>(
      (ref, month) => ref
          .watch(monthlyAnalyticsRepositoryProvider)
          .watchMonthlySummary(month),
    );
final categoryTotalsProvider = StreamProvider.autoDispose
    .family<List<CategoryTotal>, DateTime>(
      (ref, month) => ref
          .watch(monthlyAnalyticsRepositoryProvider)
          .watchCategoryTotals(month),
    );
final budgetUsageProvider = StreamProvider.autoDispose
    .family<List<BudgetUsage>, DateTime>(
      (ref, month) =>
          ref.watch(budgetRepositoryProvider).watchBudgetUsage(month),
    );
