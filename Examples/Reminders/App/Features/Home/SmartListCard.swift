import SwiftUI

/// One card of the grid at the top of Home: a smart list and the number of its reminders.
struct SmartListCard: View {
  let smartList: SmartList
  let count: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: smartList.symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(ListStyle.color(named: smartList.color), in: Circle())
          .accessibilityHidden(true)
        Spacer()
        Text(count, format: .number)
          .font(.title2.bold())
          .foregroundStyle(.primary)
          .accessibilityIdentifier("home.smart.\(smartList.rawValue).count")
      }
      Text(smartList.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
  }
}
