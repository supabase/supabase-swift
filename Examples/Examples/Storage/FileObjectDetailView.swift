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
        JSONValueView(
          value: .object([
            "name": .string(fileObject.name),
            "bucketId": fileObject.bucketId.map(JSONValue.string) ?? .null,
            "owner": fileObject.owner.map(JSONValue.string) ?? .null,
            "id": fileObject.id.map { .string($0.uuidString) } ?? .null,
            "updatedAt": fileObject.updatedAt.map { .string($0.description) } ?? .null,
            "createdAt": fileObject.createdAt.map { .string($0.description) } ?? .null,
            "lastAccessedAt": fileObject.lastAccessedAt.map { .string($0.description) } ?? .null,
            "metadata": fileObject.metadata.map(JSONValue.object) ?? .null,
            "buckets": fileObject.buckets.map { .string($0.name) } ?? .null,
          ])
        )
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
