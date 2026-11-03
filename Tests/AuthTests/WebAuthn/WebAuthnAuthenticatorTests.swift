//
//  WebAuthnAuthenticatorTests.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

#if canImport(AuthenticationServices) && !os(watchOS)
  import AuthenticationServices
  import Foundation
  import Testing

  @_spi(Experimental) @testable import Auth

  @Suite
  struct WebAuthnAuthenticatorTests {
    @Test
    func canceledCeremonyBecomesCancellationError() {
      let error = WebAuthnAuthenticator.ceremonyError(from: ASAuthorizationError(.canceled))

      #expect(error is CancellationError)
    }

    @Test
    func failedCeremonyBecomesPasskeyCeremonyFailed() throws {
      let underlying = ASAuthorizationError(.failed)

      let error = try #require(
        WebAuthnAuthenticator.ceremonyError(from: underlying) as? AuthError)

      #expect(error.kind == .passkeyCeremonyFailed)
      #expect(error.errorCode == .unknown)
      #expect((error.underlyingError as? ASAuthorizationError)?.code == .failed)
    }

    #if !os(tvOS)
      @Test
      func matchedExcludedCredentialCarriesCredentialExistsCode() throws {
        guard #available(iOS 18, macOS 15, visionOS 2, *) else { return }

        let error = try #require(
          WebAuthnAuthenticator.ceremonyError(
            from: ASAuthorizationError(.matchedExcludedCredential)) as? AuthError)

        #expect(error.kind == .passkeyCeremonyFailed)
        #expect(error.errorCode == .webAuthnCredentialExists)
      }
    #endif

    @Test
    func otherErrorsPassThrough() {
      let error = WebAuthnAuthenticator.ceremonyError(from: URLError(.notConnectedToInternet))

      #expect((error as? URLError)?.code == .notConnectedToInternet)
    }

    @Test
    @MainActor
    func defaultPresentationAnchorResolvesAWindow() {
      #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let anchor = AuthPlatform.defaultPresentationAnchor()
        #expect(anchor === window)
      #else
        let anchor = AuthPlatform.defaultPresentationAnchor()
        #expect(anchor.isKind(of: UIWindow.self))
      #endif
    }
  }
#endif
