import Foundation
import SylvraCore

/// Fixture diff for `--demo`, previews and screenshots.
public struct DemoDiffLoader: DiffLoading {
    /// Simulates a push after the screen opened (`--new-commits`).
    private let simulatesPush: Bool
    private let started = Date()

    public init(simulatesPush: Bool = false) {
        self.simulatesPush = simulatesPush
    }

    public func loadReviewProgress(for id: PullRequestID) async throws -> ReviewProgress {
        ReviewProgress(
            headSHA: simulatesPush && Date().timeIntervalSince(started) > 3 ? "f00dfeed" : "e08b5a1",
            lastReviewedSHA: "c0ffee1",
            lastReviewedAt: Date().addingTimeInterval(-26 * 3600))
    }

    public func loadDiff(for id: PullRequestID, from base: String, to head: String) async throws -> [FileDiff] {
        UnifiedDiffParser.parse(Self.sinceLastReviewDiff)
    }

    /// What changed after the reviewer's last review: quantities and the CSV header.
    static let sinceLastReviewDiff = """
        diff --git a/Sources/Billing/Invoice.swift b/Sources/Billing/Invoice.swift
        index 3333333..4444444 100644
        --- a/Sources/Billing/Invoice.swift
        +++ b/Sources/Billing/Invoice.swift
        @@ -8,6 +8,7 @@ struct Invoice: Codable {
         struct LineItem: Codable {
             let name: String
             let price: Decimal
        +    let quantity: Decimal
         }
        diff --git a/Sources/Export/CSVEncoder.swift b/Sources/Export/CSVEncoder.swift
        index 5555550..5555555 100644
        --- a/Sources/Export/CSVEncoder.swift
        +++ b/Sources/Export/CSVEncoder.swift
        @@ -4,7 +4,7 @@
         struct CSVEncoder {
             func encode(_ items: [LineItem]) -> Data {
        -        var lines = ["name,price"]
        +        var lines = ["name,price,quantity"]
                 for item in items {
        -            lines.append("\\(item.name),\\(item.price)")
        +            lines.append("\\(item.name),\\(item.price),\\(item.quantity)")
                 }
        """

    public func loadDiff(for id: PullRequestID) async throws -> PullRequestDiff {
        PullRequestDiff(
            files: UnifiedDiffParser.parse(Self.diff),
            viewedPaths: ["Sources/Billing/Invoice.swift", "Tests/BillingTests/InvoiceServiceTests.swift"],
            nodeID: "demo")
    }

    public func loadFileContent(for id: PullRequestID, path: String, ref: String) async throws -> String {
        guard path == "Sources/Billing/InvoiceService.swift" else { return "" }
        return Self.invoiceServiceHead
    }

    public func setViewed(_ viewed: Bool, path: String, pullRequestNodeID: String) async throws {}

    /// The demo PR's four commits, each touching part of the files (matches `DemoPullRequestDetailLoader`).
    public func loadCommitDiff(for id: PullRequestID, sha: String) async throws -> [FileDiff] {
        let paths: [String] =
            switch sha.prefix(7) {
            case "9a1f04c": ["Sources/Export/CSVEncoder.swift"]
            case "3be7d12": ["Sources/Export/ExportFormat.swift", "Sources/Billing/InvoiceService.swift"]
            case "c40e9a8": ["Sources/Billing/Invoice.swift"]
            default: ["Tests/BillingTests/InvoiceServiceTests.swift", "Package.resolved"]
            }
        return UnifiedDiffParser.parse(Self.diff).filter { paths.contains($0.path) }
    }

    static let invoiceServiceHead = """
        import Foundation

        /// Calculates and exports invoices.
        struct InvoiceService {
            let repository: InvoiceRepository

            func total(for invoice: Invoice) -> Decimal {
                invoice.items.reduce(.zero) { sum, item in
                    sum + (item.price * item.quantity).rounded(2)
                }
            }

            func export(_ invoice: Invoice, as format: ExportFormat) throws -> Data {
                switch format {
                case .json: return try JSONEncoder().encode(invoice)
                case .csv: return CSVEncoder().encode(invoice.items)
                }
            }
        }
        """

