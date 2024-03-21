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

  var body: some View {
    Group {
      switch fileObjects {
      case .idle:
        Color.clear
      case .inFlight:
        ProgressView()
      case let .result(.success(files)):
        List {
          ForEach(files) { file in
            NavigationLink(file.name, value: file)
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
    .navigationTitle("Objects")
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
      ScrollView {
        Text(stringfy(bucket))
          .monospaced()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
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
