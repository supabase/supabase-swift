//
//  Toast.swift
//  SlackClone
//
//  Created by Guilherme Souza on 27/12/23.
//

import SwiftUI

struct ToastState: Identifiable {
  let id = UUID()

  enum Status {
    case error
    case success
  }

  var status: Status
  var title: String
  var description: String?
}

struct Toast: View {
  let state: ToastState

  var body: some View {
    VStack(alignment: .leading) {
      Text(state.title)
        .font(.headline)
      state.description.map { Text($0) }
    }
    .padding()
    .background(backgroundColor.opacity(0.8))
    .foregroundStyle(.white)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  var backgroundColor: Color {
    switch state.status {
    case .error:
      .red
    case .success:
      .green
    }
  }
}

@MainActor
struct ToastModifier: ViewModifier {
  let state: Binding<ToastState?>

  @State private var dismissTask: Task<Void, Never>?

  func body(content: Content) -> some View {
    content
      .frame(maxHeight: .infinity)
      .overlay(alignment: .bottom) {
        VStack {
          if let state = state.wrappedValue {
            Toast(state: state)
              .transition(.move(edge: .bottom))
          }
        }
        .animation(.snappy, value: state.wrappedValue?.id)
      }
      .onChange(of: state.wrappedValue?.id) { old, new in
        if old == nil, new != nil {
          scheduleDismiss()
        }
      }
      .onDisappear { dismissTask?.cancel() }
  }

  private func scheduleDismiss() {
    dismissTask?.cancel()
    dismissTask = Task {
      try? await Task.sleep(for: .seconds(2))
      if Task.isCancelled { return }
      state.wrappedValue = nil
    }
  }
}

extension View {
  func toast(state: Binding<ToastState?>) -> some View {
    modifier(ToastModifier(state: state))
  }
}

#Preview {
  Toast(
    state: ToastState(status: .success, title: "Error", description: "Custom error description")
  )
}
