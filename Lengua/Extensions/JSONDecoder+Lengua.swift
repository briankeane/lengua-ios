import Foundation

extension JSONDecoder {
  /// Decoder for Lengua API payloads whose timestamps are ISO8601 with a `Z`
  /// zone, with or without fractional seconds (`2026-08-01T10:00:00.000Z`).
  /// The stock `.iso8601` strategy rejects the fractional-seconds form.
  static var lenguaISO8601: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let string = try decoder.singleValueContainer().decode(String.self)
      if let date = fractionalFormatter.date(from: string) { return date }
      if let date = plainFormatter.date(from: string) { return date }
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Invalid ISO8601 date: \(string)"))
    }
    return decoder
  }

  private static let fractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let plainFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
