import SwiftUI

struct IncomeListView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @State private var isShowingAddSheet = false
    @State private var selectedSource: String?
    @State private var selectedMonth = Date()

    static let incomeTop = Color(red: 0.16, green: 0.52, blue: 0.36)
    static let incomeBottom = Color(red: 0.09, green: 0.33, blue: 0.23)

    var body: some View {
        AuthLockView(reason: "Unlock to view your income") {
            lockedContent
        }
    }

    private var lockedContent: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(Palette.mutedText)
                        }

                        totalCard

                        Button {
                            selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Palette.mutedText)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    let sources = viewModel.incomeSourceTotals(for: selectedMonth)

                    if sources.isEmpty {
                        Spacer()
                        Text("No income this month")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.mutedText)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                Text("Tap a source to see its individual transactions")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.mutedText)
                                    .padding(.top, 4)

                                ForEach(sources) { item in
                                    IncomeSourceCard(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedSource = item.source }
                                }
                            }
                            .padding(18)
                        }
                    }
                }
                .padding(.bottom, 70)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            isShowingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Self.incomeTop)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationDestination(item: $selectedSource) { source in
                IncomeSourceTransactionsView(viewModel: viewModel, source: source, month: selectedMonth)
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddTransactionView(initialType: .income, categories: viewModel.categories.map(\.name)) { name in
                await viewModel.addCustomCategory(name: name)
            } onSave: { id, merchant, amount, category, date, note, type in
                Task { await viewModel.addTransaction(merchant: merchant, amount: amount, category: category, date: date, note: note, type: type) }
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.monthLabel(for: selectedMonth))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.72))
            Text(viewModel.monthlyIncome(for: selectedMonth), format: .currency(code: "SGD"))
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [Self.incomeTop, Self.incomeBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct IncomeSourceCard: View {
    let item: IncomeSourceTotal

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(IncomeListView.incomeTop)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.source)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("\(item.count) transaction\(item.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.mutedText)
            }

            Spacer()

            Text("+\(item.total, format: .currency(code: "SGD"))")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(IncomeListView.incomeTop)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.mutedText)
        }
        .padding(13)
        .background(Palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    IncomeListView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository()))
}
