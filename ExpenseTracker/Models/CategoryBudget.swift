import Foundation

struct CategoryBudget: Identifiable, Equatable {
    var id: String { category }
    let category: String
    var limit: Double
}
