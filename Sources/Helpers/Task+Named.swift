//
//  Task+Named.swift
//  Helpers
//
//  Created by Guilherme Souza on 04/11/26.
//

extension Task where Failure == Never {
  /// Starts `operation` as a task called `name`, which debuggers and Instruments show, when the OS
  /// has task names, and as an ordinary `Task` otherwise.
  ///
  /// `Task(name:)` is gated on the Apple 26 releases only, so the fallback runs on earlier Apple
  /// releases. Linux always takes the named branch.
  @discardableResult
  package static func named(
    _ name: String,
    priority: TaskPriority? = nil,
    @_implicitSelfCapture @_inheritActorContext(always)
    operation: sending @escaping @isolated(any) () async -> Success
  ) -> Task<Success, Never> {
    if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
      Task(name: name, priority: priority, operation: operation)
    } else {
      Task(priority: priority, operation: operation)
    }
  }
}
