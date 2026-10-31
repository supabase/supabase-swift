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
      storage.set("verifier-a", "flow-a", .signIn)
      storage.set("verifier-b", "flow-b", .signIn)

      #expect(storage.get("flow-a") == "verifier-a")
      #expect(storage.get("flow-b") == "verifier-b")
    }
  }

  @Test
  func getWithNoFlowIdFallsBackToMostRecentlyStoredVerifier() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a", .signIn)
      storage.set("verifier-b", "flow-b", .signIn)

      #expect(storage.get(nil) == "verifier-b")
    }
  }

  @Test
  func ringEvictsOldestFlowBeyondMaxConcurrentFlows() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      for i in 0..<CodeVerifierStorage.maxConcurrentFlows {
        storage.set("verifier-\(i)", "flow-\(i)", .signIn)
      }
      for i in 0..<CodeVerifierStorage.maxConcurrentFlows {
        #expect(storage.get("flow-\(i)") == "verifier-\(i)")
      }

      storage.set("verifier-5", "flow-5", .signIn)

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
      storage.set("verifier-a", "flow-a", .signIn)
      storage.set("verifier-b", "flow-b", .signIn)

      storage.remove("flow-a")

      #expect(storage.get("flow-a") == nil)
      #expect(storage.get("flow-b") == "verifier-b")
    }
  }

  @Test
  func removeClearsLegacyFallbackOnlyWhenItMatchesTheRemovedFlow() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a", .signIn)
      storage.set("verifier-b", "flow-b", .signIn)

      storage.remove("flow-a")
      #expect(storage.get(nil) == "verifier-b")

      storage.remove("flow-b")
      #expect(storage.get(nil) == nil)
    }
  }

  @Test
  func storesThePurposeOfEachFlowUntilItIsRemoved() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a", .recovery)
      storage.set("verifier-b", "flow-b", .signIn)

      #expect(storage.purpose("flow-a") == .recovery)
      #expect(storage.purpose("flow-b") == .signIn)
      #expect(storage.purpose(nil) == .signIn)

      storage.remove("flow-b")
      #expect(storage.purpose("flow-b") == nil)
      #expect(storage.purpose(nil) == nil)
      #expect(storage.purpose("flow-a") == .recovery)
    }
  }

  @Test
  func removeWithNoFlowIdOnlyClearsTheLegacySlot() {
    let (storage, _, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a", .signIn)

      storage.remove(nil)

      #expect(storage.get(nil) == nil)
      #expect(storage.get("flow-a") == "verifier-a")
    }
  }

  @Test
  func removeAllClearsEveryPendingFlowAndTheLegacySlot() {
    let (storage, localStorage, client) = makeSUT()
    withExtendedLifetime(client) {
      storage.set("verifier-a", "flow-a", .signIn)
      storage.set("verifier-b", "flow-b", .signIn)

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
        storage.set("verifier-\(i)", "flow-\(i)", .signIn)
      }

      let pendingFlows = (0..<flowCount).filter { storage.get("flow-\($0)") != nil }
      #expect(pendingFlows.count == CodeVerifierStorage.maxConcurrentFlows)
    }
  }
}
