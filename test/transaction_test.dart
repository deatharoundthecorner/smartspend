import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/features/categories/data/drift_category_repository.dart';
import 'package:smartspend/features/expenses/data/drift_expense_repository.dart';
import 'package:smartspend/features/expenses/domain/expense.dart';

void main() {
  test('outbox failure rolls back expense write atomically', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final category = (await DriftCategoryRepository(
        db,
      ).watchCategories().first).first;
      await db.customStatement(
        "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
      );
      final repo = DriftExpenseRepository(db);
      await expectLater(
        repo.addExpense(
          ExpenseDraft(
            submissionId: const Uuid().v4(),
            amountMinor: 100,
            categoryId: category.id,
            spentAt: DateTime.now(),
          ),
        ),
        throwsException,
      );
      expect(await repo.watchExpenses().first, isEmpty);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
    } finally {
      await db.close();
    }
  });
  test('foreign keys protect category and receipt history', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      final category = (await DriftCategoryRepository(
        db,
      ).watchCategories().first).first;
      await DriftExpenseRepository(db).addExpense(
        ExpenseDraft(
          submissionId: const Uuid().v4(),
          amountMinor: 100,
          categoryId: category.id,
          spentAt: DateTime.now(),
        ),
      );
      await expectLater(
        db.customStatement('DELETE FROM categories WHERE id=?', [category.id]),
        throwsException,
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    } finally {
      await db.close();
    }
  });
}
