import SwiftUI
import UIKit

enum Palette {
    static let background = adaptive(light: Color(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xFB / 255), dark: Color(red: 0x14 / 255, green: 0x10 / 255, blue: 0x1B / 255))
    static let cardBackground = adaptive(light: .white, dark: Color(red: 0x1F / 255, green: 0x19 / 255, blue: 0x29 / 255))
    static let cardBorder = adaptive(light: Color(red: 0xDC / 255, green: 0xDF / 255, blue: 0xF2 / 255), dark: Color(red: 0x2E / 255, green: 0x24 / 255, blue: 0x38 / 255))
    static let mutedText = adaptive(light: Color(red: 0x6B / 255, green: 0x64 / 255, blue: 0x78 / 255), dark: Color(red: 0x8A / 255, green: 0x7F / 255, blue: 0x97 / 255))
    static let primaryText = adaptive(light: Color(red: 0x1C / 255, green: 0x16 / 255, blue: 0x20 / 255), dark: .white)
    static let totalCardTop = Color(red: 0x93 / 255, green: 0x38 / 255, blue: 0x9F / 255)
    static let totalCardBottom = Color(red: 0x5C / 255, green: 0x1E / 255, blue: 0x70 / 255)

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

struct TransactionListView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @State private var isShowingAddSheet = false
    @State private var editingTransaction: Transaction?
    @State private var isShowingSettings = false
    @State private var selectedMonth = Date()
    @AppStorage("accentColorHex") private var accentColorHex: String = "93389F"

    private var accentColor: Color { Color(hex: accentColorHex) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Palette.mutedText)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

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
                .padding(.top, 4)
                .padding(.bottom, 10)

                if viewModel.dayGroups(for: selectedMonth, type: .expense).isEmpty {
                    Spacer()
                    Text("No expenses this month")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.mutedText)
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.dayGroups(for: selectedMonth, type: .expense)) { group in
                            Section {
                                ForEach(group.transactions) { transaction in
                                    TransactionRow(transaction: transaction, categoryColor: viewModel.categoryColor(for: transaction.category), showsDate: false)
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
                                DayHeader(date: group.date, total: group.total)
                                    .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 4, trailing: 18))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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
                            .background(accentColor)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddTransactionView(categories: viewModel.categories.map(\.name)) { name in
                await viewModel.addCustomCategory(name: name)
            } onSave: { id, merchant, amount, category, date, note, type in
                Task { await viewModel.addTransaction(merchant: merchant, amount: amount, category: category, date: date, note: note, type: type) }
            }
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(existing: transaction, categories: viewModel.categories.map(\.name)) { name in
                await viewModel.addCustomCategory(name: name)
            } onSave: { id, merchant, amount, category, date, note, type in
                guard let id else { return }
                Task { await viewModel.updateTransaction(id: id, merchant: merchant, amount: amount, category: category, date: date, note: note, type: type) }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

    private var isViewingCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.monthLabel(for: selectedMonth))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.72))
            Text(viewModel.monthTotal(for: selectedMonth), format: .currency(code: "SGD"))
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(.white)

            if isViewingCurrentMonth, let budget = viewModel.overallBudget {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.25))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(width: geometry.size.width * CGFloat(min(viewModel.monthlyTotal / budget, 1.0)))
                    }
                }
                .frame(height: 5)
                .padding(.top, 6)

                if let pace = viewModel.paceStatus {
                    Text(pace.message)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [accentColor, accentColor.darker(by: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct DayHeader: View {
    let date: Date
    let total: Double

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.dayNumberFormatter.string(from: date))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.primaryText)
            Text(Self.weekdayFormatter.string(from: date).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.mutedText)
            Spacer()
            Text(total, format: .currency(code: "SGD"))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.mutedText)
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let categoryColor: Color
    var showsDate: Bool = true

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let incomeColor = Color(red: 0.20, green: 0.62, blue: 0.42)

    private var isIncome: Bool { transaction.type == .income }

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(isIncome ? Self.incomeColor : categoryColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(isIncome ? "Income" : transaction.category)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isIncome ? Self.incomeColor : categoryColor)
                if let note = transaction.note {
                    Text(note)
                        .font(.system(size: 11))
                        .italic()
                        .foregroundStyle(Palette.mutedText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text((isIncome ? "+" : "") + transaction.amount.formatted(.currency(code: "SGD")))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isIncome ? Self.incomeColor : Palette.primaryText)
                if showsDate {
                    Text(Self.dateFormatter.string(from: transaction.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.mutedText)
                }
            }
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
    TransactionListView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository()))
}
