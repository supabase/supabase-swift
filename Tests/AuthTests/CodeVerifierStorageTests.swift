import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
struct CodeVerifierStorageTests {
  private func makeSUT() -> (
    storage: CodeVerifierStorage, localStorage: InMemoryLocalStorage, client: AuthClient
  ) {
    let localStorage = InMemoryLocalStorage()
    let client = AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "https://project-id.supabase.com")!,
        storageKey: uniqueStorageKey(),
        localStorage: localStorage
      )
    )

    return (client.dependencies.codeVerifierStorage, localStorage, client)
  }

  @Test
  func storesAndRetrievesVerifierByFlowId() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a")
      storage.set("verifier-b", "flow-b")

      #expect(storage.get("flow-a") == "verifier-a")
      #expect(storage.get("flow-b") == "verifier-b")
    }
  }

  @Test
  func getWithNoFlowIdFallsBackToMostRecentlyStoredVerifier() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a")
      storage.set("verifier-b", "flow-b")

      #expect(storage.get(nil) == "verifier-b")
    }
  }

  @Test
  func ringEvictsOldestFlowBeyondMaxConcurrentFlows() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      for i in 0..<CodeVerifierStorage.maxConcurrentFlows {
        storage.set("verifier-\(i)", "flow-\(i)")
      }
      for i in 0..<CodeVerifierStorage.maxConcurrentFlows {
        #expect(storage.get("flow-\(i)") == "verifier-\(i)")
      }

      storage.set("verifier-5", "flow-5")

      #expect(storage.get("flow-0") == nil)
      for i in 1...5 {
        #expect(storage.get("flow-\(i)") == "verifier-\(i)")
      }
    }
  }

  @Test
  func removeDeletesOnlyItsOwnFlow() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a")
      storage.set("verifier-b", "flow-b")

      storage.remove("flow-a")

      #expect(storage.get("flow-a") == nil)
      #expect(storage.get("flow-b") == "verifier-b")
    }
  }

  @Test
  func removeClearsLegacyFallbackOnlyWhenItMatchesTheRemovedFlow() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a")
      storage.set("verifier-b", "flow-b")

      storage.remove("flow-a")
      #expect(storage.get(nil) == "verifier-b")

      storage.remove("flow-b")
      #expect(storage.get(nil) == nil)
    }
  }

  @Test
  func removeWithNoFlowIdOnlyClearsTheLegacySlot() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a")

      storage.remove(nil)

      #expect(storage.get(nil) == nil)
      #expect(storage.get("flow-a") == "verifier-a")
    }
  }

  @Test
  func removeAllClearsEveryPendingFlowAndTheLegacySlot() {
    let (storage, localStorage, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a")
      storage.set("verifier-b", "flow-b")

      storage.removeAll()

      #expect(storage.get("flow-a") == nil)
      #expect(storage.get("flow-b") == nil)
      #expect(storage.get(nil) == nil)
      #expect(localStorage.storage.isEmpty)
    }
  }

  @Test
  func concurrentSetsPreserveTheMaxConcurrentFlowsBound() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      let flowCount = 20

      DispatchQueue.concurrentPerform(iterations: flowCount) { i in
        storage.set("verifier-\(i)", "flow-\(i)")
      }

      let pendingFlows = (0..<flowCount).filter { storage.get("flow-\($0)") != nil }
      #expect(pendingFlows.count == CodeVerifierStorage.maxConcurrentFlows)
    }
  }
}
