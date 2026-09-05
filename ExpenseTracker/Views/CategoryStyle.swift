import SwiftUI

enum CategoryStyle {
    /// Seeded into Firestore the first time the app runs with no categories yet.
    static let defaultCategories: [Category] = [
        Category(name: "Food", colorHex: "FF7A45"),
        Category(name: "Transport", colorHex: "FFC93C"),
        Category(name: "Shopping", colorHex: "2EC4B6"),
        Category(name: "Subscriptions", colorHex: "7B61FF"),
        Category(name: "Utilities", colorHex: "FF5D8F"),
        Category(name: "Activities", colorHex: "4CD964"),
        Category(name: "Uncategorized", colorHex: "9B95A6")
    ]

    /// Rotated through when auto-assigning a color to a newly created custom category.
    static let vividRotation: [String] = [
        "FF7A45", "FFC93C", "2EC4B6", "7B61FF", "FF5D8F", "4CD964",
        "3AB0FF", "F45B69", "B5838D", "6FCF97"
    ]

    static func nextColor(usedCount: Int) -> String {
        vividRotation[usedCount % vividRotation.count]
    }
}
