//
//  ActionState.swift
//  Examples
//
//  Created by Guilherme Souza on 15/12/23.
//

import CasePaths
import Foundation
import SwiftUI

@CasePathable
enum ActionState<Success, Failure: Error> {
  case idle
  case inFlight
  case result(Result<Success, Failure>)

  var success: Success? {
    if case let .result(.success(success)) = self { return success }
    return nil
  }

  var isInFlight: Bool {
    if case .inFlight = self { return true }
    return false
  }
}

struct ActionStateView<Success: Sendable, SuccessContent: View>: View {
  @Binding var state: ActionState<Success, any Error>

  let action: () async throws -> Success
  @ViewBuilder var content: (Success) -> SuccessContent

  var body: some View {
    Group {
      switch state {
      case .idle:
        Color.clear
      case .inFlight:
        ProgressView()
      case let .result(.success(value)):
        content(value)
      case let .result(.failure(error)):
        VStack {
          ErrorText(error)
          Button("Retry") {
            Task { await load() }
          }
        }
      }
    }
    .task {
      await load()
    }
  }

  @MainActor
  private func load() async {
    state = .inFlight
    do {
      let value = try await action()
      state = .result(.success(value))
    } catch {
      state = .result(.failure(error))
    }
  }
}
