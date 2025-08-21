//
//  BucketDetailView.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import Supabase
import SwiftUI

struct BucketDetailView: View {
  let bucket: Bucket

  @State private var fileObjects = ActionState<[FileObject], Error>.idle
  @State private var presentBucketDetails = false

  @State private var lastActionResult: (action: String, result: Any)?

  var body: some View {
    Group {
      switch fileObjects {
      case .idle:
        Color.clear
      case .inFlight:
        ProgressView()
      case let .result(.success(files)):
        List {
          Section("Actions") {
            NavigationLink("Upload Files") {
              StorageUploadView(bucket: bucket)
            }
            
            Button("createSignedUploadURL") {
              Task {
                do {
                  let response = try await supabase.storage.from(bucket.id)
                    .createSignedUploadURL(path: "\(UUID().uuidString).txt")
                  lastActionResult = ("createSignedUploadURL", response)
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

          Section("Objects") {
            ForEach(files) { file in
              NavigationLink(file.name, value: file)
            }
          }
        }
      case let .result(.failure(error)):
        VStack {
          ErrorText(error)
          Button("Retry") {
            Task { await load() }
          }
        }
      }
    }
    .task { await load() }
    .navigationTitle(bucket.name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          presentBucketDetails = true
        } label: {
          Label("Detail", systemImage: "info.circle")
        }
      }
    }
    .popover(isPresented: $presentBucketDetails) {
      List {
        AnyJSONView(rendering: bucket)
      }
    }
    .navigationDestination(for: FileObject.self) {
      FileObjectDetailView(api: supabase.storage.from(bucket.id), fileObject: $0)
    }
  }

  @MainActor
  private func load() async {
    fileObjects = .inFlight
    fileObjects = await .result(
      Result {
        try await supabase.storage.from(bucket.id).list()
      }
    )
  }
}

#Preview {
  BucketDetailView(
    bucket: Bucket(
      id: UUID().uuidString,
      name: "name",
      owner: "owner",
      isPublic: false,
      createdAt: Date(),
      updatedAt: Date(),
      allowedMimeTypes: nil,
      fileSizeLimit: nil
    )
  )
}
