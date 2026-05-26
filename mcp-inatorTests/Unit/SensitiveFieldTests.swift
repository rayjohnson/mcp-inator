import XCTest
@testable import mcp_inator

final class SensitiveFieldTests: XCTestCase {

    func testLiteralValueIsSensitive() {
        XCTAssertTrue(EnvVar.defaultSensitivity(for: "ghp_abc123"))
    }

    func testEnvVarReferenceIsNotSensitive() {
        XCTAssertFalse(EnvVar.defaultSensitivity(for: "${GITHUB_TOKEN}"))
    }

    func testEnvVarReferenceWithUnderscoreIsNotSensitive() {
        XCTAssertFalse(EnvVar.defaultSensitivity(for: "${MY_API_KEY}"))
    }

    func testLowercaseEnvVarReferenceIsSensitive() {
        // lowercase var names don't match the heuristic pattern — treated as sensitive
        XCTAssertTrue(EnvVar.defaultSensitivity(for: "${github_token}"))
    }

    func testEmptyValueIsSensitive() {
        XCTAssertTrue(EnvVar.defaultSensitivity(for: ""))
    }

    func testPartialEnvVarIsSensitive() {
        XCTAssertTrue(EnvVar.defaultSensitivity(for: "${INCOMPLETE"))
    }

    func testEnvVarInitDefaultSensitivity() {
        let literal = EnvVar(key: "TOKEN", value: "abc123")
        XCTAssertTrue(literal.isSensitive)

        let reference = EnvVar(key: "TOKEN", value: "${API_KEY}")
        XCTAssertFalse(reference.isSensitive)
    }

    func testEnvVarInitOverrideSensitivity() {
        let forced = EnvVar(key: "TOKEN", value: "${SECRET}", isSensitive: true)
        XCTAssertTrue(forced.isSensitive)
    }
}
