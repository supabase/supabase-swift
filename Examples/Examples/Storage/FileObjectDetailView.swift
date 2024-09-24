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
        AnyJSONView(value: try! AnyJSON(fileObject))
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

        Button("Get info") {
          Task {
            do {
              let info = try await api.info(path: fileObject.name)
              lastActionResult = ("info", info)
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
