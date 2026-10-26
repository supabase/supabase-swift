import Foundation

/// The JSON coding of the formats the client persists: the session and the PKCE flow records.
///
/// Dates are RFC 3339 strings. They are written in UTC with up to nine fractional digits, so a
/// value survives a save and a load unchanged: a `Date` keeps finer than nanosecond precision only
/// within a year of 2001-01-01. They are read with zero to nine fractional digits and any offset,
/// the range GoTrue emits.
enum PersistedJSON {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(PersistedJSON.timestamp(from: date))
    }
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      guard let date = PersistedJSON.date(from: string) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Invalid RFC 3339 timestamp: \(string)"
        )
      }
      return date
    }
    return decoder
  }()

  private static let unixEpochFromReferenceDate: Int64 = 978_307_200
  private static let secondsPerDay: Int64 = 86_400
  private static let nanosecondsPerSecond = 1_000_000_000

  static func timestamp(from date: Date) -> String {
    let reference = date.timeIntervalSinceReferenceDate
    var seconds = reference.rounded(.down)
    var nanoseconds = Int(((reference - seconds) * 1e9).rounded())
    if nanoseconds == nanosecondsPerSecond {
      seconds += 1
      nanoseconds = 0
    }

    let unixSeconds = Int64(seconds) + unixEpochFromReferenceDate
    let days = floorDivide(unixSeconds, secondsPerDay)
    let secondOfDay = Int(unixSeconds - days * secondsPerDay)
    let (year, month, day) = civilDate(fromDaysSinceUnixEpoch: days)

    var result =
      "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
      + "T\(padded(secondOfDay / 3600, 2)):\(padded(secondOfDay / 60 % 60, 2)):"
      + padded(secondOfDay % 60, 2)
    if nanoseconds > 0 {
      var fraction = padded(nanoseconds, 9)
      while fraction.hasSuffix("0") { fraction.removeLast() }
      result += ".\(fraction)"
    }
    return result + "Z"
  }

  static func date(from string: String) -> Date? {
    var scanner = TimestampScanner(Array(string.utf8))

    guard
      let year = scanner.digits(4), scanner.skip("-"),
      let month = scanner.digits(2), scanner.skip("-"),
      let day = scanner.digits(2), scanner.skip("T") || scanner.skip("t"),
      let hour = scanner.digits(2), scanner.skip(":"),
      let minute = scanner.digits(2), scanner.skip(":"),
      let second = scanner.digits(2)
    else { return nil }

    var nanoseconds = 0
    if scanner.skip(".") {
      let fraction = scanner.fractionDigits()
      guard (1...9).contains(fraction.count) else { return nil }
      nanoseconds = fraction.value
      for _ in fraction.count..<9 { nanoseconds *= 10 }
    }

    let offsetSeconds: Int
    if scanner.skip("Z") || scanner.skip("z") {
      offsetSeconds = 0
    } else if let sign = scanner.sign(), let offsetHours = scanner.digits(2) {
      var offsetMinutes = 0
      if !scanner.isAtEnd {
        _ = scanner.skip(":")
        guard let minutes = scanner.digits(2) else { return nil }
        offsetMinutes = minutes
      }
      guard offsetHours < 24, offsetMinutes < 60 else { return nil }
      offsetSeconds = sign * (offsetHours * 3600 + offsetMinutes * 60)
    } else {
      return nil
    }

    guard
      scanner.isAtEnd,
      (1...12).contains(month),
      (1...daysInMonth(month, year: year)).contains(day),
      hour < 24, minute < 60, second < 60
    else { return nil }

    let days = daysSinceUnixEpoch(year: year, month: month, day: day)
    let unixSeconds =
      days * secondsPerDay + Int64(hour * 3600 + minute * 60 + second) - Int64(offsetSeconds)
    return Date(
      timeIntervalSinceReferenceDate: Double(unixSeconds - unixEpochFromReferenceDate)
        + Double(nanoseconds) / 1e9
    )
  }

  private static func padded(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }

  private static func floorDivide(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let quotient = lhs / rhs
    return lhs % rhs < 0 ? quotient - 1 : quotient
  }

  private static func daysInMonth(_ month: Int, year: Int) -> Int {
    switch month {
    case 2:
      let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
      return isLeapYear ? 29 : 28
    case 4, 6, 9, 11:
      return 30
    default:
      return 31
    }
  }

  // Howard Hinnant's `days_from_civil` and `civil_from_days`, proleptic Gregorian calendar.
  private static func daysSinceUnixEpoch(year: Int, month: Int, day: Int) -> Int64 {
    let year = Int64(month <= 2 ? year - 1 : year)
    let era = (year >= 0 ? year : year - 399) / 400
    let yearOfEra = year - era * 400
    let shiftedMonth = Int64(month > 2 ? month - 3 : month + 9)
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + Int64(day) - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  private static func civilDate(fromDaysSinceUnixEpoch days: Int64) -> (Int, Int, Int) {
    let days = days + 719_468
    let era = (days >= 0 ? days : days - 146_096) / 146_097
    let dayOfEra = days - era * 146_097
    let yearOfEra =
      (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (Int(year), Int(month), Int(day))
  }
}

private struct TimestampScanner {
  private let bytes: [UInt8]
  private var index = 0

  init(_ bytes: [UInt8]) {
    self.bytes = bytes
  }

  var isAtEnd: Bool { index == bytes.count }

  mutating func skip(_ character: Character) -> Bool {
    guard !isAtEnd, bytes[index] == character.asciiValue else { return false }
    index += 1
    return true
  }

  mutating func digits(_ count: Int) -> Int? {
    guard index + count <= bytes.count else { return nil }
    var value = 0
    for byte in bytes[index..<index + count] {
      guard let digit = Self.digit(byte) else { return nil }
      value = value * 10 + digit
    }
    index += count
    return value
  }

  mutating func fractionDigits() -> (value: Int, count: Int) {
    var value = 0
    var count = 0
    while !isAtEnd, let digit = Self.digit(bytes[index]) {
      if count < 9 { value = value * 10 + digit }
      count += 1
      index += 1
    }
    return (value, count)
  }

  mutating func sign() -> Int? {
    if skip("+") { return 1 }
    if skip("-") { return -1 }
    return nil
  }

  private static func digit(_ byte: UInt8) -> Int? {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) ? Int(byte - UInt8(ascii: "0")) : nil
  }
}
