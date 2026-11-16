import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartspend/core/database/app_database.dart' show AppDatabase;
import 'package:smartspend/features/categories/data/drift_category_repository.dart';

import 'generated_migrations/schema.dart';

void main() {
  test('new database matches committed version 1 schema snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await SchemaVerifier(GeneratedHelper()).migrateAndValidate(db, 1);
      expect(
        await DriftCategoryRepository(db).watchCategories().first,
        hasLength(10),
      );
    } finally {
      await db.close();
    }
  });
  test(
    'opening snapshot version 1 preserves existing data without reseeding',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final connection = await verifier.startAt(1);
      final db = AppDatabase(connection);
      try {
        // A snapshot represents an already-created database; onCreate must not rerun.
        final repo = DriftCategoryRepository(db);
        final category = await repo.createCategory('Existing user category');
        await verifier.migrateAndValidate(db, 1);
        final rows = await repo.watchCategories().first;
        expect(rows, hasLength(1));
        expect(rows.single.id, category.id);
      } finally {
        await db.close();
      }
    },
  );
}
