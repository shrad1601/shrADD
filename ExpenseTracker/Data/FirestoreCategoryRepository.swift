import Foundation
import FirebaseFirestore

struct FirestoreCategoryRepository: CategoryRepository {
    private let db = Firestore.firestore()

    func fetchCategories() async throws -> [Category] {
        let snapshot = try await db.collection("categories").getDocuments()
        return snapshot.documents.compactMap { document in
            guard let colorHex = document.data()["color"] as? String else { return nil }
            return Category(name: document.documentID, colorHex: colorHex)
        }
    }

    func addCategory(_ category: Category) async throws {
        try await db.collection("categories").document(category.name).setData(["color": category.colorHex])
    }

    func deleteCategory(name: String) async throws {
        try await db.collection("categories").document(name).delete()
    }
}
