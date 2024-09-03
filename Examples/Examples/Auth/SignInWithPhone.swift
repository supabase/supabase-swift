//
//  SignInWithPhone.swift
//  Examples
//
//  Created by Guilherme Souza on 03/09/24.
//

import SwiftUI

struct SignInWithPhone: View {
  @State var phone = ""
  @State var code = ""

  @State var actionState: ActionState<Void, Error> = .idle
  @State var verifyActionState: ActionState<Void, Error> = .idle

  @State var isVerifyStep = false

  var body: some View {
    if isVerifyStep {
      VStack {
        verifyView
        Button("Change phone") {
          isVerifyStep = false
        }
      }
    } else {
      phoneView
    }
  }

  var phoneView: some View {
    Form {
      Section {
        TextField("Phone", text: $phone)
          .keyboardType(.phonePad)
          .textContentType(.telephoneNumber)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
      }

      Section {
        Button("Send code to number") {
          Task {
            await sendCodeToNumberTapped()
          }
        }
      }

      switch actionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case let .result(.failure(error)):
        ErrorText(error)
      }
    }
  }

  var verifyView: some View {
    Form {
      Section {
        TextField("Code", text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
      }

      Section {
        Button("Verify") {
          Task {
            await verifyButtonTapped()
          }
        }
      }

      switch verifyActionState {
      case .idle, .result(.success):
        EmptyView()
      case .inFlight:
        ProgressView()
      case let .result(.failure(error)):
        ErrorText(error)
      }
    }
  }

  private func sendCodeToNumberTapped() async {
    actionState = .inFlight

    do {
      try await supabase.auth.signInWithOTP(phone: phone)
      actionState = .result(.success(()))
      isVerifyStep = true
    } catch {
      actionState = .result(.failure(error))
    }
  }

  private func verifyButtonTapped() async {
    verifyActionState = .inFlight
    do {
      try await supabase.auth.verifyOTP(phone: phone, token: code, type: .sms)
      verifyActionState = .result(.success(()))
    } catch {
      verifyActionState = .result(.failure(error))
    }
  }
}

#Preview {
  SignInWithPhone()
}
