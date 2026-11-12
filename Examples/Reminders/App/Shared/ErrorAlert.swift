import SwiftUI

extension View {
  /// Shows an alert while `error` has a value, and clears it on dismiss.
  func errorAlert(_ error: Binding<(any Error)?>) -> some View {
    alert(
      "Something went wrong",
      isPresented: Binding(
        get: { error.wrappedValue != nil },
        set: { if !$0 { error.wrappedValue = nil } }
      ),
      presenting: error.wrappedValue
    ) { _ in
      Button("OK", role: .cancel) {}
        .accessibilityIdentifier("error.ok")
    } message: { error in
      Text(errorMessage(for: error))
    }
  }
}

/// The text that the app shows for an error.
func errorMessage(for error: any Error) -> String {
  error.localizedDescription
}
