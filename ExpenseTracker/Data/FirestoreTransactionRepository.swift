import Foundation
import FirebaseFirestore

struct FirestoreTransactionRepository: TransactionRepository {
    private let db = Firestore.firestore()

    func fetchTransactions() async throws -> [Transaction] {
        let snapshot = try await db.collection("transactions").getDocuments()
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let merchant = data["merchant"] as? String,
                  let amount = data["amount"] as? Double,
                  let category = data["category"] as? String,
                  let timestamp = data["date"] as? Timestamp else {
                return nil
            }
            let type = (data["type"] as? String).flatMap(TransactionType.init(rawValue:)) ?? .expense
            return Transaction(
                id: document.documentID,
                merchant: merchant,
                amount: amount,
                date: timestamp.dateValue(),
                category: category,
                note: data["note"] as? String,
                type: type
            )
        }
    }

    func addTransaction(_ transaction: Transaction) async throws {
        try await db.collection("transactions").document(transaction.id).setData(fieldData(for: transaction))
    }

    func updateTransaction(_ transaction: Transaction) async throws {
        try await db.collection("transactions").document(transaction.id).setData(fieldData(for: transaction))
    }

    func deleteTransaction(id: String) async throws {
        try await db.collection("transactions").document(id).delete()
    }

    private func fieldData(for transaction: Transaction) -> [String: Any] {
        var data: [String: Any] = [
            "merchant": transaction.merchant,
            "amount": transaction.amount,
            "date": Timestamp(date: transaction.date),
            "category": transaction.category,
            "type": transaction.type.rawValue
        ]
        if let note = transaction.note {
            data["note"] = note
        }
        return data
    }
}
