import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/features/categories/data/drift_category_repository.dart';
import 'package:smartspend/features/expenses/data/drift_expense_repository.dart';
import 'package:smartspend/features/expenses/domain/expense.dart';

void main() {
  test(
    'file persistence and version 1 reopen keep transactions and seeds',
    () async {
      final dir = await Directory.systemTemp.createTemp('smartspend-test-');
      final file = File('${dir.path}/db.sqlite');
      try {
        final first = AppDatabase(NativeDatabase(file));
        late String expenseId;
        try {
          final cat = (await DriftCategoryRepository(
            first,
          ).watchCategories().first).first;
          final expense = await DriftExpenseRepository(first).addExpense(
            ExpenseDraft(
              submissionId: const Uuid().v4(),
              amountMinor: 125000,
              categoryId: cat.id,
              spentAt: DateTime(2026, 11, 15),
            ),
          );
          expenseId = expense.id;
        } finally {
          await first.close();
        }
        final reopened = AppDatabase(NativeDatabase(file));
        try {
          final expense = (await DriftExpenseRepository(
            reopened,
          ).watchExpenses().first).single;
          expect(expense.id, expenseId);
          expect(expense.amountMinor, 125000);
          expect(
            await DriftCategoryRepository(reopened).watchCategories().first,
            hasLength(10),
          );
          expect(
            (await reopened.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            1,
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
