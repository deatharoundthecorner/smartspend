import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/store_support.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/category.dart';

class DriftCategoryRepository extends StoreSupport
    implements CategoryRepository {
  DriftCategoryRepository(super.db);
  Category _map(QueryRow r) => Category(
    id: r.read('id'),
    name: r.read('name'),
    createdAt: utcDate(r.read('created_at')),
    updatedAt: utcDate(r.read('updated_at')),
    archivedAt: nullableDate(r.readNullable('archived_at')),
  );
  String _name(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 80) {
      throw const ValidationException(
        'Category name must contain 1 to 80 characters.',
      );
    }
    return clean;
  }

  @override
  Stream<List<Category>> watchCategories({
    bool includeArchived = false,
  }) => protectStream(
    db
        .customSelect(
          'SELECT * FROM categories ${includeArchived ? '' : 'WHERE archived_at IS NULL'} ORDER BY name COLLATE NOCASE,id',
          readsFrom: {db.categories},
        )
        .watch()
        .map((rows) => List.unmodifiable(rows.map(_map))),
  );
  @override
  Future<Category> createCategory(String name) => protect(
    () => db.transaction(() async {
      final clean = _name(name);
      final id = const Uuid().v4();
      final now = instant(DateTime.now());
      await db.customStatement(
        'INSERT INTO categories (id,name,created_at,updated_at) VALUES (?,?,?,?)',
        [id, clean, now, now],
      );
      await enqueue('category', id, 'upsert');
      db.markTablesUpdated({db.categories});
      return Category(
        id: id,
        name: clean,
        createdAt: utcDate(now),
        updatedAt: utcDate(now),
      );
    }),
  );
  Future<void> _exists(String id) async {
    validateId(id);
    if ((await db
            .customSelect(
              'SELECT id FROM categories WHERE id=?',
              variables: [Variable(id)],
            )
            .get())
        .isEmpty) {
      throw const NotFoundException('Category does not exist.');
    }
  }

  @override
  Future<void> renameCategory(String id, String name) => protect(
    () => db.transaction(() async {
      final clean = _name(name);
      await _exists(id);
      await db.customStatement(
        'UPDATE categories SET name=?,updated_at=? WHERE id=?',
        [clean, instant(DateTime.now()), id],
      );
      await enqueue('category', id, 'upsert');
      db.markTablesUpdated({db.categories});
    }),
  );
  @override
  Future<void> archiveCategory(String id) => protect(
    () => db.transaction(() async {
      await _exists(id);
      final now = instant(DateTime.now());
      final changed = await db.customUpdate(
        'UPDATE categories SET archived_at=?,updated_at=? WHERE id=? AND archived_at IS NULL',
        variables: variables([now, now, id]),
        updates: {db.categories},
      );
      if (changed > 0) await enqueue('category', id, 'upsert');
    }),
  );
}
