import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case expense
    case income
}

struct Transaction: Identifiable, Codable, Equatable {
    let id: String
    let merchant: String
    let amount: Double
    let date: Date
    let category: String
    let note: String?
    var type: TransactionType = .expense
}
