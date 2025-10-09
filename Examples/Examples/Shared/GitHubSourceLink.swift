//
//  GitHubSourceLink.swift
//  Examples
//
//  Helper for generating GitHub source code links
//

import Foundation
import SwiftUI

struct GitHubSourceLink {
  static let baseURL = URL(
    string: "https://github.com/supabase/supabase-swift/blob/main"
  )!

  static func url(for file: String = #file) -> URL {
    let paths = file.split(separator: "/")

    guard let rootIndex = paths.firstIndex(where: { $0 == "Examples" }) else {
      return baseURL
    }

    let relativePath = paths[rootIndex...].joined(separator: "/")
    return baseURL.appendingPathComponent(relativePath)
  }
}

struct GitHubSourceLinkViewModifier: ViewModifier {
  @Environment(\.openURL) var openURL

  let file: String

  func body(content: Content) -> some View {
    content
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            openURL(GitHubSourceLink.url(for: file))
          } label: {
            Label("View Source", systemImage: "chevron.left.forwardslash.chevron.right")
          }
        }
      }
  }
}

extension View {
  func gitHubSourceLink(for file: String = #file) -> some View {
    modifier(GitHubSourceLinkViewModifier(file: file))
  }
}
