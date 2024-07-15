//
//  AppView.swift
//  Examples
//
//  Created by Guilherme Souza on 02/07/24.
//

import CustomDump
import Supabase
import SwiftUI
import IdentifiedCollections

@MainActor
@Observable
final class AppModel {
  var panels: IdentifiedArrayOf<PanelModel> {
    didSet {
      bindPanelModels()
    }
  }

  init(panels: IdentifiedArrayOf<PanelModel>) {
    self.panels = panels
    bindPanelModels()
  }

  var path: String {
    panels.last?.path ?? ""
  }

  var pathComponents: [String] {
    path.components(separatedBy: "/")
  }

  var selectedFile: FileObject? {
    panels.last?.selectedItem
  }

  private func bindPanelModels() {
    for panel in panels {
      panel.onSelectItem = { [weak self, weak panel] item in
        guard let self, let panel else { return }

//        self.panels.append(PanelModel(path: self.path.appending))
//
//        if let name = item.name, item.id == nil {
//          self.panels.replaceSubrange(
//            (index + 1)...,
//            with: [PanelModel(path: self.path.appending("/\(name)"))]
//          )
//        }
      }
    }
  }
}

struct AppView: View {
  @Bindable var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      breadcrump

      ScrollView(.horizontal) {
        HStack {
          ForEach(model.panels) { panel in
            PanelView(
              model: panel
//              model: PanelModel(path: path[0 ... pathIndex].joined(separator: "/"))
//              path: path[0 ... pathIndex].joined(separator: "/"),
//              selectedItem: Binding(
//                get: {
//                  selectedItemPerPath[path[pathIndex]]
//                },
//                set: { newValue in
//                  selectedItemPerPath[path[pathIndex]] = newValue
//
//                  if let newValue, let name = newValue.name, newValue.id == nil {
//                    path.replaceSubrange((pathIndex + 1)..., with: [name])
//                  } else {
//                    path.replaceSubrange((pathIndex + 1)..., with: [])
//                  }
//                }
//              )
            )
            .frame(width: 200)
          }
        }
      }
    }
    .overlay(alignment: .trailing) {
      if let selectedFile = model.selectedFile {
        Form {
          Text(selectedFile.name ?? "")
            .font(.title2)
          Divider()

          if let contentLenth = selectedFile.metadata?["contentLength"]?.intValue {
            LabeledContent("Size", value: "\(contentLenth)")
          }

          if let mimeType = selectedFile.metadata?["mimetype"]?.stringValue {
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
    .animation(.default, value: model.path)
    .animation(.default, value: model.selectedFile)
  }

  var breadcrump: some View {
    HStack {
      ForEach(Array(zip(model.pathComponents.indices, model.pathComponents)), id: \.0) { idx, path in
        Button(path) {
//          self.path.replaceSubrange((idx + 1)..., with: [])
        }
        .buttonStyle(.plain)

//        if idx != self.path.indices.last {
//          Text(">")
//        }
      }
    }
    .padding()
  }
}

struct DragValue: Codable {
  let path: String
  let object: FileObject
}

@MainActor
@Observable
final class PanelModel: Identifiable {
  let path: String
  var selectedItem: FileObject?

  var items: [FileObject] = []

  @ObservationIgnored
  var onSelectItem: @MainActor (FileObject) -> Void = { _ in }

  init(path: String) {
    self.path = path
  }

  func load() async {
    do {
      let files = try await supabase.storage.from("main").list(path: path)
      items = files.filter { $0.name?.hasPrefix(".") == false }
    } catch {
      dump(error)
    }
  }

  func didSelectItem(_ item: FileObject) {
    self.selectedItem = item
    onSelectItem(item)
  }

  func newFolderButtonTapped() async {
    do {
      try await supabase.storage.from("main")
        .upload(path: "\(path)/Untiltled/.dummy", file: Data())
    } catch {

    }
  }

  func uploadFile(at url: URL) async {
    let path = url.lastPathComponent

    do {
      let file = try Data(contentsOf: url)
      try await supabase.storage.from("main")
        .upload(path: "\(self.path)/\(path)", file: file)
    } catch {}
  }
}

struct PanelView: View {
  @Bindable var model: PanelModel

  @State private var isDraggingOver = false

  var body: some View {
    List {
      ForEach(model.items) { item in
        Text(item.name ?? "")
          .bold(model.selectedItem == item)
          .onTapGesture {
            model.didSelectItem(item)
          }
          .onDrag {
            let data = try! JSONEncoder().encode(DragValue(path: model.path, object: item))
            let string = String(decoding: data, as: UTF8.self)
            return NSItemProvider(object: string as NSString)
          }
      }
      .onInsert(of: ["public.text"]) { index, items in
        for item in items {
          Task {
            guard let data = try await item.loadItem(forTypeIdentifier: "public.text") as? Data,
                  let value = try? JSONDecoder().decode(DragValue.self, from: data) else {
              return
            }

            self.model.items.insert(value.object, at: index)
          }
        }
        print(index, items)
      }
    }
    .task {
      await model.load()
    }
    .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
      for provider in providers {
        _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
          guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
            return
          }

          Task {
            await model.uploadFile(at: url)
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
          await model.newFolderButtonTapped()
        }
      }
    }
  }
}

#Preview {
  AppView(model: AppModel(panels: []))
}
