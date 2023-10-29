import SwiftUI

/// A control that initiates an async action.
public struct AsyncButton<Label: View>: View {
  let role: ButtonRole?
  let label: Label
  let action: () async -> Void

  @State private var task: Task<Void, Never>?

  private var inFlight: Bool {
    task != nil
  }

  public init(
    role: ButtonRole? = nil,
    action: @escaping () async -> Void,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.action = action
    self.label = label()
  }

  public var body: some View {
    Button(role: role) {
      task = Task.detached(priority: .userInitiated) { @MainActor in
        defer { task = nil }
        await action()
      }
    } label: {
      label.loading(inFlight)
    }
    .onDisappear { task?.cancel() }
    .allowsHitTesting(!inFlight)
  }
}

public struct DefaultAsyncButtonLabel<Label: View>: View {
  @Environment(\.isLoading) var isLoading

  @ViewBuilder var label: Label

  public var body: some View {
    ZStack {
      label.opacity(isLoading ? 0 : 1)

      if isLoading {
        ProgressView()
      }
    }
    .animation(.default, value: isLoading)
  }
}

extension AsyncButton where Label == DefaultAsyncButtonLabel<Text> {
  public init(
    _ title: some StringProtocol,
    role: ButtonRole? = nil,
    action: @escaping () async -> Void
  ) {
    self.init(
      role: role,
      action: action,
      label: {
        DefaultAsyncButtonLabel {
          Text(title)
        }
      }
    )
  }

  public init(
    _ titleKey: LocalizedStringKey,
    role: ButtonRole? = nil,
    action: @escaping () async -> Void
  ) {
    self.init(
      role: role,
      action: action,
      label: {
        DefaultAsyncButtonLabel {
          Text(titleKey)
        }
      }
    )
  }
}

extension AsyncButton {
  public init<Child: View>(
    role: ButtonRole? = nil,
    action: @escaping () async -> Void,
    @ViewBuilder label: @escaping () -> Child
  ) where Label == DefaultAsyncButtonLabel<Child> {
    self.init(
      role: role,
      action: action,
      label: { DefaultAsyncButtonLabel(label: label) }
    )
  }
}

struct AsyncButton_PreviewProvider: PreviewProvider {
  static var previews: some View {
    AsyncButton("Button") {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 5)
    }
  }
}

private enum LoadingEnvironmentKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// A property to access and modify the loading state within the environment.
  public var isLoading: Bool {
    get { self[LoadingEnvironmentKey.self] }
    set { self[LoadingEnvironmentKey.self] = newValue }
  }
}

extension View {
  /// Sets the loading state value in the environment.
  /// - Parameter value: A Boolean value indicating whether the view is in a loading state.
  /// - Returns: A modified view with the updated loading state in the environment.
  public func loading(_ value: Bool) -> some View {
    environment(\.isLoading, value)
  }
}
