//
//  FileObjectDetailView.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import Supabase
import SwiftUI

struct FileObjectDetailView: View {
  let api: StorageBucket
  let fileObject: StorageObject

  @Environment(\.openURL) var openURL
  @State var lastActionResult: (action: String, result: Any)?

  var body: some View {
    List {
      Section {
        JSONValueView(
          value: .object([
            "name": .string(fileObject.name),
            "id": fileObject.id.map { .string($0.uuidString) } ?? .null,
            "updatedAt": fileObject.updatedAt.map { .string($0.description) } ?? .null,
            "createdAt": fileObject.createdAt.map { .string($0.description) } ?? .null,
            "lastAccessedAt": fileObject.lastAccessedAt.map { .string($0.description) } ?? .null,
            "version": fileObject.version.map(JSONValue.string) ?? .null,
            "size": fileObject.metadata?.size.map { .string(String($0)) } ?? .null,
            "mimeType": fileObject.metadata?.mimeType.map(JSONValue.string) ?? .null,
            "eTag": fileObject.metadata?.eTag.map(JSONValue.string) ?? .null,
            "userMetadata": fileObject.userMetadata.map(JSONValue.object) ?? .null,
          ])
        )
      }

      Section("Actions") {
        Button("createSignedURL") {
          Task {
            do {
              let url = try await api.createSignedURL(
                path: fileObject.name, expiresIn: .seconds(60))
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
                expiresIn: .seconds(60),
                download: .withOriginalName
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
          Text(stringify(lastActionResult.result))
        }
      }
    }
    .navigationTitle(fileObject.name)
  }
}
