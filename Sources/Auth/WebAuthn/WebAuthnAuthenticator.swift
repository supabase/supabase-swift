//
//  WebAuthnAuthenticator.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

#if canImport(AuthenticationServices) && !os(watchOS)
  import AuthenticationServices
  import Foundation

  /// Drives the platform passkey ceremony via `ASAuthorizationController`.
  ///
  /// This is an injectable seam: ``AuthPasskeys`` and ``AuthMFA`` orchestrate the network exchange
  /// around it and can be tested by substituting a fake. The ``live`` implementation requires a
  /// real device, an Associated Domains entitlement (`webcredentials:<rpId>`), and a relying-party
  /// server hosting `.well-known/apple-app-site-association`, so it can only be exercised
  /// end-to-end on-device.
  struct WebAuthnAuthenticator: Sendable {
    /// Presents the registration UI and returns the resulting W3C credential JSON. A `nil` anchor
    /// means ``AuthPlatform/defaultPresentationAnchor()``.
    var register:
      @MainActor @Sendable (_ options: WebAuthnCreationOptions, _ anchor: ASPresentationAnchor?)
        async throws -> JSONValue

    /// Presents the assertion UI and returns the resulting W3C credential JSON. A `nil` anchor
    /// means ``AuthPlatform/defaultPresentationAnchor()``.
    var authenticate:
      @MainActor @Sendable (_ options: WebAuthnRequestOptions, _ anchor: ASPresentationAnchor?)
        async throws -> JSONValue
  }

  extension WebAuthnAuthenticator {
    static let live = WebAuthnAuthenticator(
      register: { options, anchor in
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
          relyingPartyIdentifier: options.rpID
        )
        let request = provider.createCredentialRegistrationRequest(
          challenge: options.challenge,
          name: options.userName,
          userID: options.userID
        )
        #if !os(tvOS) && !os(visionOS)
          if #available(iOS 17.4, macOS 13.5, *) {
            request.excludedCredentials = options.excludedCredentialIDs.map {
              ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
          }
        #endif
        let credential: ASAuthorizationPlatformPublicKeyCredentialRegistration =
          try await WebAuthnCeremony(anchor: anchor).run(request: request)
        return try WebAuthnCredentialJSON.registration(
          credentialID: credential.credentialID,
          clientDataJSON: credential.rawClientDataJSON,
          attestationObject: credential.rawAttestationObject
        )
      },
      authenticate: { options, anchor in
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
          relyingPartyIdentifier: options.rpID
        )
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        request.allowedCredentials = options.allowedCredentialIDs.map {
          ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        let credential: ASAuthorizationPlatformPublicKeyCredentialAssertion =
          try await WebAuthnCeremony(anchor: anchor).run(request: request)
        return WebAuthnCredentialJSON.assertion(
          credentialID: credential.credentialID,
          clientDataJSON: credential.rawClientDataJSON,
          authenticatorData: credential.rawAuthenticatorData,
          signature: credential.signature,
          userID: credential.userID
        )
      }
    )

    /// Maps an `ASAuthorizationController` failure onto the error the ceremony throws: a user
    /// cancel becomes `CancellationError`, as OAuth does, and any other `ASAuthorizationError`
    /// becomes ``AuthError/Kind-swift.struct/passkeyCeremonyFailed``.
    static func ceremonyError(from error: any Error) -> any Error {
      guard let error = error as? ASAuthorizationError else { return error }
      if error.code == .canceled { return CancellationError() }

      var errorCode = ErrorCode.unknown
      #if !os(tvOS)
        if #available(iOS 18, macOS 15, visionOS 2, *), error.code == .matchedExcludedCredential {
          errorCode = .webAuthnCredentialExists
        }
      #endif
      return AuthError.passkeyCeremonyFailed(error, errorCode: errorCode)
    }
  }

  /// Bridges `ASAuthorizationController`'s delegate callbacks to `async`/`await`.
  ///
  /// `ASAuthorizationController` keeps only a weak reference to its delegate and is itself not
  /// retained by the system, so the ceremony retains both itself and the controller until a
  /// callback fires.
  @MainActor
  private final class WebAuthnCeremony: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
  {
    private let anchor: ASPresentationAnchor?
    private var continuation: CheckedContinuation<ASAuthorization, any Error>?
    private var controller: ASAuthorizationController?
    private var selfRetain: WebAuthnCeremony?

    init(anchor: ASPresentationAnchor?) {
      self.anchor = anchor
    }

    func run<Credential>(request: ASAuthorizationRequest) async throws -> Credential {
      let authorization = try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.selfRetain = self
        controller.performRequests()
      }
      guard let credential = authorization.credential as? Credential else {
        throw AuthError.decoding("The authenticator returned an unexpected credential type.")
      }
      return credential
    }

    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithAuthorization authorization: ASAuthorization
    ) {
      finish(.success(authorization))
    }

    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithError error: any Error
    ) {
      finish(.failure(WebAuthnAuthenticator.ceremonyError(from: error)))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
      anchor ?? AuthPlatform.defaultPresentationAnchor()
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
      continuation?.resume(with: result)
      continuation = nil
      controller = nil
      selfRetain = nil
    }
  }
#endif
