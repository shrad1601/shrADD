import Foundation

struct Category: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let colorHex: String
}
