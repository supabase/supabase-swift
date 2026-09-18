/// A Postgres schema, named by a type so a relation can say which schema it lives in.
///
/// Conform an uninhabited type to it, the way the request phases are declared, and point a
/// relation at it with `@Table("secrets", schema: PrivateSchema.self)`:
///
/// ```swift
/// enum PrivateSchema: PostgrestSchema {
///   static let name = "private"
/// }
/// ```
///
/// Naming the schema is what lets the compiler reject a relation queried through the wrong one.
/// See ``PostgrestSchemaScope``.
public protocol PostgrestSchema: Sendable {
  /// The schema's name as PostgREST addresses it, for example `"private"`.
  static var name: String { get }
}

/// The schema a relation belongs to when it does not name one, matching PostgREST's own default.
public enum PublicSchema: PostgrestSchema {
  public static let name = "public"
}
