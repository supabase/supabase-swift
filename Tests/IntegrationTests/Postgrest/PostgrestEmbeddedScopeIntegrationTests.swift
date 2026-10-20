//
//  PostgrestEmbeddedScopeIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

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

@SelectionOf(Posts.self)
struct PostWithDiscussion {
  var id: Int
  @Relationship(\Posts.discussionId) var discussion: DiscussionTitle?
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestEmbeddedScopeIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

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
