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
  let root: PanelModel

  var panels: IdentifiedArrayOf<PanelModel> = [] {
    didSet {
      bindPanelModels()
    }
  }

  init(root: PanelModel) {
    self.root = root
    bindPanelModels()
  }

  var path: String {
    panels.last?.path ?? ""
  }

  var pathComponents: [String] {
    path.components(separatedBy: "/")
  }

  var selectedFile: FileObject? {
   nil// panels.last?.selectedItem
  }

  private func bindPanelModels() {
    for panel in [root] + panels {
      panel.onSelectItem = { [weak self, weak panel] item in
        guard let self, let panel else { return }

        self.panels.append(PanelModel(path: panel.path.appending("/\(item.name!)")))
      }
    }
  }
}

struct AppView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationStack(path: $model.panels) {
      PanelView(model: model.root)
        .navigationDestination(for: PanelModel.self) { model in
          PanelView(model: model)
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
//    .animation(.default, value: model.path)
//    .animation(.default, value: model.selectedFile)
  }
}

struct DragValue: Codable {
  let path: String
  let object: FileObject
}

@MainActor
@Observable
final class PanelModel: Identifiable, Hashable {
  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  nonisolated static func == (lhs: PanelModel, rhs: PanelModel) -> Bool {
    lhs === rhs
  }

  let path: String
  var selectedItem: FileObject.ID?

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

  func onPrimaryAction(_ itemID: FileObject.ID) {
    guard let item = items.first(where: { $0.id == itemID }) else { return }
    onSelectItem(item)
  }

//  func didSelectItem(_ item: FileObject) {
//    self.selectedItem = item
//    onSelectItem(item)
//  }

  func newFolderButtonTapped() async {
    do {
      try await supabase.storage.from("main")
        .upload(path: "\(path)/Untiltled/.dummy", file: Data())
      await load()
    } catch {

    }
  }

  func uploadFile(at url: URL) async {
    let path = url.lastPathComponent

    do {
      let file = try Data(contentsOf: url)
      try await supabase.storage.from("main")
        .upload(path: "\(self.path)/\(path)", file: file)
      await load()
    } catch {}
  }
}

struct PanelView: View {
  @Bindable var model: PanelModel

  @State private var isDraggingOver = false

  var body: some View {
    Table(model.items, selection: $model.selectedItem) {
      TableColumn("Name") { item in
        Text(item.name ?? "No name")
      }

      TableColumn("Date modified") { item in
        if let lastModifiedStringValue = item.metadata?["lastModified"]?.stringValue,
           let lastModified = try? Date(lastModifiedStringValue, strategy: .iso8601.day().month().year().dateTimeSeparator(.standard).time(includingFractionalSeconds: true))
        {
          Text(lastModified.formatted(date: .abbreviated, time: .shortened))
        } else {
          Text("-")
        }
      }

      TableColumn("Size") { item in
        if let sizeRawValue = item.metadata?["size"]?.intValue {
          Text(sizeRawValue.formatted(.byteCount(style: .file)))
        } else {
          Text("-")
        }
      }

      TableColumn("Metadata") { item in
        Text(
          {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try! encoder.encode(item.metadata ?? [:])
            return String(decoding: data, as: UTF8.self)
          }()
        )
      }
    }
    .contextMenu(
      forSelectionType: FileObject.ID.self,
      menu: { items in
        Button("New folder") {
          Task {
            await model.newFolderButtonTapped()
          }
        }
      },
      primaryAction: { items in
        guard let item = items.first else { return }

        model.onPrimaryAction(item)
      }
    )
//    .onInsert(of: ["public.text"]) { index, items in
//      for item in items {
//        Task {
//          guard let data = try await item.loadItem(forTypeIdentifier: "public.text") as? Data,
//                let value = try? JSONDecoder().decode(DragValue.self, from: data) else {
//            return
//          }
//
//          self.model.items.insert(value.object, at: index)
//        }
//      }
//      print(index, items)
//    }
    .navigationTitle(model.path)
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
  }
}
