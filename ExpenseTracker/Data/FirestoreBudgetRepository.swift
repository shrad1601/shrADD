import Foundation
import FirebaseFirestore

struct FirestoreBudgetRepository: BudgetRepository {
    private let db = Firestore.firestore()

    func fetchBudgets() async throws -> [CategoryBudget] {
        let snapshot = try await db.collection("budgets").getDocuments()
        return snapshot.documents.compactMap { document in
            guard let limit = document.data()["limit"] as? Double else { return nil }
            return CategoryBudget(category: document.documentID, limit: limit)
        }
    }

    func setBudget(category: String, limit: Double) async throws {
        try await db.collection("budgets").document(category).setData(["limit": limit])
    }
}
