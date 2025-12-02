import Foundation

extension String {
    func addingPercentEncoding(forURLComponents allowed: Bool) -> String? {
        if allowed {
            return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        }
        return self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }
}