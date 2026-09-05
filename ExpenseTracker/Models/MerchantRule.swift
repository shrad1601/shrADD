import Foundation

struct MerchantRule: Identifiable, Equatable {
    var id: String { keyword }
    let keyword: String
    let category: String
}
