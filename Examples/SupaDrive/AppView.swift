//
//  AppView.swift
//  Examples
//
//  Created by Guilherme Souza on 02/07/24.
//

import Supabase
import SwiftUI

enum Item: Identifiable, Hashable {
  case folder(Folder)
  case file(File)

  var id: String {
    switch self {
    case let .file(file): file.id
    case let .folder(folder): folder.id
    }
  }

  var name: String {
    switch self {
    case let .file(file): file.name
    case let .folder(folder): folder.name
    }
  }

  var isFolder: Bool {
    if case .folder = self { return true }
    return false
  }

  var isFile: Bool {
    if case .file = self { return true }
    return false
  }
}

struct Folder: Identifiable, Hashable {
  let id: String
  let name: String
  let items: [Item]
}

struct File: Identifiable, Hashable {
  let id: String
  let name: String
}

struct AppView: View {
  @State var path: [String]
  @State var selectedItemPerPath: [String: Item] = [:]

  @State var reload = UUID()

  var body: some View {
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

                if case let .folder(folder) = newValue {
                  path.replaceSubrange((pathIndex + 1)..., with: [folder.name])
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
    .overlay(alignment: .trailing) {
      if
        let lastPath = path.last,
        let selectedItem = selectedItemPerPath[lastPath],
        case let .file(file) = selectedItem
      {
        ScrollView {
          VStack {
            Text(file.name)
          }
          .frame(width: 200)
          .padding()
        }
        .background(Color.secondary)
      }
    }
  }
}

struct PanelView: View {
  var path: String
  @Binding var selectedItem: Item?

  @State private var isDraggingOver = false
  @State private var items: [Item] = []

  @State private var reload = UUID()

  var body: some View {
    List {
      Section(path) {
        ForEach(items) { item in
          Button {
            selectedItem = item
          } label: {
            Text(item.name)
              .background(selectedItem == item ? Color.blue : Color.clear)
          }
        }
      }
      .buttonStyle(.plain)
    }
    .task(id: reload) {
      do {
        let files = try await supabase.storage.from("main").list(path: path)

        items = files.map(Item.init)
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

          Task {
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
  }
}

extension Item {
  init(file: FileObject) {
    if file.id == nil {
      self = .folder(Folder(id: file.name, name: file.name, items: []))
    } else {
      self = .file(File(id: file.id!, name: file.name))
    }
  }
}

#Preview {
  AppView(path: [])
}
