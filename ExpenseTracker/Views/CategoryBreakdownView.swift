import SwiftUI
import Charts

struct CategoryBreakdownView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @State private var editingCategory: CategoryTotal?
    @State private var selectedAngleValue: Double?
    @State private var selectedCategoryName: String?
    @State private var selectedMonth = Date()
    @State private var isShowingManageCategories = false

    private var categoryTotals: [CategoryTotal] {
        viewModel.categoryTotals(for: selectedMonth)
    }

    private func category(atAngleValue value: Double) -> CategoryTotal? {
        var cumulative = 0.0
        for item in categoryTotals {
            cumulative += item.total
            if value <= cumulative {
                return item
            }
        }
        return categoryTotals.last
    }

    var body: some View {
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
                    .padding(.top, 8)

                    if categoryTotals.isEmpty {
                        Spacer()
                        Text("No expenses this month")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.mutedText)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 18) {
                                Chart(categoryTotals) { item in
                                    SectorMark(
                                        angle: .value("Total", item.total),
                                        innerRadius: .ratio(0.0),
                                        angularInset: 1.5
                                    )
                                    .foregroundStyle(item.color)
                                    .cornerRadius(2)
                                    .opacity(selectedCategoryName == nil || selectedCategoryName == item.category ? 1 : 0.35)
                                }
                                .chartAngleSelection(value: $selectedAngleValue)
                                .frame(height: 240)
                                .padding(.horizontal, 8)
                                .padding(.top, 10)

                                Text("Tap a slice to see its transactions")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.mutedText)

                                VStack(spacing: 10) {
                                    ForEach(categoryTotals) { item in
                                        CategoryCard(item: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture { editingCategory = item }
                                    }
                                }
                            }
                            .padding(18)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedCategoryName) { name in
                CategoryTransactionsView(viewModel: viewModel, category: name, color: viewModel.categoryColor(for: name))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Manage") { isShowingManageCategories = true }
                }
            }
        }
        .onChange(of: selectedAngleValue) { _, newValue in
            guard let newValue, let matched = category(atAngleValue: newValue) else { return }
            selectedCategoryName = matched.category
            selectedAngleValue = nil
        }
        .sheet(item: $editingCategory) { item in
            SetBudgetView(category: item.category, currentLimit: item.budgetLimit, currentColor: item.color) { limit in
                Task { await viewModel.setBudget(category: item.category, limit: limit) }
            } onColorChange: { color in
                Task { await viewModel.setCategoryColor(name: item.category, colorHex: color.toHex()) }
            } onDelete: {
                Task { await viewModel.deleteCategory(name: item.category) }
            }
        }
        .sheet(isPresented: $isShowingManageCategories) {
            ManageCategoriesView(viewModel: viewModel)
        }
    }
}

private struct CategoryCard: View {
    let item: CategoryTotal

    private var progress: Double? {
        guard let limit = item.budgetLimit, limit > 0 else { return nil }
        return min(item.total / limit, 1.0)
    }

    private var barColor: Color {
        guard let limit = item.budgetLimit, limit > 0 else { return item.color }
        let ratio = item.total / limit
        if ratio >= 1.0 { return Color(red: 0.85, green: 0.32, blue: 0.32) }
        if ratio >= 0.8 { return Color(red: 0.88, green: 0.62, blue: 0.28) }
        return item.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(Int(item.percentage.rounded()))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 22)
                    .background(item.color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(item.category)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)

                Spacer()

                Text(item.total, format: .currency(code: "SGD"))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.primaryText)
            }

            if let limit = item.budgetLimit {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.cardBorder)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: geometry.size.width * CGFloat(progress ?? 0))
                    }
                }
                .frame(height: 6)

                Text("\(limit - item.total >= 0 ? "" : "over by ")\(abs(limit - item.total), format: .currency(code: "SGD")) \(limit - item.total >= 0 ? "left" : "")  ·  budget \(limit, format: .currency(code: "SGD"))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.mutedText)
            } else {
                Text("Tap to set a budget")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.mutedText)
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

private struct SetBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    let category: String
    @State private var limitText: String
    @State private var color: Color
    @State private var isShowingDeleteConfirmation = false

    let onSave: (Double) -> Void
    let onColorChange: (Color) -> Void
    let onDelete: () -> Void

    init(
        category: String,
        currentLimit: Double?,
        currentColor: Color,
        onSave: @escaping (Double) -> Void,
        onColorChange: @escaping (Color) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.category = category
        self._limitText = State(initialValue: currentLimit.map { String(format: "%.2f", $0) } ?? "")
        self._color = State(initialValue: currentColor)
        self.onSave = onSave
        self.onColorChange = onColorChange
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Color") {
                    ColorPicker("Category color", selection: $color, supportsOpacity: false)
                }
                Section("Monthly budget for \(category)") {
                    TextField("Amount", text: $limitText)
                        .keyboardType(.decimalPad)
                }
                Section {
                    Button("Delete Category", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                } footer: {
                    Text("Existing transactions keep the \"\(category)\" label but lose its custom color and budget.")
                }
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onColorChange(color)
                        if let value = Double(limitText) {
                            onSave(value)
                        }
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(category)\"?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Category", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// Lists every category regardless of whether it has any transactions this
// month (or ever), so categories you've created but never used can still be
// deleted — the pie-chart cards only show categories with spend in the
// selected month.
private struct ManageCategoriesView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeleteCategory: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.categories) { category in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 12, height: 12)
                        Text(category.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.primaryText)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeleteCategory = category.name
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete \"\(pendingDeleteCategory ?? "")\"?",
                isPresented: Binding(
                    get: { pendingDeleteCategory != nil },
                    set: { if !$0 { pendingDeleteCategory = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Category", role: .destructive) {
                    if let name = pendingDeleteCategory {
                        Task { await viewModel.deleteCategory(name: name) }
                    }
                    pendingDeleteCategory = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteCategory = nil }
            }
        }
    }
}

#Preview {
    CategoryBreakdownView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository()))
}
