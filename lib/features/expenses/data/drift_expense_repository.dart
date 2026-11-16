import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/store_support.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/formatting/money.dart';
import '../../../core/utils/month_range.dart';
import '../../analytics/domain/monthly_summary.dart';
import '../domain/expense.dart';
import '../domain/expense_repository.dart';

class DriftExpenseRepository extends StoreSupport implements ExpenseRepository {
  DriftExpenseRepository(super.db);
  Expense _map(QueryRow r) => Expense(
    id: r.read('id'),
    amountMinor: r.read('amount_minor'),
    currencyCode: r.read('currency_code'),
    categoryId: r.read('category_id'),
    merchantName: r.read('merchant_name'),
    note: r.read('note'),
    spentAt: utcDate(r.read('spent_at')),
    source: ExpenseSource.values.byName(r.read('source')),
    receiptAttachmentId: r.readNullable('receipt_attachment_id'),
    createdAt: utcDate(r.read('created_at')),
    updatedAt: utcDate(r.read('updated_at')),
    deletedAt: nullableDate(r.readNullable('deleted_at')),
  );

  Stream<List<Expense>> _watch({
    DateTime? start,
    DateTime? endExclusive,
    String? categoryId,
    String? query,
  }) {
    final clauses = ['deleted_at IS NULL'];
    final args = <Object>[];
    if (start != null) {
      clauses.add('spent_at >= ?');
      args.add(instant(start));
    }
    if (endExclusive != null) {
      clauses.add('spent_at < ?');
      args.add(instant(endExclusive));
    }
    if (categoryId != null) {
      clauses.add('category_id = ?');
      args.add(categoryId);
    }
    if (query != null && query.trim().isNotEmpty) {
      clauses.add(
        '(instr(lower(merchant_name), lower(?)) > 0 OR instr(lower(note), lower(?)) > 0)',
      );
      args.addAll([query.trim(), query.trim()]);
    }
    return protectStream(
      db
          .customSelect(
            'SELECT * FROM expenses WHERE ${clauses.join(' AND ')} ORDER BY spent_at DESC, id',
            variables: variables(args),
            readsFrom: {db.expenses},
          )
          .watch()
          .map((rows) => List.unmodifiable(rows.map(_map))),
    );
  }

  @override
  Stream<List<Expense>> watchExpenses({String? query, String? categoryId}) =>
      _watch(query: query, categoryId: categoryId);
  @override
  Stream<List<Expense>> watchExpensesInRange({
    required DateTime start,
    required DateTime endExclusive,
    String? categoryId,
    String? query,
  }) {
    if (!start.isBefore(endExclusive)) {
      throw const ValidationException('Range end must be after start.');
    }
    return _watch(
      start: start,
      endExclusive: endExclusive,
      categoryId: categoryId,
      query: query,
    );
  }

  void _validate(int amount, String currency, String merchant, String note) {
    validateAmount(amount);
    if (currency != 'LKR') {
      throw const ValidationException('Only LKR is supported.');
    }
    if (merchant.length > 160 || note.length > 2000) {
      throw const ValidationException('Merchant or note is too long.');
    }
  }

  Future<void> _receipt(ExpenseSource source, String? attachmentId) async {
    if (source == ExpenseSource.receipt && attachmentId == null) {
      throw const ValidationException('A verified receipt is required.');
    }
    if (attachmentId != null) {
      validateId(attachmentId);
      final rows = await db
          .customSelect(
            'SELECT id FROM receipt_attachments WHERE id = ? AND verified_at IS NOT NULL',
            variables: [Variable(attachmentId)],
          )
          .get();
      if (rows.isEmpty) {
        throw const ValidationException('Receipt attachment is not verified.');
      }
    }
  }

