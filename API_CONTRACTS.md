# SmartSpend API contracts v1

Initial proposal for frontend review. No prior contracts existed in the repository.
Coordinate breaking changes in this file and the PR before implementing them.
The frontend imports `lib/app/providers.dart` and feature **domain** files, never
Drift tables, SQL, or data implementations.

## Models

All model fields are final. Repository lists are unmodifiable. `int` amounts are
LKR minor units (100 = LKR 1.00). Domain timestamps returned by repositories are
UTC `DateTime`; use `.toLocal()` to display. User-entered dates may be local;
repositories convert them to UTC microseconds on write.

| Model | Fields |
| --- | --- |
| `Expense` | `String id`, `int amountMinor`, `String currencyCode` (LKR), `String categoryId`, `String merchantName`, `String note`, `DateTime spentAt`, `ExpenseSource source`, `String? receiptAttachmentId`, `DateTime createdAt`, `DateTime updatedAt`, `DateTime? deletedAt` |
| `ExpenseDraft` | `String submissionId`, `int amountMinor`, `String categoryId`, `DateTime spentAt`, optional `currencyCode` (LKR), `merchantName` (empty), `note` (empty), `source` (manual), `receiptAttachmentId` (null), `receiptVerified` (false) |
| `ExpenseSource` | enum values `manual`, `receipt` |
| `Category` | `String id`, `String name`, `DateTime createdAt`, `DateTime updatedAt`, `DateTime? archivedAt` |
| `MonthlySummary` | `DateTime month` (local month start), `int totalMinor`, `int transactionCount`, `int previousTotalMinor`; getters `differenceMinor`, `int? changeInBasisPoints` |
| `CategoryTotal` | `String categoryId`, `String categoryName`, `int totalMinor`, `int transactionCount` |
| `Budget` | `String id`, `String month` (YYYY-MM), `int amountMinor`, `String? categoryId` (null = overall) |
| `BudgetUsage` | `Budget budget`, `int spentMinor`; getters `remainingMinor`, `isExceeded`, `usedBasisPoints` |
| `ReceiptAttachment` | `String id`, `String localPath`, `DateTime createdAt`, `DateTime verifiedAt` |
| `OcrExtraction` | optional `String amountText`, `String merchantName`, `DateTime spentAt`; unverified transient result only |

Basis points are integer hundredths of a percent: 12500 means 125.00%. Division
truncates toward zero. A zero previous total has no defined percentage change
(`null`); show an em dash or "No previous spending". Budget remaining may be
negative. An exceptionally large percentage can raise `ValidationException`;
show the absolute amounts instead. SQL sum overflow likewise reports validation
failure rather than a rounded or wrapped total.

## Repository signatures

```dart
abstract interface class ExpenseRepository implements MonthlyAnalyticsRepository {
  Stream<List<Expense>> watchExpenses({String? query, String? categoryId});
  Stream<List<Expense>> watchExpensesInRange({
    required DateTime start, required DateTime endExclusive,
    String? categoryId, String? query,
  });
  Future<Expense> addExpense(ExpenseDraft draft);
  Future<void> updateExpense(Expense expense);
  Future<void> deleteExpense(String id);
}
abstract interface class MonthlyAnalyticsRepository {
  Stream<MonthlySummary> watchMonthlySummary(DateTime month);
  Stream<List<CategoryTotal>> watchCategoryTotals(DateTime month);
}
abstract interface class CategoryRepository {
  Stream<List<Category>> watchCategories({bool includeArchived = false});
  Future<Category> createCategory(String name);
  Future<void> renameCategory(String id, String name);
  Future<void> archiveCategory(String id);
}
abstract interface class BudgetRepository {
  Future<Budget> setBudget({required DateTime month,
    required int amountMinor, String? categoryId});
  Stream<List<BudgetUsage>> watchBudgetUsage(DateTime month);
  Future<void> deleteBudget(String id);
}
```

### Behavioral guarantees

- Watchers emit current database data and committed changes asynchronously. A mutation
  Future can finish before the UI receives its next stream event. Use `ref.watch`
  in widgets; reading a provider Future alone does not subscribe to later changes.
  Empty lists and zero
  summaries are valid successes. Errors must not be presented as empty results.
- Expenses exclude soft deletions and sort by spentAt descending, then ID. Date
  ranges include start and exclude end. Search is literal substring over merchant
  and note, with SQLite's ASCII case-insensitive matching; `%` is not a wildcard.
