import Foundation
import FirebaseFirestore

struct FirestoreMerchantRuleRepository: MerchantRuleRepository {
    private let db = Firestore.firestore()

    func fetchRules() async throws -> [MerchantRule] {
        let snapshot = try await db.collection("merchantRules").getDocuments()
        return snapshot.documents.compactMap { document in
            guard let category = document.data()["category"] as? String else { return nil }
            return MerchantRule(keyword: document.documentID, category: category)
        }
    }

    func addRule(_ rule: MerchantRule) async throws {
        try await db.collection("merchantRules").document(rule.keyword).setData(["category": rule.category])
    }

    func deleteRule(keyword: String) async throws {
        try await db.collection("merchantRules").document(keyword).delete()
    }
}
