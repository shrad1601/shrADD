import SwiftUI

struct IncomeSourceTransactionsView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    let source: String
    let month: Date
    @State private var editingTransaction: Transaction?

    private var transactions: [Transaction] {
        let calendar = Calendar.current
        return viewModel.transactions
            .filter { $0.type == .income && $0.merchant == source && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    private var total: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if transactions.isEmpty {
                Text("No transactions from \(source) this month")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.mutedText)
            } else {
                List {
                    Section {
                        ForEach(transactions) { transaction in
                            TransactionRow(transaction: transaction, categoryColor: IncomeListView.incomeTop)
                                .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTransaction = transaction }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.deleteTransaction(transaction) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text("\(transactions.count) transaction\(transactions.count == 1 ? "" : "s")")
                            Spacer()
                            Text("+\(total, format: .currency(code: "SGD"))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.mutedText)
                        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 4, trailing: 18))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(source)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(existing: transaction, categories: viewModel.categories.map(\.name)) { name in
                await viewModel.addCustomCategory(name: name)
            } onSave: { id, merchant, amount, category, date, note, type in
                guard let id else { return }
                Task { await viewModel.updateTransaction(id: id, merchant: merchant, amount: amount, category: category, date: date, note: note, type: type) }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IncomeSourceTransactionsView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository()), source: "Ottodot", month: Date())
    }
}
