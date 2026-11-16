import PhotosUI
import SwiftUI

/// The images of a reminder. An image uploads as soon as the user picks it. It does not
/// wait for the Done button of the sheet.
struct AttachmentsSection: View {
  @Environment(DataStore.self) private var store

  let reminderID: UUID

  @State private var pickedItem: PhotosPickerItem?
  @State private var isUploading = false
  @State private var viewedAttachment: Attachment?
  @State private var errorText: String?

  var body: some View {
    let attachments = store.attachments(of: reminderID)
    // The label closure of `PhotosPicker` is not on the main actor.
    let isUploading = isUploading

    Section {
      if !attachments.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
              Button {
                viewedAttachment = attachment
              } label: {
                AttachmentImage(attachment: attachment)
                  .frame(width: 72, height: 72)
                  .clipShape(RoundedRectangle(cornerRadius: 10))
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Image \(index + 1)")
              .accessibilityIdentifier("attachment.\(index)")
            }
          }
        }
        .scrollIndicators(.hidden)
      }

      PhotosPicker(selection: $pickedItem, matching: .images) {
        HStack {
          Label("Add Image", systemImage: "photo.badge.plus")
          if isUploading {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(isUploading)
      .accessibilityIdentifier("reminderDetail.addImage")
      // These modifiers are on one row. On the `Section`, SwiftUI applies them to each
      // row, and two covers that open at the same time close the sheet.
      .onChange(of: pickedItem) { _, item in
        if let item { upload(item) }
      }
      .fullScreenCover(item: $viewedAttachment) { attachment in
        AttachmentViewer(attachment: attachment)
      }
    } header: {
      Text("Images")
    } footer: {
      if let errorText {
        Text(errorText)
          .foregroundStyle(.red)
          .accessibilityIdentifier("attachment.error")
      }
    }
  }

  private func upload(_ item: PhotosPickerItem) {
    isUploading = true
    errorText = nil
    Task {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw UnreadableImage()
        }
        try await store.addAttachment(imageData: data, reminderID: reminderID)
      } catch {
        errorText = errorMessage(for: error)
      }
      pickedItem = nil
      isUploading = false
    }
  }
}

/// Downloads and shows the image of one attachment.
private struct AttachmentImage: View {
  @Environment(DataStore.self) private var store

  let attachment: Attachment
  var contentMode: ContentMode = .fill

  @State private var image: UIImage?
  @State private var didFail = false

  var body: some View {
    ZStack {
      Color(.secondarySystemFill)
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else if didFail {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
      }
    }
    .task(id: attachment.id) {
      do {
        image = try await store.image(for: attachment)
      } catch {
        didFail = true
      }
    }
  }
}

/// One image on the full screen, with a delete button.
private struct AttachmentViewer: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let attachment: Attachment

  @State private var isDeleting = false
  @State private var error: (any Error)?

  var body: some View {
    NavigationStack {
      AttachmentImage(attachment: attachment, contentMode: .fit)
        .ignoresSafeArea(edges: .bottom)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
              .accessibilityIdentifier("attachment.close")
          }
          ToolbarItem(placement: .destructiveAction) {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
              .disabled(isDeleting)
              .accessibilityIdentifier("attachment.delete")
          }
        }
        .errorAlert($error)
    }
  }

  private func delete() {
    isDeleting = true
    Task {
      do {
        try await store.deleteAttachment(id: attachment.id)
        dismiss()
      } catch {
        self.error = error
      }
      isDeleting = false
    }
  }
}
