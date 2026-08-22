//
//  PostgrestFilterOperandEscapingTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 22/08/26.
//

import Testing

@testable import PostgREST

/// Pins where filter-operand escaping is applied, and — more importantly — where it must **not** be.
///
/// `escapePostgRESTFilterValue` is called at exactly two call sites, `in` and `notIn`. That looks
/// like an oversight, and it has been filed as one (SDK-1510). It is not. The asymmetry tracks the
/// PostgREST grammar exactly: a top-level operand runs to the **end of the query-parameter value**,
/// so nothing inside it is structural and nothing needs escaping. Escaping is only needed where the
/// operand sits inside a delimited list.
///
/// Measured against PostgREST 14.15 (`public.ecr.aws/supabase/postgrest:v14.15`) on Postgres 17,
/// against a `text` column, one row per value:
///
/// | Context | Unquoted | Quoted |
/// |---|---|---|
/// | `txt=eq.a,b` | 200, **correct row** | `eq."a,b"` → 200, `[]` |
/// | `txt=in.(a,b)` | 200, `[]` — matches nothing | `in.("a,b")` → 200, **correct row** |
/// | `or=(txt.eq.a,b)` | **400 `PGRST100`** | `or=(txt.eq."a,b")` → 200, **correct row** |
///
/// Every awkward scalar value round-trips correctly with no escaping at all — `a,b`, `a"b`, `a\b`,
/// `a(b)c`, `a.b`, `a:b`, `a&b`, `a=b`, `a+b`, `a b`, `" lead"`, `(1,2)`, `{a,b}`, `eq.x`, `a%b`,
/// `a#b`, `a'b`, `null`, `true`, `*`, `a->b`, `a->>b`. Quoting any of them returns `[]`.
///
/// The decisive observation is that PostgREST treats a double quote in a scalar operand as **data,
/// not syntax**: a row whose stored value is literally `"quoted"`, quote characters included, is the
/// row that `txt=eq.%22quoted%22` returns. So quoting a scalar operand does not delimit it — it
/// changes what is being compared.
///
/// Do not "fix" the asymmetry these tests describe. Quoting the scalar operators would silently
/// return zero rows for any value containing a comma, quote, backslash, paren or edge whitespace,
/// and would break `match`/`imatch` for essentially every non-trivial regex.
@Suite
struct PostgrestFilterOperandEscapingTests {
  // MARK: - Scalar operands are sent through unescaped, and that is correct

  @Test
  func eqSendsCommaUnescaped() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("name", value: "a,b").execute()
    #expect(capture.query?.contains("name=eq.a,b") == true)
  }

  @Test
  func eqSendsEmbeddedQuoteUnescaped() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("name", value: #"a"b"#).execute()
    #expect(capture.query?.contains(#"name=eq.a"b"#) == true)
  }

  @Test
  func eqSendsBackslashUnescaped() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("name", value: #"a\b"#).execute()
    #expect(capture.query?.contains(#"name=eq.a\b"#) == true)
  }

  @Test
  func eqLeavesPlainValueAlone() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("name", value: "plain").execute()
    #expect(capture.query?.contains("name=eq.plain") == true)
  }

  /// Edge whitespace is data. `escapePostgRESTFilterValue` would quote this one; the scalar
  /// operators must not, because the server compares against the quote marks too.
  @Test
  func eqPreservesLeadingWhitespaceUnquoted() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("name", value: " lead").execute()
    #expect(capture.query?.contains("name=eq. lead") == true)
  }

  /// A regex operand is the case quoting would damage most: the escaper doubles the backslash.
  @Test
  func matchSendsRegexUnescaped() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .match("email", pattern: #"@supabase\.io$"#).execute()
    #expect(capture.query?.contains(#"email=match.@supabase\.io$"#) == true)
  }

  /// `not` wraps the same scalar shape, so it follows the same rule.
  @Test
  func notWrappedOperandStaysUnescaped() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .not("name", operator: .eq, value: "a,b").execute()
    #expect(capture.query?.contains("name=not.eq.a,b") == true)
  }

  @Test
  func comparisonOperatorsAllSendCommaUnescaped() async throws {
    let cases: [(String, (PostgrestFilterBuilder) -> PostgrestFilterBuilder)] = [
      ("neq", { $0.neq("c", value: "a,b") }),
      ("gt", { $0.gt("c", value: "a,b") }),
      ("gte", { $0.gte("c", value: "a,b") }),
      ("lt", { $0.lt("c", value: "a,b") }),
      ("lte", { $0.lte("c", value: "a,b") }),
      ("like", { $0.like("c", pattern: "a,b") }),
      ("ilike", { $0.ilike("c", pattern: "a,b") }),
      ("imatch", { $0.imatch("c", pattern: "a,b") }),
      ("isdistinct", { $0.isDistinct("c", value: "a,b") }),
    ]

    for (op, apply) in cases {
      let capture = QueryCapture()
      _ = try await apply(capture.client.from("t").select()).execute()
      #expect(capture.query?.contains("c=\(op).a,b") == true, "\(op) escaped its operand")
    }
  }

  // MARK: - Delimited-list operands are escaped, and that is also correct

  /// `in.(a,b)` matches nothing on the server — the comma splits the list. Quoting is required.
  @Test
  func inQuotesAnOperandContainingAComma() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().in("name", values: ["a,b"]).execute()
    #expect(capture.query?.contains(#"name=in.("a,b")"#) == true)
  }

  @Test
  func inBackslashEscapesAnEmbeddedQuote() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().in("name", values: [#"a"b"#]).execute()
    #expect(capture.query?.contains(#"name=in.("a\"b")"#) == true)
  }

  @Test
  func inLeavesAPlainOperandUnquoted() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().in("name", values: ["plain"]).execute()
    #expect(capture.query?.contains("name=in.(plain)") == true)
  }

  @Test
  func notInQuotesAnOperandContainingAComma() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().notIn("name", values: ["a,b"]).execute()
    #expect(capture.query?.contains(#"name=not.in.("a,b")"#) == true)
  }

  // MARK: - Array-literal operands escape one layer down, per element

  /// The commas *between* elements are structural; the comma *inside* an element is data. That
  /// split is what `postgrestArrayElement` implements, and it is the correct layer — quoting the
  /// whole literal instead yields `cs."{a,b}"`, which the server rejects with `22P02 malformed
  /// array literal`.
  @Test
  func containsEscapesPerElementNotWholeLiteral() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .contains("tags", value: ["a,b", "c"]).execute()
    #expect(capture.query?.contains(#"tags=cs.{"a,b",c}"#) == true)
  }

  /// A `String` operand here is the caller hand-writing the literal, so it is passed through. The
  /// braces and commas are theirs and are structural.
  @Test
  func containsPassesAHandWrittenLiteralThrough() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().contains("tags", value: "{a,b}").execute()
    #expect(capture.query?.contains("tags=cs.{a,b}") == true)
  }

  /// A range literal is made of reserved characters. Quoting it yields `sl."[a,b)"`, which the
  /// server rejects with `22P02 malformed range literal`.
  @Test
  func rangeOperandIsPassedThrough() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("events").select()
      .rangeLt("scheduled", range: "[2024-01-01,2024-06-01)").execute()
    #expect(capture.query?.contains("scheduled=sl.[2024-01-01,2024-06-01)") == true)
  }
}
