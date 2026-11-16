import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/core/errors/app_exception.dart';
import 'package:smartspend/core/formatting/money.dart';
import 'package:smartspend/features/expenses/data/drift_expense_repository.dart';
import 'package:smartspend/features/expenses/domain/expense.dart';
import 'package:smartspend/features/categories/data/drift_category_repository.dart';
import 'package:smartspend/features/budgets/data/drift_budget_repository.dart';

void main() {
  late AppDatabase db;
  late DriftExpenseRepository expenses;
  late DriftCategoryRepository categories;
  late DriftBudgetRepository budgets;
  late String food;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    expenses = DriftExpenseRepository(db);
    categories = DriftCategoryRepository(db);
    budgets = DriftBudgetRepository(db);
    food = (await categories.watchCategories().first)
        .firstWhere((c) => c.name == 'Food & Groceries')
        .id;
  });
  tearDown(() async {
    await db.close();
  });
  ExpenseDraft draft({
    int amount = 125000,
    DateTime? date,
    String? id,
    String? category,
    String merchant = 'Lunch shop',
    String note = '',
  }) => ExpenseDraft(
    submissionId: id ?? const Uuid().v4(),
    amountMinor: amount,
    categoryId: category ?? food,
    spentAt: date ?? DateTime(2026, 11, 15, 12),
    merchantName: merchant,
    note: note,
  );
  Expense edit(Expense e, {int? amount, String? category}) => Expense(
    id: e.id,
    amountMinor: amount ?? e.amountMinor,
    categoryId: category ?? e.categoryId,
    spentAt: e.spentAt,
    merchantName: e.merchantName,
    note: e.note,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    source: e.source,
    receiptAttachmentId: e.receiptAttachmentId,
  );

  test('initial schema, ten seeds, currency and foreign keys', () async {
    expect(await categories.watchCategories().first, hasLength(10));
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      1,
    );
    expect(
      (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
        'foreign_keys',
      ),
      1,
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(
      tables.map((r) => r.read<String>('name')),
      containsAll([
        'expenses',
        'categories',
        'budgets',
        'receipt_attachments',
        'app_settings',
        'sync_outbox',
        'report_history',
      ]),
    );
  });
  test(
    'insert, retrieve UTC date, edit, stale conflict and soft delete',
    () async {
      final e = await expenses.addExpense(draft());
      expect(e.spentAt.isUtc, isTrue);
      expect(await expenses.watchExpenses().first, hasLength(1));
      await expenses.updateExpense(edit(e, amount: 200));
      expect((await expenses.watchExpenses().first).single.amountMinor, 200);
      await expectLater(
        expenses.updateExpense(edit(e, amount: 300)),
        throwsA(isA<ConflictException>()),
      );
      await expenses.deleteExpense(e.id);
      await expenses.deleteExpense(e.id);
      expect(await expenses.watchExpenses().first, isEmpty);
      expect(
        (await db.customSelect('SELECT * FROM expenses').getSingle())
            .readNullable<int>('deleted_at'),
        isNotNull,
      );
      expect(
        await db.customSelect('SELECT * FROM sync_outbox').get(),
        hasLength(3),
      );
    },
  );
  test('same submission is idempotent under concurrent calls; changed input conflicts', () async {
    final d = draft();
    final result = await Future.wait([
      expenses.addExpense(d),
      expenses.addExpense(d),
    ]);
    expect(result[0].id, result[1].id);
    expect(await expenses.watchExpenses().first, hasLength(1));
    expect(
      await db.customSelect('SELECT * FROM sync_outbox').get(),
      hasLength(1),
    );
    await expectLater(
      expenses.addExpense(draft(id: d.submissionId, amount: 1)),
      throwsA(isA<ConflictException>()),
    );
    await expenses.deleteExpense(result.first.id);
    await expectLater(
      expenses.addExpense(d),
      throwsA(isA<ConflictException>()),
    );
  });
  test(
    'search is literal, case-insensitive, and combines with category and date',
    () async {
      final transport = (await categories.watchCategories().first)
          .firstWhere((c) => c.name == 'Transport')
          .id;
      await expenses.addExpense(draft(merchant: 'MARKET 100%', note: 'Dinner'));
      await expenses.addExpense(draft(category: transport, merchant: 'Bus'));
      expect(await expenses.watchExpenses(query: 'dINNer').first, hasLength(1));
      expect(await expenses.watchExpenses(query: '%').first, hasLength(1));
      expect(
        await expenses.watchExpenses(categoryId: transport).first,
        hasLength(1),
      );
      expect(
        await expenses
            .watchExpensesInRange(
              start: DateTime(2026, 11),
              endExclusive: DateTime(2026, 12),
              categoryId: food,
              query: 'market',
            )
            .first,
        hasLength(1),
      );
      expect(
        () => expenses.watchExpensesInRange(
          start: DateTime(2026, 12),
          endExclusive: DateTime(2026, 11),
        ),
        throwsA(isA<ValidationException>()),
      );
    },
  );
  test(
    'exclusive month boundaries, previous month, category totals and deletion',
    () async {
      await expenses.addExpense(
        draft(amount: 100, date: DateTime(2026, 10, 31, 23, 59, 59, 999, 999)),
      );
      final a = await expenses.addExpense(
        draft(amount: 200, date: DateTime(2026, 11)),
      );
      await expenses.addExpense(
        draft(amount: 300, date: DateTime(2026, 11, 30, 23, 59, 59, 999, 999)),
      );
      await expenses.addExpense(draft(amount: 999, date: DateTime(2026, 12)));
      final s = await expenses.watchMonthlySummary(DateTime(2026, 11)).first;
      expect(s.totalMinor, 500);
      expect(s.previousTotalMinor, 100);
      expect(s.transactionCount, 2);
      expect(s.changeInBasisPoints, 40000);
      final total =
          (await expenses.watchCategoryTotals(DateTime(2026, 11)).first).single;
      expect(total.totalMinor, 500);
      expect(total.transactionCount, 2);
      await expenses.deleteExpense(a.id);
      expect(
        (await expenses.watchMonthlySummary(DateTime(2026, 11)).first)
            .totalMinor,
        300,
      );
    },
  );
  test('empty month contains real zeros', () async {
    final s = await expenses.watchMonthlySummary(DateTime(2026, 1)).first;
    expect(s.totalMinor, 0);
    expect(s.previousTotalMinor, 0);
    expect(s.transactionCount, 0);
    expect(s.changeInBasisPoints, isNull);
    expect(
      await expenses.watchCategoryTotals(DateTime(2026, 1)).first,
      isEmpty,
    );
  });
  test('category CRUD and archive preserves history; archived category rejects new entries', () async {
    final c = await categories.createCategory(' Pets ');
    await categories.renameCategory(c.id, 'Pet care');
    final e = await expenses.addExpense(draft(category: c.id));
    await categories.archiveCategory(c.id);
    expect(
      (await categories.watchCategories().first).any((c2) => c2.id == c.id),
      isFalse,
    );
    expect(
      await categories.watchCategories(includeArchived: true).first,
      hasLength(11),
    );
    expect((await expenses.watchExpenses().first).single.categoryId, c.id);
    await expenses.updateExpense(edit(e, amount: 200));
    await expectLater(
      expenses.addExpense(draft(category: c.id)),
      throwsA(isA<ValidationException>()),
    );
    expect(
      (await expenses.watchCategoryTotals(DateTime(2026, 11)).first)
          .single
          .categoryName,
      'Pet care',
    );
    await expectLater(
      categories.createCategory('pet care'),
      throwsA(isA<ConflictException>()),
    );
    await expectLater(
      categories.createCategory('  '),
      throwsA(isA<ValidationException>()),
    );
  });
  test('invalid input rolls back both expense and outbox', () async {
    for (final amount in [0, -1]) {
      await expectLater(
        expenses.addExpense(draft(amount: amount)),
        throwsA(isA<ValidationException>()),
      );
    }
    await expectLater(
      expenses.addExpense(draft(category: const Uuid().v4())),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      expenses.addExpense(draft(id: 'not-uuid')),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      expenses.addExpense(draft(note: 'x' * 2001)),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      expenses.addExpense(
        ExpenseDraft(
          submissionId: const Uuid().v4(),
          amountMinor: 1,
          categoryId: food,
          spentAt: DateTime.now(),
          currencyCode: 'USD',
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await expenses.watchExpenses().first, isEmpty);
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });
  test(
    'unverified OCR is rejected and verified attachment is required',
    () async {
      await expectLater(
        expenses.addExpense(
          ExpenseDraft(
            submissionId: const Uuid().v4(),
            amountMinor: 1,
            categoryId: food,
            spentAt: DateTime.now(),
            source: ExpenseSource.receipt,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        expenses.addExpense(
          ExpenseDraft(
            submissionId: const Uuid().v4(),
            amountMinor: 1,
            categoryId: food,
            spentAt: DateTime.now(),
            source: ExpenseSource.receipt,
            receiptVerified: true,
            receiptAttachmentId: const Uuid().v4(),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      final id = const Uuid().v4();
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      await db.customStatement(
        'INSERT INTO receipt_attachments (id,local_path,verified_at,created_at) VALUES (?,?,?,?)',
        [id, 'receipts/example.jpg', now, now],
      );
      final e = await expenses.addExpense(
        ExpenseDraft(
          submissionId: const Uuid().v4(),
          amountMinor: 1,
          categoryId: food,
          spentAt: DateTime.now(),
          source: ExpenseSource.receipt,
          receiptVerified: true,
          receiptAttachmentId: id,
        ),
      );
      expect(e.source, ExpenseSource.receipt);
    },
  );
  test('monthly and category budgets upsert and use database totals', () async {
    final a = await budgets.setBudget(
      month: DateTime(2026, 11),
      amountMinor: 1000,
    );
    final b = await budgets.setBudget(
      month: DateTime(2026, 11, 20),
      amountMinor: 2000,
    );
    expect(a.id, b.id);
    await budgets.setBudget(
      month: DateTime(2026, 11),
      amountMinor: 500,
      categoryId: food,
    );
    await expenses.addExpense(draft(amount: 600));
    final usages = await budgets.watchBudgetUsage(DateTime(2026, 11)).first;
    expect(usages, hasLength(2));
    expect(usages.every((u) => u.spentMinor == 600), isTrue);
    expect(
      usages.singleWhere((u) => u.budget.categoryId == food).isExceeded,
      isTrue,
    );
    await budgets.deleteBudget(a.id);
    expect(
      await budgets.watchBudgetUsage(DateTime(2026, 11)).first,
      hasLength(1),
    );
    await expectLater(
      budgets.setBudget(month: DateTime(2026, 11), amountMinor: 0),
      throwsA(isA<ValidationException>()),
    );
  });
  test('stream updates after committed expense write', () async {
    final stream = expenses.watchMonthlySummary(DateTime(2026, 11));
    final expectation = expectLater(
      stream.map((s) => s.totalMinor),
      emitsInOrder([0, 200]),
    );
    // Await a query on the same connection before the write to let the stream subscribe.
    await expenses.watchExpenses().first;
    await expenses.addExpense(draft(amount: 200));
    await expectation;
  });
  test('aggregate overflow reports an error instead of floating point or wraparound', () async {
    await expenses.addExpense(draft(amount: maxMoneyMinor));
    await expenses.addExpense(draft(amount: 1));
    await expectLater(
      expenses.watchMonthlySummary(DateTime(2026, 11)).first,
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      expenses.watchCategoryTotals(DateTime(2026, 11)).first,
      throwsA(isA<ValidationException>()),
    );
  });
  test('deleted category cannot receive a new expense', () async {
    await expectLater(
      db.customStatement('DELETE FROM categories WHERE id=?', [food]),
      completes,
    );
    await expectLater(
      expenses.addExpense(draft()),
      throwsA(isA<ValidationException>()),
    );
  });
  test(
    'summary stream recovers after an overflowing expense is removed',
    () async {
      await expenses.addExpense(draft(amount: maxMoneyMinor));
      final extra = await expenses.addExpense(draft(amount: 1));
      final errorSeen = Completer<Object>();
      final recovered = Completer<int>();
      final subscription = expenses
          .watchMonthlySummary(DateTime(2026, 11))
          .listen(
            (summary) {
              if (!recovered.isCompleted) {
                recovered.complete(summary.totalMinor);
              }
            },
            onError: (Object error) {
              if (!errorSeen.isCompleted) errorSeen.complete(error);
            },
          );
      try {
        expect(await errorSeen.future, isA<ValidationException>());
        await expenses.deleteExpense(extra.id);
        expect(await recovered.future, maxMoneyMinor);
      } finally {
        await subscription.cancel();
      }
    },
  );
}
