//
//  MFAFlow.swift
//  Examples
//
//  Created by Guilherme Souza on 27/10/23.
//

import SVGView
import Supabase
import SwiftUI

enum MFAStatus {
  case unenrolled
  case unverified
  case verified
  case disabled

  var description: String {
    switch self {
    case .unenrolled:
      "User does not have MFA enrolled."
    case .unverified:
      "User has an MFA factor enrolled but has not verified it."
    case .verified:
      "User has verified their MFA factor."
    case .disabled:
      "User has disabled their MFA factor. (Stale JWT.)"
    }
  }
}

struct MFAFlow: View {
  let status: MFAStatus

  var body: some View {
    NavigationStack {
      switch status {
      case .unenrolled:
        MFAEnrollView()
      case .unverified:
        MFAVerifyView()
      case .verified:
        MFAVerifiedView()
      case .disabled:
        MFADisabledView()
      }
    }
  }
}

struct MFAEnrollView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var verificationCode = ""

  @State private var enrollResponse: AuthMFAEnrollResponse?
  @State private var error: Error?

  var body: some View {
    Form {
      if let totp = enrollResponse?.totp {
        Section {
          SVGView(string: totp.qrCode)
          LabeledContent("Secret", value: totp.secret)
          LabeledContent("URI", value: totp.uri)
        }
      }

      Section("Verification code") {
        TextField("Code", text: $verificationCode)
      }

      if let error {
        Section {
          Text(error.localizedDescription).foregroundStyle(.red)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
      }

      ToolbarItem(placement: .primaryAction) {
        Button("Enable") {
          enableButtonTapped()
        }
        .disabled(verificationCode.isEmpty)
      }
    }
    .task {
      do {
        error = nil
        enrollResponse = try await supabase.auth.mfa.enroll(params: MFAEnrollParams())
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  private func enableButtonTapped() {
    Task {
      do {
        try await supabase.auth.mfa.challengeAndVerify(
          params: MFAChallengeAndVerifyParams(factorId: enrollResponse!.id, code: verificationCode))
      } catch {
        self.error = error
      }
    }
  }
}

struct MFAVerifyView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var verificationCode = ""
  @State private var error: Error?

  var body: some View {
    Form {
      Section {
        TextField("Code", text: $verificationCode)
      }

      if let error {
        Section {
          Text(error.localizedDescription).foregroundStyle(.red)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
      }

      ToolbarItem(placement: .primaryAction) {
        Button("Verify") {
          verifyButtonTapped()
        }
        .disabled(verificationCode.isEmpty)
      }
    }
  }

  @MainActor
  private func verifyButtonTapped() {
    Task {
      do {
        error = nil

        let factors = try await supabase.auth.mfa.listFactors()
        guard let totpFactor = factors.totp.first else {
          debugPrint("No TOTP factor found.")
          return
        }

        try await supabase.auth.mfa.challengeAndVerify(
          params: MFAChallengeAndVerifyParams(factorId: totpFactor.id, code: verificationCode))
      } catch {
        self.error = error
      }
    }
  }
}

struct MFAVerifiedView: View {
  var factors: [Factor] {
    []
  }

  var body: some View {
    List {
      ForEach(factors) { factor in
        VStack {
          LabeledContent("ID", value: factor.id)
          LabeledContent("Type", value: factor.factorType)
          LabeledContent("Friendly name", value: factor.friendlyName ?? "-")
          LabeledContent("Status", value: factor.status.rawValue)
        }
      }
      .onDelete { indexSet in
        Task {
          do {
            let factorsToRemove = indexSet.map { factors[$0] }
            for factor in factorsToRemove {
              try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))
            }
          } catch {

          }
        }
      }
    }
    .navigationTitle("Factors")
  }
}

struct MFADisabledView: View {
  var body: some View {
    Text(MFAStatus.disabled.description)
  }
}