- Month selectors should use `DateTime(year, month)` in the device timezone. UTC
  inputs are first converted to local time. Local calendar boundaries are converted
  separately to UTC; no fixed 30-day or 24-hour approximation is used.
- Generate one UUID `submissionId` when a new form session starts. Retain the same
  ID, amount, timestamp and other draft fields for a failed-save retry. An identical
  retry returns the existing expense (including later edits), with no duplicate
  outbox event. Changed content or a deleted original raises conflict. A new expense
  requires a new ID even when its amount and date match an earlier expense.
- Update passes the original `createdAt` and `updatedAt` unchanged. `updatedAt` is
  the concurrency token, not an editable date. Reload the stream after saving to
  obtain the new token. Stale writes raise conflict. Receipt source and attachment
  cannot be changed through editing; deletion goes through `deleteExpense`.
- New expenses and changed category assignments require an active category.
  Existing expenses in archived categories may still be edited without reassigning
  them. History and report joins retain archived categories.
- Category names are trimmed, 1–80 characters, unique under SQLite lower/trim
  normalization including archived names. Merchant max 160, note max 2000.
- Category rename and budget upsert currently use last committed write wins.
  Expense edits use optimistic concurrency. Future cloud conflict policy is not
  implemented and must not be inferred from these local contracts.
- A budget is unique per local YYYY-MM and category, or per month overall. Setting
  it again updates the same ID. Category and overall budgets may coexist.
- Receipt-derived drafts require `receiptVerified: true` AND an existing verified
  attachment. The future scanner/attachment workflow is deliberately not exposed
  yet; do not insert attachments from widgets or treat the flag as an OCR service.

## Providers

| Provider | Value |
| --- | --- |
| `expenseRepositoryProvider` | `ExpenseRepository` |
| `categoryRepositoryProvider` | `CategoryRepository` |
| `budgetRepositoryProvider` | `BudgetRepository` |
| `monthlyAnalyticsRepositoryProvider` | `MonthlyAnalyticsRepository` |
| `expensesProvider` | `AsyncValue<List<Expense>>` |
| `categoriesProvider` | `AsyncValue<List<Category>>` (active only) |
| `monthlySummaryProvider(month)` | `AsyncValue<MonthlySummary>` |
| `categoryTotalsProvider(month)` | `AsyncValue<List<CategoryTotal>>` |
| `budgetUsageProvider(month)` | `AsyncValue<List<BudgetUsage>>` |

`databaseProvider` is infrastructure-owned. Override repository providers with
fakes for frontend tests; production has one database per root ProviderScope.
DateTime family arguments should be normalized to the first of the selected month
for stable provider identity.

```dart
final summary = ref.watch(monthlySummaryProvider(DateTime(2026, 11)));
return summary.when(
  loading: () => const CircularProgressIndicator(),
  error: (error, stack) => Text('Could not load spending. Please retry.'),
  data: (value) => Text(formatLkr(value.totalMinor)),
);
```

```dart
// Keep submissionId outside the save callback; do not regenerate on retry.
final draft = ExpenseDraft(
  submissionId: submissionId,
  amountMinor: parseLkr(amountText),
  categoryId: selectedCategoryId,
  spentAt: selectedDate,
  merchantName: merchantText,
  note: noteText,
);
final saved = await ref.read(expenseRepositoryProvider).addExpense(draft);
```

Disable Save while its Future is pending. Catch `AppException` for expected failures,
retain the draft, and show actionable feedback. Streams and async methods propagate
storage errors; invalid date range construction throws synchronously. Programming
errors remain visible rather than being disguised as storage errors.

| Error code | Type | UI behavior |
| --- | --- | --- |
| `validation` | `ValidationException` | Correct the amount, field, selection or receipt; preserve input |
| `not_found` | `NotFoundException` | Refresh the list and explain that the record is unavailable |
| `conflict` | `ConflictException` | Reload stale edits or choose a distinct category name; preserve user input |
| `storage` | `AppException` | Show retry action; do not display raw cause to users |

Utilities: `parseLkr`, `formatLkr`, `sumMoney`, `changeBasisPoints`, `formatMonth` and
`MonthRange`. No money utility converts through `double`. FL Chart belongs in
presentation and is not required by these shared report contracts.
