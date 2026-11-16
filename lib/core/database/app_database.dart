import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
part 'app_database.g.dart';

@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      const names = [
        'Food & Groceries',
        'Transport',
        'Utilities',
        'Bills & Subscriptions',
        'Shopping',
        'Healthcare',
        'Education',
        'Entertainment',
        'Housing',
        'Other',
      ];
      for (final name in names) {
        await customStatement(
          'INSERT INTO categories (id,name,created_at,updated_at) VALUES (?,?,?,?)',
          [const Uuid().v4(), name, now, now],
        );
      }
      await customStatement(
        "INSERT INTO app_settings (key,value) VALUES ('currency','LKR')",
      );
    },
    onUpgrade: (m, from, to) async {
      // No released predecessor exists. Add explicit, tested incremental steps
      // when introducing schema v2; never delete or recreate the database.
      throw StateError('Unsupported schema upgrade $from → $to');
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      final violations = await customSelect('PRAGMA foreign_key_check').get();
      if (violations.isNotEmpty) {
        throw StateError('Database foreign-key violation');
      }
    },
  );
}
