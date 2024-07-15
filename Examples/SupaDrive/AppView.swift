//
//  AppView.swift
//  Examples
//
//  Created by Guilherme Souza on 02/07/24.
//

import CustomDump
import Supabase
import SwiftUI

struct AppView: View {
  @State var path: [String]
  @State var selectedItemPerPath: [String: FileObject] = [:]

  @State var reload = UUID()

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      breadcrump

      ScrollView(.horizontal) {
        HStack {
          ForEach(path.indices, id: \.self) { pathIndex in
            PanelView(
              path: path[0 ... pathIndex].joined(separator: "/"),
              selectedItem: Binding(
                get: {
                  selectedItemPerPath[path[pathIndex]]
                },
                set: { newValue in
                  selectedItemPerPath[path[pathIndex]] = newValue

                  if let newValue, let name = newValue.name, newValue.id == nil {
                    path.replaceSubrange((pathIndex + 1)..., with: [name])
                  } else {
                    path.replaceSubrange((pathIndex + 1)..., with: [])
                  }
                }
              )
            )
            .frame(width: 200)
          }
        }
      }
    }
    .overlay(alignment: .trailing) {
      if
        let lastPath = path.last,
        let selectedItem = selectedItemPerPath[lastPath],
        selectedItem.id != nil
      {
        Form {
          Text(selectedItem.name ?? "")
            .font(.title2)
          Divider()

          if let contentLenth = selectedItem.metadata?["contentLength"]?.intValue {
            LabeledContent("Size", value: "\(contentLenth)")
          }

          if let mimeType = selectedItem.metadata?["mimetype"]?.stringValue {
            LabeledContent("MIME Type", value: mimeType)
          }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .transition(.move(edge: .trailing))
      }
    }
    .animation(.default, value: path)
    .animation(.default, value: selectedItemPerPath)
  }

  var breadcrump: some View {
    HStack {
      ForEach(Array(zip(path.indices, path)), id: \.0) { idx, path in
        Button(path) {
          self.path.replaceSubrange((idx + 1)..., with: [])
        }
        .buttonStyle(.plain)

        if idx != self.path.indices.last {
          Text(">")
        }
      }
    }
    .padding()
  }
}

struct PanelView: View {
  var path: String
  @Binding var selectedItem: FileObject?

  @State private var isDraggingOver = false
  @State private var items: [FileObject] = []

  @State private var reload = UUID()

  var body: some View {
    List {
      ForEach(items) { item in
        Button {
          selectedItem = item
        } label: {
          Text(item.name ?? "")
            .bold(selectedItem == item)
        }
      }
      .buttonStyle(.plain)
    }
    .task(id: reload) {
      do {
        let files = try await supabase.storage.from("main").list(path: path)

        items = files.filter { $0.name?.hasPrefix(".") == false }
      } catch {
        dump(error)
      }
    }
    .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
      for provider in providers {
        _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
          guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
            return
          }

          Task { @MainActor in
            let path = url.lastPathComponent
            let file = try! Data(contentsOf: url)
            try! await supabase.storage.from("main")
              .upload(path: "\(self.path)/\(path)", file: file)

            reload = UUID()
          }
        }
      }
      return true
    }
    .overlay {
      if isDraggingOver {
        Color.gray.opacity(0.2)
      }
    }
    .contextMenu {
      Button("New folder") {
        Task {
          try! await supabase.storage.from("main")
            .upload(path: "\(path)/Untiltled/.dummy", file: Data())
          reload = UUID()
        }
      }
    }
  }
}

extension FileObject {
  var metadataDump: String {
    var output = ""
    customDump(metadata, to: &output)
    return output
  }
}

#Preview {
  AppView(path: [])
}