    static let diff = """
        diff --git a/Sources/Billing/InvoiceService.swift b/Sources/Billing/InvoiceService.swift
        index 1111111..2222222 100644
        --- a/Sources/Billing/InvoiceService.swift
        +++ b/Sources/Billing/InvoiceService.swift
        @@ -4,14 +4,19 @@ import Foundation
         struct InvoiceService {
             let repository: InvoiceRepository
        \u{20}
             func total(for invoice: Invoice) -> Decimal {
        -        invoice.items.reduce(0) { $0 + $1.price }
        +        invoice.items.reduce(.zero) { sum, item in
        +            sum + (item.price * item.quantity).rounded(2)
        +        }
             }
        \u{20}
        -    func export(_ invoice: Invoice) throws -> Data {
        -        try JSONEncoder().encode(invoice)
        +    func export(_ invoice: Invoice, as format: ExportFormat) throws -> Data {
        +        switch format {
        +        case .json: return try JSONEncoder().encode(invoice)
        +        case .csv: return CSVEncoder().encode(invoice.items)
        +        }
             }
         }
        diff --git a/Sources/Billing/Invoice.swift b/Sources/Billing/Invoice.swift
        index 3333333..4444444 100644
        --- a/Sources/Billing/Invoice.swift
        +++ b/Sources/Billing/Invoice.swift
        @@ -8,6 +8,7 @@ struct Invoice: Codable {
         struct LineItem: Codable {
             let name: String
             let price: Decimal
        +    let quantity: Decimal
         }
        diff --git a/Sources/Export/CSVEncoder.swift b/Sources/Export/CSVEncoder.swift
        new file mode 100644
        index 0000000..5555555
        --- /dev/null
        +++ b/Sources/Export/CSVEncoder.swift
        @@ -0,0 +1,12 @@
        +import Foundation
        +
        +/// Encodes line items as CSV (RFC 4180).
        +struct CSVEncoder {
        +    func encode(_ items: [LineItem]) -> Data {
        +        var lines = ["name,price,quantity"]
        +        for item in items {
        +            lines.append("\\(item.name),\\(item.price),\\(item.quantity)")
        +        }
        +        return Data(lines.joined(separator: "\\n").utf8)
        +    }
        +}
        diff --git a/Sources/Export/ExportFormat.swift b/Sources/Export/ExportFormat.swift
        new file mode 100644
        index 0000000..6666666
        --- /dev/null
        +++ b/Sources/Export/ExportFormat.swift
        @@ -0,0 +1,4 @@
        +enum ExportFormat {
        +    case json
        +    case csv
        +}
        diff --git a/Tests/BillingTests/InvoiceServiceTests.swift b/Tests/BillingTests/InvoiceServiceTests.swift
        index 7777777..8888888 100644
        --- a/Tests/BillingTests/InvoiceServiceTests.swift
        +++ b/Tests/BillingTests/InvoiceServiceTests.swift
        @@ -12,4 +12,10 @@ struct InvoiceServiceTests {
             @Test func totalSumsItems() {
                 #expect(service.total(for: .sample) == 42)
             }
        +
        +    @Test func exportsCSV() throws {
        +        let data = try service.export(.sample, as: .csv)
        +        #expect(String(decoding: data, as: UTF8.self).hasPrefix("name,price"))
        +    }
         }
        diff --git a/Package.resolved b/Package.resolved
        index 9999999..aaaaaaa 100644
        --- a/Package.resolved
        +++ b/Package.resolved
        @@ -1,3 +1,3 @@
         {
        -  "originHash" : "1a2b3c",
        +  "originHash" : "4d5e6f",
         }
        """
}
