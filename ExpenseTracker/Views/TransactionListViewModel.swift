import SwiftUI

struct DayGroup: Identifiable {
    let id: Date
    let date: Date
    let transactions: [Transaction]
    let total: Double
}

struct CategoryTotal: Identifiable {
    var id: String { category }
    let category: String
    let total: Double
    let percentage: Double
    let budgetLimit: Double?
    let color: Color
}

struct PaceStatus {
    let message: String
    let isOverPace: Bool
    let expectedSpend: Double
}

struct IncomeSourceTotal: Identifiable {
    var id: String { source }
    let source: String
    let total: Double
    let count: Int
}

@MainActor
final class TransactionListViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var budgets: [String: Double] = [:]
    @Published var categories: [Category] = []
    @Published var merchantRules: [MerchantRule] = []
    @Published var errorMessage: String?

    private let repository: TransactionRepository
    private let budgetRepository: BudgetRepository
    private let categoryRepository: CategoryRepository
    private let merchantRuleRepository: MerchantRuleRepository

    init(
        repository: TransactionRepository = FirestoreTransactionRepository(),
        budgetRepository: BudgetRepository = FirestoreBudgetRepository(),
        categoryRepository: CategoryRepository = FirestoreCategoryRepository(),
        merchantRuleRepository: MerchantRuleRepository = FirestoreMerchantRuleRepository()
    ) {
        self.repository = repository
        self.budgetRepository = budgetRepository
        self.categoryRepository = categoryRepository
        self.merchantRuleRepository = merchantRuleRepository
    }

    var monthLabel: String {
        Self.monthFormatter.string(from: Date()).uppercased()
    }

    // Budgets and pace only ever track spending, so this (and everywhere else
    // that feeds them) excludes income — income is shown as its own separate
    // stat instead of netting against what you've spent.
    private var currentMonthTransactions: [Transaction] {
        transactions.filter { $0.type == .expense && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    var monthlyTotal: Double {
        currentMonthTransactions.reduce(0) { $0 + $1.amount }
    }

    static let overallBudgetKey = "OVERALL_BUDGET"

    var overallBudget: Double? {
        budgets[Self.overallBudgetKey]
    }

    func setOverallBudget(_ limit: Double) async {
        await setBudget(category: Self.overallBudgetKey, limit: limit)
    }

    var paceStatus: PaceStatus? {
        guard let budget = overallBudget, budget > 0 else { return nil }
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return nil }
        let daysInMonth = Double(range.count)
        let dayOfMonth = Double(calendar.component(.day, from: now))
        let expectedSpend = budget * (dayOfMonth / daysInMonth)
        let isOverPace = monthlyTotal > expectedSpend * 1.1
        return PaceStatus(
            message: isOverPace ? "Spending faster than planned" : "On track for the month",
            isOverPace: isOverPace,
            expectedSpend: expectedSpend
        )
    }

    var sortedTransactions: [Transaction] {
        currentMonthTransactions.sorted { $0.date > $1.date }
    }

    func monthLabel(for date: Date) -> String {
        Self.monthFormatter.string(from: date).uppercased()
    }

    func monthTotal(for month: Date) -> Double {
        transactions
            .filter { $0.type == .expense && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    func monthlyIncome(for month: Date) -> Double {
        transactions
            .filter { $0.type == .income && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    // Income often arrives as several small transactions from the same
    // source in one month (e.g. multiple pay-outs from the same tutoring
    // agency) — this groups them into one row per source so the Income tab
    // shows a summed total instead of a wall of near-duplicate entries.
    func incomeSourceTotals(for month: Date) -> [IncomeSourceTotal] {
        let calendar = Calendar.current
        let monthIncome = transactions.filter { $0.type == .income && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let grouped = Dictionary(grouping: monthIncome, by: \.merchant)
        return grouped.map { source, txns in
            IncomeSourceTotal(source: source, total: txns.reduce(0) { $0 + $1.amount }, count: txns.count)
        }
        .sorted { $0.total > $1.total }
    }

    // Income and expenses now live on completely separate tabs, so callers
    // always pass the type they want grouped — Transactions passes .expense,
    // Income passes .income.
    func dayGroups(for month: Date, type: TransactionType) -> [DayGroup] {
        let calendar = Calendar.current
        let monthTransactions = transactions.filter { $0.type == type && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let grouped = Dictionary(grouping: monthTransactions) { calendar.startOfDay(for: $0.date) }
        return grouped.map { day, txns in
            DayGroup(
                id: day,
                date: day,
                transactions: txns.sorted { $0.date > $1.date },
                total: txns.reduce(0) { $0 + $1.amount }
            )
        }
        .sorted { $0.date > $1.date }
    }

    // For the Compare tab: what fraction of this month's income has gone to
    // expenses. Nil when there's no income logged that month — dividing by
    // zero isn't a meaningful "0% spent", it's "this question doesn't apply".
    func percentageOfIncomeSpent(for month: Date) -> Double? {
        let income = monthlyIncome(for: month)
        guard income > 0 else { return nil }
        return (monthTotal(for: month) / income) * 100
    }

    func categoryTotals(for month: Date) -> [CategoryTotal] {
        let calendar = Calendar.current
        let monthTransactions = transactions.filter { $0.type == .expense && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
        let grouped = Dictionary(grouping: monthTransactions, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        let overallTotal = grouped.reduce(0) { $0 + $1.total }
        return grouped.map {
            CategoryTotal(
                category: $0.category,
                total: $0.total,
                percentage: overallTotal > 0 ? $0.total / overallTotal * 100 : 0,
                budgetLimit: budgets[$0.category],
                color: categoryColor(for: $0.category)
            )
        }
    }

    func categoryColor(for name: String) -> Color {
        if let match = categories.first(where: { $0.name == name }) {
            return Color(hex: match.colorHex)
        }
        return Color(hex: "9B95A6")
    }

    func load() async {
        do {
            async let fetchedTransactions = repository.fetchTransactions()
            async let fetchedBudgets = budgetRepository.fetchBudgets()
            async let fetchedCategories = categoryRepository.fetchCategories()
            async let fetchedRules = merchantRuleRepository.fetchRules()
            transactions = try await fetchedTransactions
            budgets = Dictionary(uniqueKeysWithValues: try await fetchedBudgets.map { ($0.category, $0.limit) })
            merchantRules = try await fetchedRules

            let existingCategories = try await fetchedCategories
            if existingCategories.isEmpty {
                for category in CategoryStyle.defaultCategories {
                    try await categoryRepository.addCategory(category)
                }
                categories = CategoryStyle.defaultCategories
            } else {
                categories = existingCategories
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMerchantRule(keyword: String, category: String) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        let rule = MerchantRule(keyword: trimmed, category: category)
        merchantRules.removeAll { $0.keyword == trimmed }
        merchantRules.append(rule)
        do {
            try await merchantRuleRepository.addRule(rule)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMerchantRule(_ rule: MerchantRule) async {
        merchantRules.removeAll { $0.keyword == rule.keyword }
        do {
            try await merchantRuleRepository.deleteRule(keyword: rule.keyword)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCustomCategory(name: String) async -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let existing = categories.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing.name
        }
        let colorHex = CategoryStyle.nextColor(usedCount: categories.count)
        let category = Category(name: trimmed, colorHex: colorHex)
        categories.append(category)
        do {
            try await categoryRepository.addCategory(category)
        } catch {
            errorMessage = error.localizedDescription
        }
        return trimmed
    }

    func deleteCategory(name: String) async {
        categories.removeAll { $0.name == name }
        budgets.removeValue(forKey: name)
        do {
            try await categoryRepository.deleteCategory(name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCategoryColor(name: String, colorHex: String) async {
        if let index = categories.firstIndex(where: { $0.name == name }) {
            categories[index] = Category(name: name, colorHex: colorHex)
        }
        do {
            try await categoryRepository.addCategory(Category(name: name, colorHex: colorHex))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setBudget(category: String, limit: Double) async {
        budgets[category] = limit
        do {
            try await budgetRepository.setBudget(category: category, limit: limit)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTransaction(merchant: String, amount: Double, category: String, date: Date, note: String?, type: TransactionType = .expense) async {
        let transaction = Transaction(
            id: UUID().uuidString,
            merchant: merchant,
            amount: amount,
            date: date,
            category: category,
            note: note,
            type: type
        )
        transactions.append(transaction)
        do {
            try await repository.addTransaction(transaction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTransaction(id: String, merchant: String, amount: Double, category: String, date: Date, note: String?, type: TransactionType = .expense) async {
        let transaction = Transaction(id: id, merchant: merchant, amount: amount, date: date, category: category, note: note, type: type)
        if let index = transactions.firstIndex(where: { $0.id == id }) {
            transactions[index] = transaction
        }
        do {
            try await repository.updateTransaction(transaction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTransaction(_ transaction: Transaction) async {
        transactions.removeAll { $0.id == transaction.id }
        do {
            try await repository.deleteTransaction(id: transaction.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}
