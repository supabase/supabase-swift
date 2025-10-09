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

      Section("File Operations") {
        NavigationLink(destination: FileUploadView()) {
          ExampleRow(
            title: "Upload Files",
            description: "Upload images, documents, and files",
            icon: "arrow.up.doc.fill"
          )
        }

        NavigationLink(destination: FileDownloadView()) {
          ExampleRow(
            title: "Download Files",
            description: "Download and preview stored files",
            icon: "arrow.down.doc.fill"
          )
        }

        NavigationLink(destination: FileManagementView()) {
          ExampleRow(
            title: "File Management",
            description: "Move, copy, and delete files",
            icon: "doc.on.doc.fill"
          )
        }
      }

      Section("Advanced Features") {
        NavigationLink(destination: ImageTransformView()) {
          ExampleRow(
            title: "Image Transformations",
            description: "Resize, crop, and optimize images",
            icon: "photo.fill"
          )
        }

        NavigationLink(destination: SignedURLsView()) {
          ExampleRow(
            title: "Signed URLs",
            description: "Generate temporary access URLs",
            icon: "link.circle.fill"
          )
        }

        NavigationLink(destination: FileSearchView()) {
          ExampleRow(
            title: "Search & Metadata",
            description: "Search files and manage metadata",
            icon: "magnifyingglass"
          )
        }
      }
    }
    .navigationTitle("Storage")
  }
}
