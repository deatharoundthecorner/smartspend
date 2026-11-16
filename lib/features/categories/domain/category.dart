class Category {
  const Category({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
}

abstract interface class CategoryRepository {
  Stream<List<Category>> watchCategories({bool includeArchived = false});
  Future<Category> createCategory(String name);
  Future<void> renameCategory(String id, String name);
  Future<void> archiveCategory(String id);
}
