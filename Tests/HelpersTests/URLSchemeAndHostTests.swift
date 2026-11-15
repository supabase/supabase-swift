import Foundation
import Helpers
import Testing

@Suite
struct URLSchemeAndHostTests {
  @Test(arguments: [
    "https://project-ref.supabase.co",
    "http://localhost:54321/rest/v1",
    "wss://project-ref.supabase.co/realtime/v1",
    "http://127.0.0.1",
  ])
  func acceptsURLsWithASchemeAndAHost(url: String) throws {
    #expect(try #require(URL(string: url)).hasSchemeAndHost)
  }

  @Test(arguments: [
    "project-ref",
    "https:///v1",
    "//project-ref.supabase.co/v1",
    "mailto:someone@example.com",
    "file:///tmp/supabase",
  ])
  func rejectsURLsWithoutASchemeOrAHost(url: String) throws {
    #expect(try #require(URL(string: url)).hasSchemeAndHost == false)
  }
}
