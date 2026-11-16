import 'dart:async';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';
import 'app_database.dart';

final uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
void validateId(String id) {
  if (!uuidPattern.hasMatch(id)) {
    throw const ValidationException('A UUID is required.');
  }
}

DateTime utcDate(int value) =>
    DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
DateTime? nullableDate(int? value) => value == null ? null : utcDate(value);
int instant(DateTime date) => date.toUtc().microsecondsSinceEpoch;

Future<T> protect<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AppException {
    rethrow;
  } on SqliteException catch (e) {
    if (e.message.contains('integer overflow')) {
      throw const ValidationException(
        'The total exceeds the supported monetary range.',
      );
    }
    if (e.resultCode == 19) {
      throw ConflictException(
        'Database constraint rejected the change: ${e.message}',
      );
    }
    throw AppException('storage', 'Could not access local data.', e);
  }
}

Stream<T> protectStream<T>(Stream<T> source) => source.transform(
  StreamTransformer<T, T>.fromHandlers(
    handleError: (error, stack, sink) {
      if (error is SqliteException) {
        final mapped = error.message.contains('integer overflow')
            ? const ValidationException(
                'The total exceeds the supported monetary range.',
              )
            : AppException('storage', 'Could not read local data.', error);
        sink.addError(mapped, stack);
      } else {
        sink.addError(error, stack);
      }
    },
  ),
);

class StoreSupport {
  StoreSupport(this.db);
  final AppDatabase db;
  List<Variable> variables(List<Object> values) => [
    for (final value in values)
      if (value is int)
        Variable<int>(value)
      else
        Variable<String>(value as String),
  ];
  Future<void> activeCategory(String id) async {
    validateId(id);
    final rows = await db
        .customSelect(
          'SELECT id FROM categories WHERE id = ? AND archived_at IS NULL',
          variables: [Variable(id)],
        )
        .get();
    if (rows.isEmpty) {
      throw const ValidationException('Choose an active category.');
    }
  }

  Future<void> enqueue(String type, String id, String operation) async {
    await db.customStatement(
      'INSERT INTO sync_outbox (id,entity_type,entity_id,operation,created_at) VALUES (?,?,?,?,?)',
      [const Uuid().v4(), type, id, operation, instant(DateTime.now())],
    );
    db.markTablesUpdated({db.syncOutbox});
  }
}
