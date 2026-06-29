//
//  RequiresLocalSupabase.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Testing

/// A `ConditionTrait` that skips the annotated suite or test when the local
/// Supabase instance is not reachable.
///
/// Apply at the suite level so every test in the suite is skipped together:
/// ```swift
/// @Suite("IE-1 Connection Lifecycle", .requiresLocalSupabase)
/// struct ConnectionE2ETests { ... }
/// ```
///
/// Or per-test:
/// ```swift
/// @Test(.requiresLocalSupabase)
/// func myE2ETest() async throws { ... }
/// ```
extension Trait where Self == ConditionTrait {
  static var requiresLocalSupabase: Self {
    .enabled("Requires a running local Supabase instance") {
      await IntegrationEnv.isReachable()
    }
  }
}
