import Foundation

protocol CategoryRepository {
    func fetchCategories() async throws -> [Category]
    func addCategory(_ category: Category) async throws
    func deleteCategory(name: String) async throws
}
