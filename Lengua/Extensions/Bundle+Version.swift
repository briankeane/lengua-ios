import Foundation

extension Bundle {
  var releaseVersionNumber: String? {
    infoDictionary?["CFBundleShortVersionString"] as? String
  }
}
