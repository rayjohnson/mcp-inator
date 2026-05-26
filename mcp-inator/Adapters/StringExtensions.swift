import Foundation

extension String {
    func matches(pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
