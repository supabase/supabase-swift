import Helpers
import Testing

@Suite
struct APIKeyFormatTests {
  @Test(arguments: [
    "sb_publishable_abc123",
    "sb_secret_abc123",
  ])
  func isNewRecognizesNewFormatKeys(key: String) {
    #expect(APIKeyFormat.isNew(key))
  }

  @Test(arguments: [
    "sb_temp_nonce123_payload456",
    "sb_unknown_abc123",
    "header.payload.signature",
    "anon-key",
  ])
  func isNewRejectsNonNewFormatKeys(key: String) {
    #expect(!APIKeyFormat.isNew(key))
  }

  @Test
  func shouldWarnAcceptsRecognizedAndLegacyKeysSilently() {
    #expect(!APIKeyFormat.shouldWarn(for: "sb_publishable_shouldwarn1"))
    #expect(!APIKeyFormat.shouldWarn(for: "sb_secret_shouldwarn1"))
    #expect(!APIKeyFormat.shouldWarn(for: "sb_temp_shouldwarn1_payload"))
    #expect(!APIKeyFormat.shouldWarn(for: "header.payload.signature"))
    #expect(!APIKeyFormat.shouldWarn(for: "anon-key"))
  }

  @Test
  func shouldWarnOnceForUnrecognizedSubtype() {
    #expect(APIKeyFormat.shouldWarn(for: "sb_uniquesubtypeA_key1"))
    #expect(!APIKeyFormat.shouldWarn(for: "sb_uniquesubtypeA_key2"))
  }

  @Test
  func shouldWarnTreatsDifferentSubtypesIndependently() {
    #expect(APIKeyFormat.shouldWarn(for: "sb_uniquesubtypeB_key1"))
    #expect(APIKeyFormat.shouldWarn(for: "sb_uniquesubtypeC_key1"))
  }

  @Test
  func shouldWarnGroupsUnparsableSubtypesTogether() {
    #expect(APIKeyFormat.shouldWarn(for: "sb_"))
    #expect(!APIKeyFormat.shouldWarn(for: "sb_uniqueunparseabletype"))
  }

  @Test
  func functionsBearerTokenSuppressesNewFormatKeyFallback() {
    #expect(
      APIKeyFormat.functionsBearerToken(
        accessToken: "sb_publishable_abc123",
        supabaseKey: "sb_publishable_abc123"
      ) == nil
    )
  }

  @Test
  func functionsBearerTokenKeepsLegacyKeyFallback() {
    #expect(
      APIKeyFormat.functionsBearerToken(
        accessToken: "legacy-jwt-key", supabaseKey: "legacy-jwt-key")
        == "legacy-jwt-key"
    )
  }

  @Test
  func functionsBearerTokenPassesThroughRealSessionToken() {
    #expect(
      APIKeyFormat.functionsBearerToken(
        accessToken: "real.session.jwt",
        supabaseKey: "sb_publishable_abc123"
      ) == "real.session.jwt"
    )
  }
}
