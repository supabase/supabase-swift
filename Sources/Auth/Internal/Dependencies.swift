import Alamofire
import ConcurrencyExtras
import Foundation
//
//struct Dependencies {
//  // var sessionManager: SessionManager
//
//  var eventEmitter = AuthStateChangeEventEmitter()
//  var date: @Sendable () -> Date = { Date() }
//}
//
//extension Dependencies {
//  static let instances = LockIsolated([AuthClientID: Dependencies]())
//
//  static subscript(_ id: AuthClientID) -> Dependencies {
//    get {
//      guard let instance = instances[id] else {
//        fatalError("Dependencies not found for id: \(id)")
//      }
//      return instance
//    }
//    set {
//      instances.withValue { $0[id] = newValue }
//    }
//  }
//}
