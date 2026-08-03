import Foundation
import XCTest
@testable import MomentumCore

final class CSVEncoderTests: XCTestCase {
    func test_rfc4180QuotingEscapesCommasQuotesAndLineBreaks() throws {
        let data = try RFC4180CSVEncoder().encode(
            headers: ["id", "name", "note"],
            rows: [["1", "Press, incline", "He said \"go\"\r\nNext set"]]
        )

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "id,name,note\r\n1,\"Press, incline\",\"He said \"\"go\"\"\r\nNext set\"\r\n"
        )
    }

    func test_unicodeIsRetainedInUTF8Output() throws {
        let data = try RFC4180CSVEncoder().encode(
            headers: ["name", "note"],
            rows: [["Café 燕麦", "नमस्ते 🏋🏽"]]
        )

        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            "name,note\r\nCafé 燕麦,नमस्ते 🏋🏽\r\n"
        )
    }

    func test_decimalFormattingAlwaysUsesPeriodAndDoesNotGroupDigits() {
        let encoder = RFC4180CSVEncoder()

        XCTAssertEqual(encoder.decimalString(Decimal(string: "1234.50")!), "1234.5")
        XCTAssertEqual(encoder.decimalString(Decimal(string: "0.125")!), "0.125")
    }

    func test_everyRowMustContainTheHeaderColumnCount() {
        XCTAssertThrowsError(try RFC4180CSVEncoder().encode(
            headers: ["id", "name"],
            rows: [["1"]]
        )) { error in
            XCTAssertEqual(
                error as? CSVEncodingError,
                .columnCountMismatch(row: 1, expected: 2, actual: 1)
            )
        }
    }

    func test_emptyAndOrdinaryFieldsRemainParseable() throws {
        let data = try RFC4180CSVEncoder().encode(
            headers: ["a", "b", "c"],
            rows: [["", "plain", " spaced "]]
        )

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "a,b,c\r\n,plain, spaced \r\n")
    }

    func test_isoTimestampUsesInternetDateTimeWithFractionalSeconds() {
        XCTAssertEqual(
            RFC4180CSVEncoder().iso8601String(Date(timeIntervalSince1970: 0)),
            "1970-01-01T00:00:00.000Z"
        )
    }
}
