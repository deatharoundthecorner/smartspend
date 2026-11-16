import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartspend/app/providers.dart';
import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/features/expenses/domain/expense.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'public providers react to real spending after seeded categories load',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final expenseChanged = Completer<void>();
      final summaryChanged = Completer<int>();
      // Match UI subscriptions and wait for asynchronous query invalidation.
      container.listen(categoriesProvider, (_, _) {});
      container.listen(expensesProvider, (_, next) {
        next.whenData((rows) {
          if (rows.length == 1 && !expenseChanged.isCompleted) {
            expenseChanged.complete();
          }
        });
      });
      container.listen(monthlySummaryProvider(DateTime(2026, 11)), (_, next) {
        next.whenData((summary) {
          if (summary.transactionCount == 1 && !summaryChanged.isCompleted) {
            summaryChanged.complete(summary.totalMinor);
          }
        });
      });
      try {
        final categories = await container.read(categoriesProvider.future);
        expect(categories, hasLength(10));
        await container
            .read(expenseRepositoryProvider)
            .addExpense(
              ExpenseDraft(
                submissionId: const Uuid().v4(),
                amountMinor: 125000,
                categoryId: categories.first.id,
                spentAt: DateTime(2026, 11, 15),
              ),
            );
        await expenseChanged.future;
        expect(await summaryChanged.future, 125000);
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );
}
