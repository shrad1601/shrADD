import Foundation

final class MockCategoryRepository: CategoryRepository {
    private var categories: [Category] = CategoryStyle.defaultCategories

    func fetchCategories() async throws -> [Category] {
        categories
    }

    func addCategory(_ category: Category) async throws {
        categories.append(category)
    }

    func deleteCategory(name: String) async throws {
        categories.removeAll { $0.name == name }
    }
}
