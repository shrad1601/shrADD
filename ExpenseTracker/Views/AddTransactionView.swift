import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var type: TransactionType
    @State private var merchant: String
    @State private var amountText: String
    @State private var category: String
    @State private var date: Date
    @State private var note: String

    @State private var categories: [String]
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    private let existingId: String?
    let onAddCategory: (String) async -> String

    /// id is nil when creating a new transaction, or the existing id when editing one.
    let onSave: (_ id: String?, _ merchant: String, _ amount: Double, _ category: String, _ date: Date, _ note: String?, _ type: TransactionType) -> Void

    init(
        existing: Transaction? = nil,
        initialType: TransactionType = .expense,
        categories: [String],
        onAddCategory: @escaping (String) async -> String,
        onSave: @escaping (_ id: String?, _ merchant: String, _ amount: Double, _ category: String, _ date: Date, _ note: String?, _ type: TransactionType) -> Void
    ) {
        self.existingId = existing?.id
        self._type = State(initialValue: existing?.type ?? initialType)
        self._merchant = State(initialValue: existing?.merchant ?? "")
        self._amountText = State(initialValue: existing.map { String($0.amount) } ?? "")
        self._category = State(initialValue: existing?.category ?? categories.first ?? "Uncategorized")
        self._date = State(initialValue: existing?.date ?? Date())
        self._note = State(initialValue: existing?.note ?? "")
        self._categories = State(initialValue: categories)
        self.onAddCategory = onAddCategory
        self.onSave = onSave
    }

    private var amount: Double? {
        Double(amountText)
    }

    private var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section(type == .expense ? "Transaction" : "Income") {
                    TextField(type == .expense ? "Merchant" : "Source", text: $merchant)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    if type == .expense {
                        Picker("Category", selection: $category) {
                            ForEach(categories, id: \.self) { Text($0) }
                        }
                        Button("Add new category") { isAddingCategory = true }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }
                Section("Note") {
                    TextField("Optional description", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let savedCategory = type == .expense ? category : "Income"
                        onSave(existingId, merchant, amount ?? 0, savedCategory, date, note.isEmpty ? nil : note, type)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("New Category", isPresented: $isAddingCategory) {
                TextField("Category name", text: $newCategoryName)
                Button("Add") {
                    let nameToAdd = newCategoryName
                    newCategoryName = ""
                    Task {
                        let added = await onAddCategory(nameToAdd)
                        if !added.isEmpty {
                            if !categories.contains(added) {
                                categories.append(added)
                            }
                            category = added
                        }
                    }
                }
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
        }
    }

    private var navigationTitle: String {
        switch (existingId, type) {
        case (nil, .expense): return "Add Expense"
        case (nil, .income): return "Add Income"
        case (_, .expense): return "Edit Expense"
        case (_, .income): return "Edit Income"
        }
    }
}

#Preview {
    AddTransactionView(categories: CategoryStyle.defaultCategories.map(\.name)) { $0 } onSave: { _, _, _, _, _, _, _ in }
}
