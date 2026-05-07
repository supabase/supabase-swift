//
//  StorageExamplesView.swift
//  Examples
//
//  Comprehensive showcase of Supabase Storage features
//

import SwiftUI

struct StorageExamplesView: View {
  var body: some View {
    List {
      Section {
        Text("Manage files and buckets with Supabase Storage")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Bucket Management") {
        NavigationLink(destination: BucketList()) {
          ExampleRow(
            title: "Browse Buckets",
            description: "List and manage storage buckets",
            icon: "folder.fill"
          )
        }

        NavigationLink(destination: BucketOperationsView()) {
          ExampleRow(
            title: "Bucket Operations",
            description: "Create, update, and configure buckets",
            icon: "folder.badge.gearshape"
          )
        }
      }

      Section("Upload") {
        NavigationLink(destination: FileUploadView()) {
          ExampleRow(
            title: "Upload Files",
            description: "Smart default, multipart, or TUS resumable with pause/resume/cancel",
            icon: "arrow.up.doc.fill"
          )
        }
      }

      Section("Download") {
        NavigationLink(destination: FileDownloadView()) {
          ExampleRow(
            title: "Download Files",
            description:
              "To memory or to disk with pause, resume, cancel, and background-session support",
            icon: "arrow.down.doc.fill"
          )
        }
      }

      Section("File Management") {
        NavigationLink(destination: FileManagementView()) {
          ExampleRow(
            title: "Move, Copy & Delete",
            description: "Manage files within and across buckets",
            icon: "doc.on.doc.fill"
          )
        }

        NavigationLink(destination: FileSearchView()) {
          ExampleRow(
            title: "Search & Metadata",
            description: "Search files and inspect file metadata",
            icon: "magnifyingglass"
          )
        }
      }

      Section("Advanced Features") {
        NavigationLink(destination: ImageTransformView()) {
          ExampleRow(
            title: "Image Transformations",
            description: "Resize, crop, and optimize images on-the-fly",
            icon: "photo.fill"
          )
        }

        NavigationLink(destination: SignedURLsView()) {
          ExampleRow(
            title: "Signed URLs",
            description: "Generate time-limited access URLs",
            icon: "link.circle.fill"
          )
        }
      }
    }
    .navigationTitle("Storage")
  }
}
