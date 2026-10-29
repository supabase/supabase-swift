// Journey: Database (PostgREST) — insert, filter, update, delete, and RPC through SupabaseClient.
// Proof: the SDK's own reads, plus `verify.sh sql` on the `todos` row that this run created.
import Foundation
import Supabase

struct Todo: Codable, Sendable {
  let id: UUID
  var description: String
  var isComplete: Bool
  var tags: [String]

  enum CodingKeys: String, CodingKey {
    case id, description, tags
    case isComplete = "is_complete"
  }
}

struct NewTodo: Encodable, Sendable {
  let description: String
  let tags: [String]
}

let client = Verify.client()
let marker = Verify.unique("todo")

Verify.step("db-read-seed", "select seeded users ordered by username")
if let users: [[String: String]] = await Verify.attempt("db-read-seed", {
  try await client.from("users").select("username").order("username").execute().value
}) {
  let names = users.compactMap { $0["username"] }
  Verify.save("db-read-seed.json", names)
  Verify.check(
    "db-read-seed", names == ["awailas", "dragarcia", "kiwicopple", "supabot"],
    "usernames \(names)")
}

Verify.step("db-insert", "insert todo '\(marker)' with returning: .representation")
let inserted: Todo? = await Verify.attempt("db-insert") {
  try await client.from("todos")
    .insert(NewTodo(description: marker, tags: ["verify"]), returning: .representation)
    .single()
    .execute()
    .value
}
if let inserted {
  Verify.save("db-insert.json", inserted)
  Verify.check(
    "db-insert", inserted.description == marker && !inserted.isComplete,
    "id \(inserted.id) is_complete=\(inserted.isComplete)")

  Verify.step("db-filter", "select todos where description = marker")
  if let found: [Todo] = await Verify.attempt("db-filter", {
    try await client.from("todos").select().eq("description", value: marker).execute().value
  }) {
    Verify.check("db-filter", found.map(\.id) == [inserted.id], "found \(found.count) row(s)")
  }

  Verify.step("db-update", "mark the todo complete")
  if let updated: Todo = await Verify.attempt("db-update", {
    try await client.from("todos")
      .update(["is_complete": true], returning: .representation)
      .eq("id", value: inserted.id)
      .single()
      .execute()
      .value
  }) {
    Verify.save("db-update.json", updated)
    Verify.check("db-update", updated.isComplete, "is_complete=\(updated.isComplete)")
  }
}

Verify.step("db-rpc", "call RPC get_status(name_param: 'supabot')")
if let status: String = await Verify.attempt("db-rpc", {
  try await client.rpc("get_status", params: ["name_param": "supabot"]).execute().value
}) {
  Verify.check("db-rpc", status == "ONLINE", "status \(status)")
}

// The row stays so `verify.sh sql` can show it from outside the SDK; `db-delete` covers deletion
// on a second row.
Verify.step("db-delete", "insert then delete a throwaway todo")
let doomed = Verify.unique("doomed")
if let row: Todo = await Verify.attempt("db-delete", {
  try await client.from("todos")
    .insert(NewTodo(description: doomed, tags: []), returning: .representation)
    .single().execute().value
}) {
  _ = await Verify.attempt("db-delete") {
    try await client.from("todos").delete().eq("id", value: row.id).execute()
  }
  let left: [Todo] =
    (await Verify.attempt("db-delete") {
      try await client.from("todos").select().eq("id", value: row.id).execute().value
    }) ?? [Todo(id: row.id, description: doomed, isComplete: false, tags: [])]
  Verify.check("db-delete", left.isEmpty, "rows left after delete: \(left.count)")
}

print("MARKER \(marker)")
Verify.finish()
