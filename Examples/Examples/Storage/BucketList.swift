//
//  BucketList.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import Supabase
import SwiftUI

struct BucketList: View {
  @State var buckets = ActionState<[Bucket], Error>.idle

  var body: some View {
    Group {
      switch buckets {
      case .idle:
        Color.clear
      case .inFlight:
        ProgressView()
      case let .result(.success(buckets)):
        List {
          ForEach(buckets, id: \.self) { bucket in
            NavigationLink(bucket.name, value: bucket)
          }
        }
        .overlay {
          if buckets.isEmpty {
            Text("No buckets found.")
          }
        }
      case let .result(.failure(error)):
        VStack {
          ErrorText(error)
          Button("Retry") {
            Task {
              await load()
            }
          }
        }
      }
    }
    .task {
      await load()
    }
    .navigationTitle("All buckets")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add") {
          Task {
            do {
              try await supabase.storage.createBucket("bucket-\(UUID().uuidString.lowercased())")
              await load()
            } catch {}
          }
        }
      }
    }
  }

  @MainActor
  private func load() async {
    do {
      self.buckets = .inFlight
      let buckets = try await supabase.storage.listBuckets()
      self.buckets = .result(.success(buckets))
    } catch {
      buckets = .result(.failure(error))
    }
  }
}

#Preview {
  BucketList()
}
