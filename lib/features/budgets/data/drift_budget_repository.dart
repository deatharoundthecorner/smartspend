import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/store_support.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/formatting/money.dart';
import '../../../core/utils/month_range.dart';
import '../domain/budget.dart';

class DriftBudgetRepository extends StoreSupport implements BudgetRepository {
  DriftBudgetRepository(super.db);
  @override
  Future<Budget> setBudget({
    required DateTime month,
    required int amountMinor,
    String? categoryId,
  }) => protect(
    () => db.transaction(() async {
      validateAmount(amountMinor);
      if (categoryId != null) await activeCategory(categoryId);
      final key = MonthRange(month).key;
      final rows = await db
          .customSelect(
            'SELECT id FROM budgets WHERE month=? AND ${categoryId == null ? 'category_id IS NULL' : 'category_id=?'}',
            variables: variables([key, ?categoryId]),
          )
          .get();
      final id = rows.isEmpty
          ? const Uuid().v4()
          : rows.single.read<String>('id');
      final now = instant(DateTime.now());
      if (rows.isEmpty) {
        await db.customStatement(
          'INSERT INTO budgets (id,month,category_id,amount_minor,created_at,updated_at) VALUES (?,?,?,?,?,?)',
          [id, key, categoryId, amountMinor, now, now],
        );
      } else {
        await db.customStatement(
          'UPDATE budgets SET amount_minor=?,updated_at=? WHERE id=?',
          [amountMinor, now, id],
        );
      }
      await enqueue('budget', id, 'upsert');
      db.markTablesUpdated({db.budgets});
      return Budget(
        id: id,
        month: key,
        amountMinor: amountMinor,
        categoryId: categoryId,
      );
    }),
  );
  @override
  Stream<List<BudgetUsage>> watchBudgetUsage(DateTime month) {
    final range = MonthRange(month);
    return protectStream(
      db
          .customSelect(
            'SELECT b.*, COALESCE((SELECT SUM(e.amount_minor) FROM expenses e WHERE e.deleted_at IS NULL AND e.spent_at >= ? AND e.spent_at < ? AND (b.category_id IS NULL OR e.category_id=b.category_id)),0) AS spent FROM budgets b WHERE b.month=? ORDER BY b.id',
            variables: variables([
              instant(range.start),
              instant(range.endExclusive),
              range.key,
            ]),
            readsFrom: {db.budgets, db.expenses},
          )
          .watch()
          .map(
            (rows) => List.unmodifiable(
              rows.map(
                (r) => BudgetUsage(
                  budget: Budget(
                    id: r.read('id'),
                    month: r.read('month'),
                    amountMinor: r.read('amount_minor'),
                    categoryId: r.readNullable('category_id'),
                  ),
                  spentMinor: r.read('spent'),
                ),
              ),
            ),
          ),
    );
  }

  @override
  Future<void> deleteBudget(String id) => protect(
    () => db.transaction(() async {
      validateId(id);
      final count = await db.customUpdate(
        'DELETE FROM budgets WHERE id=?',
        variables: [Variable(id)],
        updates: {db.budgets},
      );
      if (count == 0) throw const NotFoundException('Budget does not exist.');
      await enqueue('budget', id, 'delete');
    }),
  );
}
