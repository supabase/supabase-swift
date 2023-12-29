import PostgREST
import XCTest

struct Todo: Codable, Hashable {
  let id: UUID
  var description: String
  var isComplete: Bool
  var tags: [String]
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case description
    case isComplete = "is_complete"
    case tags
    case createdAt = "created_at"
  }
}

struct NewTodo: Codable, Hashable {
  var description: String
  var isComplete: Bool = false
  var tags: [String]

  enum CodingKeys: String, CodingKey {
    case description
    case isComplete = "is_complete"
    case tags
  }
}

struct User: Codable, Hashable {
  let email: String
}

@available(iOS 15.0.0, macOS 12.0.0, tvOS 13.0, *)
final class IntegrationTests: XCTestCase {
  let client = PostgrestClient(
    url: URL(string: "http://localhost:54321/rest/v1")!,
    headers: [
      "Apikey":
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
    ]
  )

  override func setUp() async throws {
    try await super.setUp()

    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )

    // Run fresh test by deleting all data. Delete without a where clause isn't supported, so have
    // to do this `neq` trick to delete all data.
    try await client.from("todos").delete().neq("id", value: UUID().uuidString).execute()
    try await client.from("users").delete().neq("id", value: UUID().uuidString).execute()
  }

  func testIntegration() async throws {
    var todos: [Todo] = try await client.from("todos").select().execute().value
    XCTAssertEqual(todos, [])

    let insertedTodo: Todo = try await client.from("todos")
      .insert(
        NewTodo(
          description: "Implement integration tests for postgrest-swift",
          tags: ["tag 01", "tag 02"]
        ),
        returning: .representation
      )
      .single()
      .execute()
      .value

    todos = try await client.from("todos").select().execute().value
    XCTAssertEqual(todos, [insertedTodo])

    let insertedTodos: [Todo] = try await client.from("todos")
      .insert(
        [
          NewTodo(description: "Make supabase swift libraries production ready", tags: ["tag 01"]),
          NewTodo(description: "Drink some coffee", tags: ["tag 02"]),
        ],
        returning: .representation
      )
      .execute()
      .value

    todos = try await client.from("todos").select().execute().value
    XCTAssertEqual(todos, [insertedTodo] + insertedTodos)

    let drinkCoffeeTodo = insertedTodos[1]
    let updatedTodo: Todo = try await client.from("todos")
      .update(["is_complete": true])
      .eq("id", value: drinkCoffeeTodo.id.uuidString)
      .single()
      .execute()
      .value
    XCTAssertTrue(updatedTodo.isComplete)

    let completedTodos: [Todo] = try await client.from("todos")
      .select()
      .eq("is_complete", value: true)
      .execute()
      .value
    XCTAssertEqual(completedTodos, [updatedTodo])

    try await client.from("todos").delete().eq("is_complete", value: true).execute()
    todos = try await client.from("todos").select().execute().value
    XCTAssertTrue(completedTodos.allSatisfy { todo in !todos.contains(todo) })

    let todosWithSpecificTag: [Todo] = try await client.from("todos").select()
      .contains("tags", value: ["tag 01"]).execute().value
    XCTAssertEqual(todosWithSpecificTag, [insertedTodo, insertedTodos[0]])
  }

  func testQueryWithPlusSign() async throws {
    let users = [
      User(email: "johndoe@mail.com"),
      User(email: "johndoe+test1@mail.com"),
      User(email: "johndoe+test2@mail.com"),
    ]

    try await client.from("users").insert(users).execute()

    let fetchedUsers: [User] = try await client.from("users").select()
      .ilike("email", value: "johndoe+test%").execute().value
    XCTAssertEqual(
      fetchedUsers[...],
      users[1 ... 2]
    )
  }
}
