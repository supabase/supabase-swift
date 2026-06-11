//
//  WebAuthnAuthenticator.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

import Foundation

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

/// Errors produced while driving a WebAuthn ceremony.
enum WebAuthnError: Error, Equatable {
  /// A required field was missing from the W3C credential options.
  case missingField(String)
  /// A field expected to be base64url-encoded could not be decoded.
  case invalidBase64URL(String)
  /// The authenticator returned a credential of an unexpected type.
  case unexpectedCredentialType
}

// MARK: - W3C options parsing (platform independent, testable)

extension AnyJSON {
  /// Base64url-decodes the `challenge` field of W3C credential options.
  func webAuthnChallengeData() throws -> Data {
    try base64URLDecoded(at: ["challenge"])
  }

  /// Base64url-decodes the `user.id` field of W3C creation options.
  func webAuthnUserID() throws -> Data {
    try base64URLDecoded(at: ["user", "id"])
  }

  /// Reads the `user.name` field of W3C creation options.
  func webAuthnUserName() throws -> String {
    guard let name = value(at: ["user", "name"])?.stringValue else {
      throw WebAuthnError.missingField("user.name")
    }
    return name
  }

  private func value(at path: [String]) -> AnyJSON? {
    var current: AnyJSON? = self
    for key in path {
      current = current?.objectValue?[key]
    }
    return current
  }

  private func base64URLDecoded(at path: [String]) throws -> Data {
    guard let string = value(at: path)?.stringValue else {
      throw WebAuthnError.missingField(path.joined(separator: "."))
    }
    guard let data = Base64URL.decode(string) else {
      throw WebAuthnError.invalidBase64URL(path.joined(separator: "."))
    }
    return data
  }
}

// MARK: - Platform authenticator

#if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
  /// Drives the platform passkey ceremony via `ASAuthorizationController`.
  ///
  /// This is an injectable seam: ``AuthClient`` and ``AuthMFA`` orchestrate the network exchange
  /// around it and can be tested by substituting a fake. The ``live`` implementation requires a
  /// real device, an Associated Domains entitlement (`webcredentials:<rpId>`), and a relying-party
  /// server hosting `.well-known/apple-app-site-association`, so it can only be exercised
  /// end-to-end on-device.
  @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
  struct WebAuthnAuthenticator: Sendable {
    /// Presents the registration UI for the given W3C creation options and returns the resulting
    /// W3C credential JSON.
    var register:
      @MainActor @Sendable (_ options: AnyJSON, _ rpId: String, _ anchor: ASPresentationAnchor)
        async throws -> AnyJSON

    /// Presents the assertion UI for the given W3C request options and returns the resulting W3C
    /// credential JSON.
    var authenticate:
      @MainActor @Sendable (_ options: AnyJSON, _ rpId: String, _ anchor: ASPresentationAnchor)
        async throws -> AnyJSON
  }

  @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
  extension WebAuthnAuthenticator {
    static let live = WebAuthnAuthenticator(
      register: { options, rpId, anchor in
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
          relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialRegistrationRequest(
          challenge: try options.webAuthnChallengeData(),
          name: try options.webAuthnUserName(),
          userID: try options.webAuthnUserID()
        )
        let authorization = try await WebAuthnCeremony(anchor: anchor).run(request: request)
        return try registrationCredentialJSON(from: authorization)
      },
      authenticate: { options, rpId, anchor in
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
          relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialAssertionRequest(
          challenge: try options.webAuthnChallengeData()
        )
        let authorization = try await WebAuthnCeremony(anchor: anchor).run(request: request)
        return try assertionCredentialJSON(from: authorization)
      }
    )
  }

  /// Serializes a platform registration credential into the W3C JSON shape the backend expects.
  @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
  private func registrationCredentialJSON(from authorization: ASAuthorization) throws -> AnyJSON {
    guard
      let credential = authorization.credential
        as? ASAuthorizationPlatformPublicKeyCredentialRegistration
    else {
      throw WebAuthnError.unexpectedCredentialType
    }
    return [
      "id": .string(Base64URL.encode(credential.credentialID)),
      "rawId": .string(Base64URL.encode(credential.credentialID)),
      "type": "public-key",
      "response": [
        "clientDataJSON": .string(Base64URL.encode(credential.rawClientDataJSON)),
        "attestationObject": .string(Base64URL.encode(credential.rawAttestationObject ?? Data())),
      ],
    ]
  }

  /// Serializes a platform assertion credential into the W3C JSON shape the backend expects.
  @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
  private func assertionCredentialJSON(from authorization: ASAuthorization) throws -> AnyJSON {
    guard
      let credential = authorization.credential
        as? ASAuthorizationPlatformPublicKeyCredentialAssertion
    else {
      throw WebAuthnError.unexpectedCredentialType
    }
    return [
      "id": .string(Base64URL.encode(credential.credentialID)),
      "rawId": .string(Base64URL.encode(credential.credentialID)),
      "type": "public-key",
      "response": [
        "clientDataJSON": .string(Base64URL.encode(credential.rawClientDataJSON)),
        "authenticatorData": .string(Base64URL.encode(credential.rawAuthenticatorData)),
        "signature": .string(Base64URL.encode(credential.signature)),
        "userHandle": .string(Base64URL.encode(credential.userID)),
      ],
    ]
  }

  /// Bridges `ASAuthorizationController`'s delegate callbacks to `async`/`await`.
  ///
  /// `ASAuthorizationController` keeps only a weak reference to its delegate and is itself not
  /// retained by the system, so the ceremony retains both itself and the controller until a
  /// callback fires.
  @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
  @MainActor
  private final class WebAuthnCeremony: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
  {
    private let anchor: ASPresentationAnchor
    private var continuation: CheckedContinuation<ASAuthorization, any Error>?
    private var controller: ASAuthorizationController?
    private var selfRetain: WebAuthnCeremony?

    init(anchor: ASPresentationAnchor) {
      self.anchor = anchor
    }

    func run(request: ASAuthorizationRequest) async throws -> ASAuthorization {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.selfRetain = self
        controller.performRequests()
      }
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
      finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
      anchor
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
      continuation?.resume(with: result)
      continuation = nil
      controller = nil
      selfRetain = nil
    }
  }
#endif
