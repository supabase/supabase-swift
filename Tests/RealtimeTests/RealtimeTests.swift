import XCTest

@testable import Realtime

final class RealtimeTests: XCTestCase {
//  var supabaseUrl: String {
//    guard let url = ProcessInfo.processInfo.environment["supabaseUrl"] else {
//      XCTFail("supabaseUrl not defined in environment.")
//      return ""
//    }
//
//    return url
//  }
//
//  var supabaseKey: String {
//    guard let key = ProcessInfo.processInfo.environment["supabaseKey"] else {
//      XCTFail("supabaseKey not defined in environment.")
//      return ""
//    }
//    return key
//  }
//
//  func testConnection() throws {
//    try XCTSkipIf(
//      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == nil,
//      "INTEGRATION_TESTS not defined"
//    )
//
//    let socket = RealtimeClient(
//      "\(supabaseUrl)/realtime/v1", params: ["Apikey": supabaseKey]
//    )
//
//    let e = expectation(description: "testConnection")
//    socket.onOpen {
//      XCTAssertEqual(socket.isConnected, true)
//      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//        socket.disconnect()
//      }
//    }
//
//    socket.onError { error, _ in
//      XCTFail(error.localizedDescription)
//    }
//
//    socket.onClose {
//      XCTAssertEqual(socket.isConnected, false)
//      e.fulfill()
//    }
//
//    socket.connect()
//
//    waitForExpectations(timeout: 3000) { error in
//      if let error {
//        XCTFail("\(self.name)) failed: \(error.localizedDescription)")
//      }
//    }
//  }
//
//  func testChannelCreation() throws {
//    try XCTSkipIf(
//      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] == nil,
//      "INTEGRATION_TESTS not defined"
//    )
//
//    let client = RealtimeClient(
//      "\(supabaseUrl)/realtime/v1", params: ["Apikey": supabaseKey]
//    )
//    let allChanges = client.channel(.all)
//    allChanges.on(.all) { message in
//      print(message)
//    }
//    allChanges.join()
//    allChanges.leave()
//    allChanges.off(.all)
//
//    let allPublicInsertChanges = client.channel(.schema("public"))
//    allPublicInsertChanges.on(.insert) { message in
//      print(message)
//    }
//    allPublicInsertChanges.join()
//    allPublicInsertChanges.leave()
//    allPublicInsertChanges.off(.insert)
//
//    let allUsersUpdateChanges = client.channel(.table("users", schema: "public"))
//    allUsersUpdateChanges.on(.update) { message in
//      print(message)
//    }
//    allUsersUpdateChanges.join()
//    allUsersUpdateChanges.leave()
//    allUsersUpdateChanges.off(.update)
//
//    let allUserId99Changes = client.channel(
//      .column("id", value: "99", table: "users", schema: "public")
//    )
//    allUserId99Changes.on(.all) { message in
//      print(message)
//    }
//    allUserId99Changes.join()
//    allUserId99Changes.leave()
//    allUserId99Changes.off(.all)
//
//    XCTAssertEqual(client.isConnected, false)
//
//    let e = expectation(description: name)
//    client.onOpen {
//      XCTAssertEqual(client.isConnected, true)
//      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//        client.disconnect()
//      }
//    }
//
//    client.onError { error, _ in
//      XCTFail(error.localizedDescription)
//    }
//
//    client.onClose {
//      XCTAssertEqual(client.isConnected, false)
//      e.fulfill()
//    }
//
//    client.connect()
//
//    waitForExpectations(timeout: 3000) { error in
//      if let error {
//        XCTFail("\(self.name)) failed: \(error.localizedDescription)")
//      }
//    }
//  }
}
