//
//  Task+Immediate.swift
//  Helpers
//
//  Created by Guilherme Souza on 19/10/26.
//

extension Task where Failure == Never {
  /// Starts `operation` on the caller's actor, running it inline up to its first suspension
  /// point when the OS has `Task.immediate`, and as an ordinary `Task` otherwise.
  ///
  /// The synchronous prefix is what makes a side effect observable to the caller before this
  /// function returns: state the body mutates before it first awaits is already mutated. Code
  /// must stay correct without that prefix, because the fallback does not have it.
  ///
  /// `Task.immediate` is gated on the Apple 26 releases only, so the fallback runs on earlier
  /// Apple releases. Linux always takes the immediate branch.
  @discardableResult
  package static func immediateIfAvailable(
    priority: TaskPriority? = nil,
    @_implicitSelfCapture @_inheritActorContext(always)
    operation: sending @escaping @isolated(any) () async -> Success
  ) -> Task<Success, Never> {
    if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
      Task.immediate(priority: priority, operation: operation)
    } else {
      Task(priority: priority, operation: operation)
    }
  }
}

extension Task where Failure == any Error {
  /// The throwing form of ``Task/immediateIfAvailable(priority:operation:)``.
  @discardableResult
  package static func immediateIfAvailable(
    priority: TaskPriority? = nil,
    @_implicitSelfCapture @_inheritActorContext(always)
    operation: sending @escaping @isolated(any) () async throws -> Success
  ) -> Task<Success, any Error> {
    if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
      Task.immediate(priority: priority, operation: operation)
    } else {
      Task(priority: priority, operation: operation)
    }
  }
}

extension ThrowingTaskGroup where Failure == any Error {
  /// Adds a child task that runs inline up to its first suspension point when the OS has
  /// `addImmediateTask`, and as an ordinary enqueued child otherwise.
  ///
  /// The child inherits the caller's actor on both paths. The synchronous prefix is what makes
  /// the child's first side effect happen before this call returns; see
  /// ``Task/immediateIfAvailable(priority:operation:)``.
  package mutating func addImmediateTaskIfAvailable(
    @_implicitSelfCapture @_inheritActorContext(always)
    operation: sending @escaping @isolated(any) () async throws -> ChildTaskResult
  ) {
    if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
      addImmediateTask(operation: operation)
    } else {
      addTask(operation: operation)
    }
  }
}
