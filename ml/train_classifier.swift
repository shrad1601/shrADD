import Foundation
import CreateML

let scratchDir = "/private/tmp/claude-501/-Users-shrad1601-Downloads-expense-tracker/a282702b-baf0-4d5a-b6ab-814f8d212fbd/scratchpad"
let dataURL = URL(fileURLWithPath: "\(scratchDir)/training_data.json")

let dataTable = try MLDataTable(contentsOf: dataURL)
print("Loaded \(dataTable.rows.count) rows, columns: \(dataTable.columnNames)")

let classifier = try MLTextClassifier(trainingData: dataTable, textColumn: "text", labelColumn: "label")

let trainingAccuracy = (1.0 - classifier.trainingMetrics.classificationError) * 100
print("Training accuracy: \(trainingAccuracy)%")

let validationError = classifier.validationMetrics.classificationError
if validationError.isNaN {
    print("No validation split (dataset too small to hold out a validation set).")
} else {
    print("Validation accuracy: \((1.0 - validationError) * 100)%")
}

let metadata = MLModelMetadata(
    author: "shrADD",
    shortDescription: "Predicts expense category from merchant name, trained on your own transaction history.",
    version: "1.0"
)

let outputURL = URL(fileURLWithPath: "\(scratchDir)/MerchantCategoryClassifier.mlmodel")
try classifier.write(to: outputURL, metadata: metadata)
print("Wrote model to \(outputURL.path)")
