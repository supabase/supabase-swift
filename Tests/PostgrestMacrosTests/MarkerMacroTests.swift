import MacroTesting
import XCTest

@testable import PostgrestMacrosPlugin

final class MarkerMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      macros: [
        "PrimaryKey": PrimaryKeyMacro.self,
        "Default": DefaultMacro.self,
        "Column": ColumnMacro.self,
        "Relationship": RelationshipMacro.self,
      ]
    ) { super.invokeTest() }
  }

  func testPrimaryKeyProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @PrimaryKey var id: UUID
      }
      """
    } expansion: {
      """
      struct Foo {
        var id: UUID
      }
      """
    }
  }

  func testDefaultProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @Default var isComplete: Bool
      }
      """
    } expansion: {
      """
      struct Foo {
        var isComplete: Bool
      }
      """
    }
  }

  func testColumnProducesNoPeers() {
    assertMacro {
      """
      struct Foo {
        @Column("user_id") var userId: UUID
      }
      """
    } expansion: {
      """
      struct Foo {
        var userId: UUID
      }
      """
    }
  }

  func testRelationshipProducesNoPeers() {
    assertMacro {
      #"""
      struct Foo {
        @Relationship(\Todo.userId) var profile: Profile?
      }
      """#
    } expansion: {
      #"""
      struct Foo {
        var profile: Profile?
      }
      """#
    }
  }
}
