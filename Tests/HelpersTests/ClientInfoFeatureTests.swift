import Helpers
import Testing

@Suite
struct ClientInfoFeatureTests {
  @Test
  func appendsFeaturesAsTheLastParameter() {
    #expect(
      ClientInfoFeature.clientInfo(
        "supabase-swift/3.0.0; platform=iOS; runtime=swift; runtime-version=6.2",
        adding: [.typedAPI]
      )
        == "supabase-swift/3.0.0; platform=iOS; runtime=swift; runtime-version=6.2; features=typed-api"
    )
  }

  @Test
  func leavesTheValueUnchangedWithoutFeatures() {
    #expect(
      ClientInfoFeature.clientInfo("supabase-swift/3.0.0; runtime=swift", adding: [])
        == "supabase-swift/3.0.0; runtime=swift"
    )
  }

  @Test
  func mergesAnExistingFeaturesParameterSortedAndOnce() {
    #expect(
      ClientInfoFeature.clientInfo(
        "supabase-swift/3.0.0; features=zeta,typed-api; runtime=swift",
        adding: [.typedAPI, ClientInfoFeature(rawValue: "alpha")]
      ) == "supabase-swift/3.0.0; runtime=swift; features=alpha,typed-api,zeta"
    )
  }
}
