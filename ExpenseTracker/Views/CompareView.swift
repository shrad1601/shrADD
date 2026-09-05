import SwiftUI

struct CompareView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @State private var selectedMonth = Date()
    @AppStorage("accentColorHex") private var accentColorHex: String = "93389F"

    private var accentColor: Color { Color(hex: accentColorHex) }
    private static let incomeColor = Color(red: 0.16, green: 0.52, blue: 0.36)
    private static let deficitColor = Color(red: 0.85, green: 0.32, blue: 0.32)

    private var income: Double { viewModel.monthlyIncome(for: selectedMonth) }
    private var expense: Double { viewModel.monthTotal(for: selectedMonth) }
    private var net: Double { income - expense }

    var body: some View {
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

                    Text(viewModel.monthLabel(for: selectedMonth))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.mutedText)
                        .frame(maxWidth: .infinity)

                    Button {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Palette.mutedText)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            statCard(title: "Income", amount: income, color: Self.incomeColor)
                            statCard(title: "Expenditure", amount: expense, color: accentColor)
                        }
                        .padding(.top, 14)

                        netCard
                        comparisonCard
                    }
                    .padding(18)
                }
            }
        }
    }

    private func statCard(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Palette.mutedText)
            Text(amount, format: .currency(code: "SGD"))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var netCard: some View {
        let isSurplus = net >= 0
        return VStack(alignment: .leading, spacing: 6) {
            Text(isSurplus ? "SURPLUS" : "DEFICIT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Palette.mutedText)
            Text(abs(net), format: .currency(code: "SGD"))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(isSurplus ? Self.incomeColor : Self.deficitColor)
            Text(isSurplus ? "left over after expenses this month" : "spent beyond what you earned this month")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SPENT VS EARNED")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Palette.mutedText)

            if let percentage = viewModel.percentageOfIncomeSpent(for: selectedMonth) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Palette.cardBorder)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(percentage > 100 ? Self.deficitColor : accentColor)
                            .frame(width: geometry.size.width * CGFloat(min(percentage / 100, 1.0)))
                    }
                }
                .frame(height: 10)

                Text("You've spent \(Int(percentage.rounded()))% of what you earned this month")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .padding(.top, 2)
            } else {
                Text("No income logged this month yet — nothing to compare against.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    CompareView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository()))
}