  @override
  Future<Expense> addExpense(ExpenseDraft draft) => protect(
    () => db.transaction(() async {
      validateId(draft.submissionId);
      _validate(
        draft.amountMinor,
        draft.currencyCode,
        draft.merchantName,
        draft.note,
      );
      if (draft.source == ExpenseSource.receipt && !draft.receiptVerified) {
        throw const ValidationException(
          'Verify the extracted receipt before saving.',
        );
      }
      final fingerprint = jsonEncode([
        draft.amountMinor,
        draft.currencyCode,
        draft.categoryId,
        draft.merchantName.trim(),
        draft.note.trim(),
        instant(draft.spentAt),
        draft.source.name,
        draft.receiptAttachmentId,
      ]);
      final existing = await db
          .customSelect(
            'SELECT * FROM expenses WHERE submission_id = ?',
            variables: [Variable(draft.submissionId)],
          )
          .get();
      if (existing.isNotEmpty) {
        if (existing.single.read<String>('submission_fingerprint') !=
                fingerprint ||
            existing.single.readNullable<int>('deleted_at') != null) {
          throw const ConflictException(
            'This submission ID has already been used.',
          );
        }
        return _map(existing.single);
      }
      await activeCategory(draft.categoryId);
      await _receipt(draft.source, draft.receiptAttachmentId);
      final id = const Uuid().v4();
      final now = instant(DateTime.now());
      await db.customStatement(
        'INSERT INTO expenses (id,submission_id,submission_fingerprint,amount_minor,currency_code,category_id,merchant_name,note,spent_at,source,receipt_attachment_id,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          draft.submissionId,
          fingerprint,
          draft.amountMinor,
          draft.currencyCode,
          draft.categoryId,
          draft.merchantName.trim(),
          draft.note.trim(),
          instant(draft.spentAt),
          draft.source.name,
          draft.receiptAttachmentId,
          now,
          now,
        ],
      );
      await enqueue('expense', id, 'upsert');
      db.markTablesUpdated({db.expenses});
      return _map(
        await db
            .customSelect(
              'SELECT * FROM expenses WHERE id = ?',
              variables: [Variable(id)],
            )
            .getSingle(),
      );
    }),
  );
  @override
  Future<void> updateExpense(Expense expense) => protect(
    () => db.transaction(() async {
      validateId(expense.id);
      _validate(
        expense.amountMinor,
        expense.currencyCode,
        expense.merchantName,
        expense.note,
      );
      final rows = await db
          .customSelect(
            'SELECT * FROM expenses WHERE id = ? AND deleted_at IS NULL',
            variables: [Variable(expense.id)],
          )
          .get();
      if (rows.isEmpty) {
        throw const NotFoundException('Expense no longer exists.');
      }
      final stored = _map(rows.single);
      if (stored.updatedAt != expense.updatedAt) {
        throw const ConflictException(
          'Expense changed. Reload before editing.',
        );
      }
      if (expense.deletedAt != null || expense.createdAt != stored.createdAt) {
        throw const ValidationException('Cannot change lifecycle fields.');
      }
      if (expense.categoryId != stored.categoryId) {
        await activeCategory(expense.categoryId);
      }
      if (expense.source != stored.source ||
          expense.receiptAttachmentId != stored.receiptAttachmentId) {
        throw const ValidationException(
          'Receipt provenance cannot be changed by an expense edit.',
        );
      }
      final now = instant(DateTime.now());
      final updated = now > instant(stored.updatedAt)
          ? now
          : instant(stored.updatedAt) + 1;
      await db.customStatement(
        'UPDATE expenses SET amount_minor=?, category_id=?, merchant_name=?, note=?, spent_at=?, updated_at=? WHERE id=?',
        [
          expense.amountMinor,
          expense.categoryId,
          expense.merchantName.trim(),
          expense.note.trim(),
          instant(expense.spentAt),
          updated,
          expense.id,
        ],
      );
      await enqueue('expense', expense.id, 'upsert');
      db.markTablesUpdated({db.expenses});
    }),
  );
  @override
  Future<void> deleteExpense(String id) => protect(
    () => db.transaction(() async {
      validateId(id);
      final rows = await db
          .customSelect(
            'SELECT deleted_at FROM expenses WHERE id=?',
            variables: [Variable(id)],
          )
          .get();
      if (rows.isEmpty) {
        throw const NotFoundException('Expense does not exist.');
      }
      if (rows.single.readNullable<int>('deleted_at') != null) return;
      final now = instant(DateTime.now());
      await db.customStatement(
        'UPDATE expenses SET deleted_at=?,updated_at=? WHERE id=?',
        [now, now, id],
      );
      await enqueue('expense', id, 'delete');
      db.markTablesUpdated({db.expenses});
    }),
  );
  @override
  Stream<MonthlySummary> watchMonthlySummary(DateTime month) {
    final range = MonthRange(month);
    final previous = MonthRange(range.previousMonth);
    return protectStream(
      db
          .customSelect(
            'SELECT COALESCE(SUM(CASE WHEN spent_at >= ? THEN amount_minor ELSE 0 END),0) AS total, COUNT(CASE WHEN spent_at >= ? THEN 1 END) AS count, COALESCE(SUM(CASE WHEN spent_at < ? THEN amount_minor ELSE 0 END),0) AS previous FROM expenses WHERE deleted_at IS NULL AND spent_at >= ? AND spent_at < ?',
            variables: variables([
              instant(range.start),
              instant(range.start),
              instant(range.start),
              instant(previous.start),
              instant(range.endExclusive),
            ]),
            readsFrom: {db.expenses},
          )
          .watchSingle()
          .map(
            (r) => MonthlySummary(
              month: range.start,
              totalMinor: r.read('total'),
              transactionCount: r.read('count'),
              previousTotalMinor: r.read('previous'),
            ),
          ),
    );
  }

  @override
  Stream<List<CategoryTotal>> watchCategoryTotals(DateTime month) {
    final range = MonthRange(month);
    return protectStream(
      db
          .customSelect(
            'SELECT c.id, c.name, SUM(e.amount_minor) AS total, COUNT(*) AS count FROM expenses e JOIN categories c ON c.id=e.category_id WHERE e.deleted_at IS NULL AND e.spent_at >= ? AND e.spent_at < ? GROUP BY c.id,c.name ORDER BY total DESC,c.id',
            variables: variables([
              instant(range.start),
              instant(range.endExclusive),
            ]),
            readsFrom: {db.expenses, db.categories},
          )
          .watch()
          .map(
            (rows) => List.unmodifiable(
              rows.map(
                (r) => CategoryTotal(
                  categoryId: r.read('id'),
                  categoryName: r.read('name'),
                  totalMinor: r.read('total'),
                  transactionCount: r.read('count'),
                ),
              ),
            ),
          ),
    );
  }
}
