enum ExpenseSource { manual, receipt }

class Expense {
  const Expense({
    required this.id,
    required this.amountMinor,
    this.currencyCode = 'LKR',
    required this.categoryId,
    this.merchantName = '',
    this.note = '',
    required this.spentAt,
    this.source = ExpenseSource.manual,
    this.receiptAttachmentId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  final String id;
  final int amountMinor;
  final String currencyCode;
  final String categoryId;
  final String merchantName;
  final String note;
  final DateTime spentAt;
  final ExpenseSource source;
  final String? receiptAttachmentId;
  final DateTime createdAt;

  /// Optimistic concurrency token: pass unchanged when updating an expense.
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.submissionId,
    required this.amountMinor,
    required this.categoryId,
    required this.spentAt,
    this.currencyCode = 'LKR',
    this.merchantName = '',
    this.note = '',
    this.source = ExpenseSource.manual,
    this.receiptAttachmentId,
    this.receiptVerified = false,
  });

  /// One UUID per form submission; reuse it on retry, never across new expenses.
  final String submissionId;
  final int amountMinor;
  final String currencyCode;
  final String categoryId;
  final String merchantName;
  final String note;
  final DateTime spentAt;
  final ExpenseSource source;
  final String? receiptAttachmentId;
  final bool receiptVerified;
}
