//
//  FileObjectDetailView.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import Supabase
import SwiftUI

struct FileObjectDetailView: View {
  let api: StorageFileApi
  let fileObject: FileObject

  @Environment(\.openURL) var openURL
  @State var lastActionResult: (action: String, result: Any)?

  var body: some View {
    List {
      Section {
        DisclosureGroup("Raw details") {
          Text(stringfy(fileObject))
            .monospaced()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      Section("Actions") {
        Button("createSignedURL") {
          Task {
            do {
              let url = try await api.createSignedURL(path: fileObject.name, expiresIn: 60)
              lastActionResult = ("createSignedURL", url)
              openURL(url)
            } catch {}
          }
        }

        Button("createSignedURL (download)") {
          Task {
            do {
              let url = try await api.createSignedURL(
                path: fileObject.name,
                expiresIn: 60,
                download: true
              )
              lastActionResult = ("createSignedURL (download)", url)
              openURL(url)
            } catch {}
          }
        }
      }

      if let lastActionResult {
        Section("Last action result") {
          Text(lastActionResult.action)
          Text(stringfy(lastActionResult.result))
        }
      }
    }
    .navigationTitle(fileObject.name)
  }
}
