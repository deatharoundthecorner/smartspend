class MonthRange {
  MonthRange(DateTime month) : this._(month.toLocal());
  MonthRange._(DateTime local)
    : start = DateTime(local.year, local.month),
      endExclusive = DateTime(local.year, local.month + 1);
  final DateTime start;
  final DateTime endExclusive;
  DateTime get previousMonth => DateTime(start.year, start.month - 1);
  String get key =>
      '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}';
}
