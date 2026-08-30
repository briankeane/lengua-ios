import SwiftUI

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  static let brand = Color(hex: 0x3D4AD9)
  static let brandDeep = Color(hex: 0x252F8C)
  static let brandSoft = Color(hex: 0xE9ECFF)
  static let surface = Color(hex: 0xFBFBF7)
  static let ink = Color(hex: 0x18213D)
  static let muted = Color(hex: 0x667085)
  static let line = Color(hex: 0xD9DEF2)
  static let danger = Color(hex: 0xC4324A)
}

extension Font {
  static func funnel(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .bold, .semibold, .heavy, .black, .medium: name = "FunnelSans-Bold"
    default: name = "FunnelSans-Regular"
    }
    return .custom(name, size: size)
  }

  static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .bold, .heavy, .black: name = "Inter-Bold"
    case .semibold, .medium: name = "Inter-SemiBold"
    default: name = "Inter-Regular"
    }
    return .custom(name, size: size)
  }
}

enum DesignRadius {
  static let card: CGFloat = 20
  static let control: CGFloat = 14
  static let pill: CGFloat = 999
}

enum DesignSpacing {
  static let md: CGFloat = 16
  static let lg: CGFloat = 24
}
