import SwiftUI

/// The colors and icons that a list can have. The database stores the names.
enum ListStyle {
  // swift-format adds a trailing comma here, and SwiftLint refuses it.
  // swift-format-ignore
  static let colors: [(name: String, color: Color)] = [
    ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
    ("mint", .mint), ("teal", .teal), ("cyan", .cyan), ("blue", .blue),
    ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("brown", .brown)
  ]

  // SF Symbol names.
  // swift-format-ignore
  static let icons: [String] = [
    "list.bullet", "bookmark.fill", "mappin", "gift.fill", "birthday.cake.fill",
    "graduationcap.fill", "backpack.fill", "pencil.and.ruler.fill", "doc.fill", "book.fill",
    "creditcard.fill", "dumbbell.fill", "fork.knife", "cart", "house.fill",
    "building.2.fill", "airplane", "car.fill", "pawprint.fill", "leaf.fill",
    "heart.fill", "star.fill", "music.note", "gamecontroller.fill"
  ]

  static let defaultColor = "blue"
  static let defaultIcon = "list.bullet"

  static func color(named name: String) -> Color {
    colors.first { $0.name == name }?.color ?? .blue
  }
}

/// The round colored icon of a list.
struct ListIcon: View {
  let list: ReminderList
  var size: CGFloat = 30

  var body: some View {
    Image(systemName: list.icon)
      .font(.system(size: size * 0.45, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(ListStyle.color(named: list.color), in: Circle())
      .accessibilityHidden(true)
  }
}
