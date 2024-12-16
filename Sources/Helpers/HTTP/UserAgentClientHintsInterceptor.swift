//
//  UserAgentClientHintsInterceptor.swift
//  Supabase
//
//  Created by Guilherme Souza on 16/12/24.
//

import Foundation
import HTTPTypes

#if canImport(UIKit)
  import UIKit
#endif

struct UserAgentClientHintsInterceptor: HTTPClientInterceptor {

  func intercept(
    _ request: HTTPRequest,
    next: (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse {
    var request = request

    request.headers[.secCHUAPlatform] = await getPlatformName()
    request.headers[.secCHUAPlatformVersion] = getPlatformVersion()
    request.headers[.secCHUAModel] = await getModel()

    return try await next(request)
  }

  @MainActor
  private func getPlatformName() -> String? {
    #if os(iOS)
      if UIDevice.current.userInterfaceIdiom == .pad {
        return "iPadOS"
      } else {
        return "iOS"
      }
    #elseif os(macOS)
      return "macOS"
    #elseif os(watchOS)
      return "watchOS"
    #elseif os(tvOS)
      return "tvOS"
    #elseif os(Linux)
      return "Linux"
    #elseif os(Windows)
      return "Windows"
    #else
      return nil
    #endif
  }

  private func getPlatformVersion() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }

  @MainActor private func getModel() -> String? {
    #if os(iOS) || os(tvOS)
    return UIDevice.current.model
    #elseif os(macOS)
      return "Mac"
    #elseif os(Windows)
      return "Windows-Device"
    #elseif os(Linux)
      return "Linux-Device"
    #else
      return nil
    #endif
  }
}

extension HTTPField.Name {
  static let secCHUAPlatform: HTTPField.Name = .init("Sec-CH-UA-Platform")!
  static let secCHUAPlatformVersion: HTTPField.Name = .init("Sec-CH-UA-Platform-Version")!
  static let secCHUAModel: HTTPField.Name = .init("Sec-CH-UA-Model")!
}
