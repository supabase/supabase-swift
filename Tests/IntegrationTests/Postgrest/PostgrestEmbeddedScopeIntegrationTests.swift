//
//  PostgrestEmbeddedScopeIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

// File scope: `@SelectionOf` attaches extensions, which cannot be nested in a type. The tables are
// in `Generated.swift`.
// The schema and rows are in `supabase/migrations/20261006000000_embedded_scope.sql` and
// `supabase/seed.sql`. Every test here is read-only.

/// Leaves `approved` and `createdAt` out on purpose: a scope filters and orders the embedded
/// relation, so both stay usable inside one.
@SelectionOf(Posts.self)
struct PostBody {
  var id: Int
  var author: String
}

@SelectionOf(Discussions.self)
struct DiscussionWithPosts {
  var id: Int
  @Relationship(\Posts.discussionId) var posts: [PostBody]
}

/// The alias differs from the relation name, so the scope prefix is `items.`, not `posts.`.
@SelectionOf(Discussions.self)
struct DiscussionWithItems {
  var id: Int
  @Relationship(\Posts.discussionId) var items: [PostBody]
}

@SelectionOf(Replies.self)
struct ReplyBody {
  var id: Int
}

@SelectionOf(Posts.self)
struct PostWithReplies {
  var id: Int
  @Relationship(\Replies.postId) var replies: [ReplyBody]
}

@SelectionOf(Discussions.self)
struct DiscussionWithThreads {
  var id: Int
  @Relationship(\Posts.discussionId) var posts: [PostWithReplies]
}

@SelectionOf(Discussions.self)
struct DiscussionTitle {
  var title: String
}

/// The many-to-one direction, against the pair that has two foreign keys between it.
@SelectionOf(Posts.self)
struct PostWithDiscussion {
  var id: Int
  @Relationship(\Posts.discussionId) var discussion: DiscussionTitle?
}

/// The server-side half of `PostgrestEmbeddedScopeTests`: the same scopes against a live
/// PostgREST, asserting which rows come back rather than what the query string says.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestEmbeddedScopeIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  /// The trap the two methods exist for: an embedded filter narrows the nested rows and leaves
  /// every parent in place. Discussion 3 has no posts and 4 has no approved one; both come back.
  @Test
  func embeddedKeepsEveryParentRow() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithPosts.self)
      .order { $0.id }
      .embedded(\.posts) { $0.where { $0.approved.eq(true) }.order { $0.id } }
      .execute()
      .value

    #expect(rows.map(\.id) == [1, 2, 3, 4])
    #expect(rows.map { $0.posts.map(\.id) } == [[1, 3], [4], [], []])
  }

  /// `!inner`, placed after the foreign-key hint, drops the parents with no matching post.
  @Test
  func requiringDropsParentsWithNoMatch() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithPosts.self)
      .order { $0.id }
      .requiring(\.posts) { $0.where { $0.approved.eq(true) }.order { $0.id } }
      .execute()
      .value

    #expect(rows.map(\.id) == [1, 2])
    #expect(rows.map { $0.posts.map(\.id) } == [[1, 3], [4]])
  }

  /// The §4.4 shape: `or`, `order` and `limit` inside one `requiring` scope, all applied by the
  /// server. Discussion 1 has three matching posts and keeps only the newest.
  @Test
  func orOrderAndLimitApplyInsideTheScope() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithPosts.self)
      .order { $0.id }
      .requiring(\.posts) {
        $0.where { $0.approved.eq(true) || $0.author.eq("bob") }
          .order { $0.createdAt.desc().nulls(.last) }
          .limit(1)
      }
      .execute()
      .value

    #expect(rows.map(\.id) == [1, 2, 4])
    #expect(rows.map { $0.posts.map(\.id) } == [[3], [4], [5]])
  }

  @Test
  func rangeAppliesInsideTheScope() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithPosts.self)
      .where { $0.id.eq(1) }
      .embedded(\.posts) { $0.order { $0.id }.range(1...1) }
      .execute()
      .value

    #expect(rows.map { $0.posts.map(\.id) } == [[2]])
  }

  /// A dotted path reaches the inner embed: `posts.replies.approved` and `posts.replies.limit`.
  @Test
  func nestedScopeShapesTheInnerEmbed() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithThreads.self)
      .where { $0.id.eq(1) }
      .embedded(\.posts) {
        $0.order { $0.id }
          .embedded(\.replies) { $0.where { $0.approved.eq(true) }.order { $0.id }.limit(1) }
      }
      .execute()
      .value

    #expect(rows.map { $0.posts.map(\.id) } == [[1, 2, 3]])
    #expect(rows.map { $0.posts.map { $0.replies.map(\.id) } } == [[[1], [], []]])
  }

  /// A nested `requiring` constrains its own parent only: posts without an approved reply go,
  /// discussions without such a post stay, with an empty `posts`.
  @Test
  func nestedRequiringConstrainsItsOwnParentOnly() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithThreads.self)
      .order { $0.id }
      .embedded(\.posts) {
        $0.requiring(\.replies) { $0.where { $0.approved.eq(true) }.order { $0.id } }
      }
      .execute()
      .value

    #expect(rows.map(\.id) == [1, 2, 3, 4])
    #expect(rows.map { $0.posts.map(\.id) } == [[1], [], [], []])
    #expect(rows[0].posts.map { $0.replies.map(\.id) } == [[1, 3]])
  }

  /// PostgREST accepts the alias in place of the relation name as the scope prefix.
  @Test
  func theAliasPrefixesTheScope() async throws {
    let rows = try await client.from(Discussions.self)
      .select(DiscussionWithItems.self)
      .order { $0.id }
      .requiring(\.items) { $0.where { $0.author.eq("bob") } }
      .execute()
      .value

    #expect(rows.map(\.id) == [1, 4])
    #expect(rows.map { $0.items.map(\.id) } == [[2], [5]])
  }

  /// The to-one direction, across the pair joined by two foreign keys. The hint picks
  /// `posts.discussion_id`, and `!inner` keeps only the posts whose discussion matches.
  @Test
  func requiringAToOneEmbed() async throws {
    let rows = try await client.from(Posts.self)
      .select(PostWithDiscussion.self)
      .order { $0.id }
      .requiring(\.discussion) { $0.where { $0.title.eq("swift") } }
      .execute()
      .value

    #expect(rows.map(\.id) == [1, 2, 3])
    #expect(rows.compactMap { $0.discussion?.title } == ["swift", "swift", "swift"])
  }

  /// §9.2: the string form can omit the hint, and on this pair that is HTTP 300 `PGRST201`. It
  /// has to arrive as the server's own error with the candidates intact, not as a decode failure.
  @Test
  func anAmbiguousUntypedEmbedIsPGRST201() async throws {
    await #expect { () async throws in
      _ = try await client.from("discussions").select("id,posts(id)").execute()
    } throws: { error in
      guard let error = error as? PostgrestError else { return false }
      return error.kind == .server
        && error.serverError?.code == "PGRST201"
        && error.serverError?.details?.contains("discussion_id") == true
        && error.serverError?.hint?.contains("posts!") == true
        && error.response?.statusCode == 300
    }
  }
}
