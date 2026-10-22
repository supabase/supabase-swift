//
//  PresenceTrackerTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Testing

@testable import Realtime

@Suite
struct PresenceTrackerTests {
  private func metas(_ refs: [(ref: String, prev: String?, name: String)]) -> JSONValue {
    .object([
      "metas": .array(
        refs.map { ref, prev, name in
          var meta: JSONObject = ["phx_ref": .string(ref), "name": .string(name)]
          if let prev { meta["phx_ref_prev"] = .string(prev) }
          return .object(meta)
        })
    ])
  }

  @Test
  func stateReplacesAndReportsJoinsAndLeaves() {
    var tracker = PresenceTracker()
    _ = tracker.applyState(["u1": metas([("r1", nil, "ana")]), "u2": metas([("r2", nil, "bo")])])

    let change = tracker.applyState([
      "u1": metas([("r1", nil, "ana"), ("r3", nil, "ana-phone")]),
      "u3": metas([("r4", nil, "cy")]),
    ])

    #expect(Set(tracker.state.entries.keys) == ["u1", "u3"])
    #expect(tracker.state.entries["u1"]?.map(\.ref) == ["r1", "r3"])
    #expect(change.joins["u1"]?.map(\.ref) == ["r3"])
    #expect(change.joins["u3"]?.map(\.ref) == ["r4"])
    #expect(change.leaves["u2"]?.map(\.ref) == ["r2"])
    #expect(change.leaves["u1"] == nil)
    #expect(tracker.state.entries["u1"]?.first?.payload == ["name": "ana"])
  }

  @Test
  func diffMergesJoinsAndKeepsOtherMetasOnLeave() throws {
    var tracker = PresenceTracker()
    _ = tracker.applyState(["u1": metas([("r1", nil, "ana")])])

    let joinedResult = tracker.applyDiff([
      "joins": ["u1": metas([("r2", nil, "ana-phone")])], "leaves": [:],
    ])
    let joined = try #require(joinedResult)
    #expect(tracker.state.entries["u1"]?.map(\.ref) == ["r1", "r2"])
    #expect(joined.joins["u1"]?.map(\.ref) == ["r2"])

    let leftResult = tracker.applyDiff([
      "joins": [:], "leaves": ["u1": metas([("r1", nil, "ana")])],
    ])
    let left = try #require(leftResult)
    #expect(tracker.state.entries["u1"]?.map(\.ref) == ["r2"])
    #expect(left.leaves["u1"]?.map(\.ref) == ["r1"])

    _ = tracker.applyDiff(["joins": [:], "leaves": ["u1": metas([("r2", nil, "ana-phone")])]])
    #expect(tracker.state.entries["u1"] == nil)
  }

  @Test
  func updateCarriesThePreviousRef() throws {
    var tracker = PresenceTracker()
    _ = tracker.applyState(["u1": metas([("r1", nil, "ana")])])

    let changeResult = tracker.applyDiff([
      "joins": ["u1": metas([("r2", "r1", "ana!")])],
      "leaves": ["u1": metas([("r1", nil, "ana")])],
    ])
    let change = try #require(changeResult)

    #expect(tracker.state.entries["u1"]?.map(\.ref) == ["r2"])
    #expect(change.joins["u1"]?.first?.previousRef == "r1")
    #expect(tracker.state.entries["u1"]?.first?.payload == ["name": "ana!"])
  }

  @Test
  func diffsBeforeTheFirstStateAreQueuedAndAppliedAfterIt() {
    var tracker = PresenceTracker()

    let early = tracker.applyDiff(["joins": ["u2": metas([("r2", nil, "bo")])], "leaves": [:]])
    #expect(early == nil)
    #expect(tracker.state.entries.isEmpty)

    let change = tracker.applyState(["u1": metas([("r1", nil, "ana")])])

    #expect(Set(tracker.state.entries.keys) == ["u1", "u2"])
    #expect(Set(change.joins.keys) == ["u1", "u2"])
  }

  @Test
  func resetClearsStateAndQueueButKeepsTheTrackedPayload() {
    var tracker = PresenceTracker()
    tracker.trackedPayload = ["name": "ana"]
    _ = tracker.applyState(["u1": metas([("r1", nil, "ana")])])

    tracker.reset()

    #expect(tracker.state.entries.isEmpty)
    #expect(tracker.trackedPayload == ["name": "ana"])
    let afterReset = tracker.applyDiff(["joins": [:], "leaves": [:]])
    #expect(afterReset == nil)
  }

  @Test
  func malformedMetasAreSkipped() {
    var tracker = PresenceTracker()

    let change = tracker.applyState([
      "u1": .object(["metas": .array([.object(["name": "no ref"]), .string("junk")])]),
      "u2": "not an object",
    ])

    #expect(tracker.state.entries.isEmpty)
    #expect(change.joins.isEmpty)
  }
}
