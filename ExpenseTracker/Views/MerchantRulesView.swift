import SwiftUI

struct MerchantRulesView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @State private var isShowingAddRule = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if viewModel.merchantRules.isEmpty {
                Text("No rules yet — add one to auto-categorize a merchant or person")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                List {
                    ForEach(viewModel.merchantRules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Contains \"\(rule.keyword)\"")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.primaryText)
                                Text("→ \(rule.category)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(viewModel.categoryColor(for: rule.category))
                            }
                            Spacer()
                        }
                        .padding(13)
                        .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .background(Palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Palette.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteMerchantRule(rule) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Auto-Categorization")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingAddRule = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddRule) {
            AddMerchantRuleView(categories: viewModel.categories.map(\.name)) { keyword, category in
                Task { await viewModel.addMerchantRule(keyword: keyword, category: category) }
            }
        }
    }
}

private struct AddMerchantRuleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var category: String
    let categories: [String]
    let onSave: (String, String) -> Void

    init(categories: [String], onSave: @escaping (String, String) -> Void) {
        self.categories = categories
        self._category = State(initialValue: categories.first ?? "Uncategorized")
        self.onSave = onSave
    }

    private var canSave: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("If merchant contains") {
                    TextField("e.g. a name or merchant", text: $keyword)
                        .autocorrectionDisabled()
                }
                Section("Always categorize as") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(keyword, category)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MerchantRulesView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository(), merchantRuleRepository: MockMerchantRuleRepository()))
    }
}
