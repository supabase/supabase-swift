# Changelog

## [3.0.0-alpha.2](https://github.com/supabase/supabase-swift/compare/v3.0.0-alpha.1...v3.0.0-alpha.2) (2026-11-23)


### ⚠ BREAKING CHANGES

* **realtime:** in a standalone RealtimeClient, an accessToken callback that returns nil now clears the stored token instead of keeping it, and httpSend drops an Authorization header from `headers` in that case.
* **supabase:** SupabaseClient.Configuration.Database, .Auth, .Functions, .Storage and .Realtime no longer have http or logger, and Database, Auth, Storage and Realtime no longer have clock. Configuration.Global.clock, and clock and now on the standalone module configurations, are @_spi(Testing) and are no longer init parameters.
* **auth:** a redirect URL with implicit tokens throws unless acceptsImplicitTokens is true. Apps that use email links without PKCE, invites, or generateLink links must opt in. An HTTPS redirect URL throws on systems older than iOS 17.4 and the matching releases.
* **storage:** UploadOptions.upsert is Bool? instead of Bool.
* **storage:** ObjectListingOptions.delimited is now Bool?, and objects(prefix:) without options lists every depth with no folders. Pass ObjectListingOptions(delimited: true) to list one level with folders.
* **storage:** report each upload's error from resumeAll ([#1850](https://github.com/supabase/supabase-swift/issues/1850))
* **postgrest:** maybeSingle() no longer sends `Accept: application/vnd.pgrst.object+json`, so PostgREST no longer rolls back a write that matches more than one row. The rows are written, then the call throws PGRST116. Use single() where the rollback matters. The typed maybeSingle() throws a .server error instead of .decoding.
* **auth:** shouldCreateUser is Bool?, channel is MessagingChannel?, and deleteUser(id:softDelete:) takes Bool?. Code that reads these properties must handle nil.

### Features

* **auth:** expose lastChallengedAt, phone, and webAuthnAAGUID on Factor ([#1876](https://github.com/supabase/supabase-swift/issues/1876)) ([7ec2429](https://github.com/supabase/supabase-swift/commit/7ec2429a57b49d064c356a92cdc384d64eb7005a))
* **helpers:** add an equal-jitter BackoffPolicy ([#1868](https://github.com/supabase/supabase-swift/issues/1868)) ([7605701](https://github.com/supabase/supabase-swift/commit/76057011bda871eedac45bd582de8214a3f35422))
* **postgrest:** add defaultToNull to typed bulk insert and upsert ([#1856](https://github.com/supabase/supabase-swift/issues/1856)) ([630823d](https://github.com/supabase/supabase-swift/commit/630823d0ff4f29b72f453c59fcc95472d24cb7e8))
* **realtime:** add buffering policies to presence state and broadcast streams ([#1840](https://github.com/supabase/supabase-swift/issues/1840)) ([3a5863a](https://github.com/supabase/supabase-swift/commit/3a5863a23626a78274f9908d3a6fa63dbd3a8ed9))
* **realtime:** add typed broadcast events ([#1845](https://github.com/supabase/supabase-swift/issues/1845)) ([029cedb](https://github.com/supabase/supabase-swift/commit/029cedb03176e916ea5cc119560fc8fe9f798e3a))


### Bug Fixes

* **auth:** let the server apply its own OTP, channel, delete, and invite defaults ([#1838](https://github.com/supabase/supabase-swift/issues/1838)) ([4e62850](https://github.com/supabase/supabase-swift/commit/4e62850d1a9ef234167fc3dffa552cc99a4d66ca))
* **auth:** refuse implicit-token redirects by default and check the OAuth callback URL ([#1864](https://github.com/supabase/supabase-swift/issues/1864)) ([ac3717a](https://github.com/supabase/supabase-swift/commit/ac3717a6f302c6ebb4ee8994ac4945c78861b3bf))
* **auth:** store the server's user after unlinkIdentity ([#1851](https://github.com/supabase/supabase-swift/issues/1851)) ([88ea33f](https://github.com/supabase/supabase-swift/commit/88ea33f490f20bf785c5242db1c93b4c84c401b5))
* **functions:** send a third-party provider token as given ([#1853](https://github.com/supabase/supabase-swift/issues/1853)) ([254d98d](https://github.com/supabase/supabase-swift/commit/254d98dc6cbf96f2ff9a1668d2432bbcce1762c4))
* **helpers:** use full jitter for the retry backoff ([#1860](https://github.com/supabase/supabase-swift/issues/1860)) ([2201765](https://github.com/supabase/supabase-swift/commit/22017653fc60540f862343b375c8f31b78f2af49))
* **postgrest:** apply the configured coders on the typed path ([#1861](https://github.com/supabase/supabase-swift/issues/1861)) ([5e06f5b](https://github.com/supabase/supabase-swift/commit/5e06f5b0c4cd4a9654be9462f2ed9163091dcb0b))
* **postgrest:** escape the database function name in @Function ([#1857](https://github.com/supabase/supabase-swift/issues/1857)) ([3c49050](https://github.com/supabase/supabase-swift/commit/3c4905066bbc81e30c5200f32e02a93b935313ee))
* **postgrest:** let PostgREST apply its own write defaults in the typed API ([#1835](https://github.com/supabase/supabase-swift/issues/1835)) ([1e5a020](https://github.com/supabase/supabase-swift/commit/1e5a0203bcfabb8dcbd736b33ab1d7cd31ad883f))
* **postgrest:** make maybeSingle behave the same on the typed and untyped paths ([#1841](https://github.com/supabase/supabase-swift/issues/1841)) ([c6ef67c](https://github.com/supabase/supabase-swift/commit/c6ef67cdf9738b9b06c2082812b8e1c701151d0f))
* **postgrest:** throw from typed readOnly() when arguments are not an object ([#1852](https://github.com/supabase/supabase-swift/issues/1852)) ([2c5b4f2](https://github.com/supabase/supabase-swift/commit/2c5b4f2f5f8015ff23e32679d5a20153181c558a))
* **realtime:** accept unknown event values in the join reply ([#1832](https://github.com/supabase/supabase-swift/issues/1832)) ([4d125a2](https://github.com/supabase/supabase-swift/commit/4d125a24ad4f6b0319f2b04674d56596fff8d978))
* **realtime:** confirm subscribe on the join reply unless waitsForSubscription is set ([#1869](https://github.com/supabase/supabase-swift/issues/1869)) ([da4f9b0](https://github.com/supabase/supabase-swift/commit/da4f9b099ee0ec0eb4c240c6063efbf9a3770dff))
* **realtime:** let the server judge typed Postgres changes filters ([#1836](https://github.com/supabase/supabase-swift/issues/1836)) ([e2eec74](https://github.com/supabase/supabase-swift/commit/e2eec74b60fcfe8ef188e49da373bc6a1951a3f7))
* **realtime:** read the httpSend error message from any JSON body ([#1846](https://github.com/supabase/supabase-swift/issues/1846)) ([5d736f7](https://github.com/supabase/supabase-swift/commit/5d736f7c048bd0475b96cd1c79451e0b32765e70))
* **realtime:** treat a nil access token after a real one as "no user" ([#1865](https://github.com/supabase/supabase-swift/issues/1865)) ([554ed9f](https://github.com/supabase/supabase-swift/commit/554ed9f8f94c724b6113596b0eeee98eae52f1f8))
* **storage:** keep a minimum wait between resumable upload retries ([#1866](https://github.com/supabase/supabase-swift/issues/1866)) ([908d3a5](https://github.com/supabase/supabase-swift/commit/908d3a5b234343a644fc8b90bffffd9b6335cffc))
* **storage:** keep resumable upload requests on the storage origin and inside the container ([#1863](https://github.com/supabase/supabase-swift/issues/1863)) ([fd7dcd4](https://github.com/supabase/supabase-swift/commit/fd7dcd414d2f6887d5b3ffffb526cf3466259ad2))
* **storage:** leave Storage's own upsert and list defaults to the service ([#1847](https://github.com/supabase/supabase-swift/issues/1847)) ([cd2c893](https://github.com/supabase/supabase-swift/commit/cd2c8938be588844b50688358cab5fb938cfb278))
* **storage:** report each upload's error from resumeAll ([#1850](https://github.com/supabase/supabase-swift/issues/1850)) ([53509e0](https://github.com/supabase/supabase-swift/commit/53509e07106481b37771883281b391b853a88033))
* **storage:** send values to the service instead of checking them first ([#1839](https://github.com/supabase/supabase-swift/issues/1839)) ([531793d](https://github.com/supabase/supabase-swift/commit/531793db66c903c700ff82a1bda2fff69e8e41be))
* **storage:** send with_delimiter on list-v2 only when the caller sets it ([#1855](https://github.com/supabase/supabase-swift/issues/1855)) ([b8a58cc](https://github.com/supabase/supabase-swift/commit/b8a58cc3e84319df34c54a38823424e408104481))
* **storage:** send x-upsert on every tus request and stop looping on duplicates ([#1854](https://github.com/supabase/supabase-swift/issues/1854)) ([24bb048](https://github.com/supabase/supabase-swift/commit/24bb0484246cb69a502919ea5d82244e29582af1))
* **supabase:** apply the URLSession delegate to the Realtime WebSocket ([#1862](https://github.com/supabase/supabase-swift/issues/1862)) ([accd70a](https://github.com/supabase/supabase-swift/commit/accd70ad06259a40c603bf0ddd55273ab4afbdd7))


### Code Refactoring

* **supabase:** one http, logger and clock for every sub-client ([#1858](https://github.com/supabase/supabase-swift/issues/1858)) ([1a2d26b](https://github.com/supabase/supabase-swift/commit/1a2d26b585ee4d92ac9daf879f5337b594ef52f6))

## [3.0.0-alpha.1](https://github.com/supabase/supabase-swift/compare/v2.55.7...v3.0.0-alpha.1) (2026-11-17)


### ⚠ BREAKING CHANGES

* **helpers:** `JSONValue.integer` and `JSONValue.double` are replaced by `JSONValue.number(JSONNumber)`. `1 == 1.0`, `doubleValue` returns a value for integers, and `value` can return a `Decimal`. See V3_MIGRATION.md.
* PostgrestClient.configuration.headers and StorageClient.configuration.headers no longer contain the SDK's default X-Client-Info. Requests still send it.
* **realtime:** the five Realtime boolean settings have new names.
* `AuthError.isRetryable` and `RealtimeError.isRetryable` are no longer public, and `RealtimeError.init` has no `isRetryable:` parameter. Drop the argument; pick the kind that says whether the client may retry.
* **auth:** AdminUserAttributes splits into AdminCreateUser and AdminUpdateUser (createUser(_:), updateUser(id:_:)); UserAttributes is UpdateUser; GenerateLinkParams is GenerateLink and takes userMetadata:; Create/UpdateOAuthClientParams are CreateOAuthClient/UpdateOAuthClient (createClient(_:), updateClient(id:_:)); Create/UpdateCustomProviderParams are CreateCustomProvider/UpdateCustomProvider (update(identifier:_:)); listClients() returns [OAuthClient], and PageParams and ListOAuthClientsPaginatedResponse are removed; revokeGrant(clientID:); OAuthAuthorizationDetailsResponse is OAuthAuthorizationDetailsResult; PostgrestReturningOptions is PostgrestReturning. See docs/migrations/v3/Auth.md and docs/migrations/v3/PostgREST.md.
* **supabase:** `SupabaseClient.Configuration.Realtime.http` is now optional and falls back to `Global.http`. A Realtime transport override now keeps the global middlewares and `TraceContextMiddleware`. `Configuration.Realtime.headers` now win over `Global.headers`.
* one type and one name per concept, in both directions ([#1781](https://github.com/supabase/supabase-swift/issues/1781))
* **realtime:** RealtimeChannel.httpSend sends every configured and global header, including X-Client-Info, on the REST broadcast request.
* `PostgrestClient.Configuration.accessToken` and `FunctionsClient.Configuration.accessToken` are removed. Use `AccessTokenMiddleware` in `http.middlewares`. A provider error no longer reaches the caller raw; read it from `underlyingError`.
* client-side refusals throw AuthError, PostgrestError or RealtimeError of kind .invalidRequest instead of EncodingError, DecodingError or URLError. A refused Realtime upgrade is .unauthorized, .rateLimited or .server instead of .transport. The watchOS block and a non-ws scheme are .invalidRequest instead of .transport. The SPI postgresChanges(for:where:) is async throws.
* the headers above change from [String: String] to HTTPFields, and PostgrestClient.Configuration.defaultHeaders is removed. See V3_MIGRATION.md, docs/migrations/v3/PostgREST.md and docs/migrations/v3/Realtime.md.
* RealtimeClient.heartbeats() no longer replays the latest heartbeat. ResumableUpload (SPI) renames state/states/State/progress to status/statusChanges()/Status/progress().
* SupabaseClient.init, StorageClient.init(configuration:) and FunctionsClient.init(configuration:) are now throwing. Add `try` at each call site.
* the settings above are renamed with no deprecated aliases. See V3_MIGRATION.md, docs/migrations/v3/Auth.md and docs/migrations/v3/Realtime.md.
* `PostgrestClient.Configuration.jsonEncoder`/`jsonDecoder` and `JSONValue.encoder`/`decoder` are no longer public; use `JSONEncoder.supabase()` / `JSONDecoder.supabase()`. Per-call coder parameters are optional. The SPI row-type label is `of:`. See V3_MIGRATION.md.
* every module error has `code: <Module>Error.Code?`; Auth `ErrorCode`/`errorCode`, Realtime `serverCode`, and Storage `serverStatusCode` are renamed or removed. See V3_MIGRATION.md.
* **storage:** @_spi(Experimental) Storage callers must update: vectors.listBuckets(prefix:pageSize:) -> listBuckets(options:), bucket.listIndexes(prefix:pageSize:) -> listIndexes(options:), bucket.index(_:) -> bucket.from(_:), bucket.indexDetails(_:) -> bucket.index(_:), and storage.resumableUploads.pending()/clear() now need `try await`.
* **auth:** uppercase ID, URL, and URI in public names; explicit CodingKeys, no key strategy ([#1757](https://github.com/supabase/supabase-swift/issues/1757))
* **storage:** uppercase ID in public names ([#1756](https://github.com/supabase/supabase-swift/issues/1756))
* **typegen:** emit ID, URL, URI, JWT and OTP in uppercase ([#1758](https://github.com/supabase/supabase-swift/issues/1758))
* AuthAdminClient.users(perPage:) -> UserSequence is now users(pageSize:) -> PageSequence<User, UserPage, Int>, and listUsers(page:perPage:) is listUsers(page:pageSize:). StorageBucket.objects(prefix:options:) returns PageSequence<StorageObject, ObjectPage, String>; ObjectListing and the Storage PageSequence<Page> are removed and ObjectListing.Page is ObjectPage. The experimental Vectors listings return PageSequence, take pageSize instead of maxResults, and page as VectorBucketPage, VectorIndexPage and VectorPage.
* `HTTPErrorResponse.statusCode` is now `status` (`HTTPResponse.Status`). `PostgrestResponse.data` is now `body`, and `PostgrestResponse.response` is split into `status` and `headers`. `DownloadResponse.httpResponse` is split into `status` and `headers`. The inits change to match. Use `status.code` for the `Int`.
* **postgrest:** PostgrestError is now PostgREST.PostgrestError. It is no longer visible through `import Auth`, `Functions`, `Realtime` or `Storage`; import PostgREST or Supabase. ObservationToken is removed.
* **auth:** isAuthRedirect(_:) is async. A redirect that does not open AuthOptions.redirectToURL or the redirectTo of a pending flow is not handled; set redirectToURL.
* **realtime:** a channel no longer becomes .unsubscribed after a server phx_error, and subscribe() no longer throws channelClosedByServer for one. See docs/migrations/v3/Realtime.md.
* **storage,postgrest:** setHeader(name:value:) is now settingHeader(name:value:) on StorageClient, StorageBucket and PostgrestRequestBuilder. The PostgREST builder takes an HTTPField.Name instead of a String.
* the methods above take an `options:` value instead of inline parameters.
* **auth:** a backup restored to another device no longer carries the session. Pass KeychainStorage(accessibility: .afterFirstUnlock, useDataProtectionKeychain: false) to keep the v2 behavior. See docs/migrations/v3/Auth.md.
* **realtime:** on watchOS, apps in a context TN3135 allows (for example audio streaming) must pass URLSessionWebSocketTransport(allowsWatchOSConnections: true) as RealtimeClientOptions.webSocketTransport.
* **auth:** see docs/migrations/v3/Auth.md.
* **realtime:** the channel reads and stream methods no longer need await, and postgresChanges(of:...) is no longer async.
* **auth:** `AuthClient.admin` and `AuthAdmin` are removed. Use `AuthAdminClient(url:serviceRoleKey:)`. `updateUserById(_:attributes:)` is `updateUser(id:attributes:)`, `createUser(attributes:)` is `createUser(_:)`, `deleteUser(id:shouldSoftDelete:)` is `deleteUser(id:softDelete:)`, `inviteUserByEmail(_:data:redirectTo:)` is `inviteUser(email:userMetadata:redirectTo:)`, `listUsers(params:)` is `listUsers(page:perPage:)` and returns `UserPage`, and `generateLink(params:)` is `generateLink(_:)`. `AdminUserAttributes.id` is a `UUID?`, `banDuration` is a `Duration?` (`.zero` lifts a ban), and `GenerateLinkProperties.redirectTo` is a `URL?`. Admin calls no longer use the client's default `redirectToURL`.
* **auth:** MobileOTPType, ResendMobileType, VerifyOTPResponse, EmailChangeConfirmation, ResendMobileResponse, and SSOResponse are replaced; signInWithOTP, verifyOTP, resend, resetPasswordForEmail, and signInWithSSO change shape. See docs/migrations/v3/Auth.md.
* **auth:** the experimental passkey and WebAuthn MFA methods moved and were renamed. See docs/migrations/v3/Auth.md.
* **auth:** the async session property is now session(). setSession(accessToken:refreshToken:) is renamed importSession and no longer emits .tokenRefreshed. refreshSession(refreshToken:) is now refreshSession(); use importSession for tokens from elsewhere. signOut() defaults to .local; pass scope: .global for the old behavior. signOut now throws on 401 and 404, and .global keeps the session when the logout fails. SignOutScope stays an enum.
* **auth:** the MFA `params:` methods and types are removed; see docs/migrations/v3/Auth.md for the mapping. `listFactors()` is `factors()`, `authenticatorAssuranceLevel()` is `assuranceLevel()`, and the MFA string typealiases are structs.
* **deps:** the package now needs swift-crypto 4.0.0 or later.
* **auth:** add v3 user, identity, and claims calls with a per-client JWKS cache ([#1684](https://github.com/supabase/supabase-swift/issues/1684))
* **auth:** one OAuth entry point, WebAuthPresenter, FlowStore, and an idempotent handleRedirect ([#1678](https://github.com/supabase/supabase-swift/issues/1678))
* **auth:** authStateChanges and onAuthStateChange(_:) are replaced by events(). AuthChangeEvent is renamed AuthEvent, and .userDeleted is removed because it was never emitted. AuthStateChangeListener, AuthStateChangeListenerRegistration, didChangeAuthStateNotification, authChangeEventInfoKey, and authChangeSessionInfoKey are removed.
* **auth:** signUp returns SignUpResult and takes SignUpOptions; data: is userMetadata:; OpenIDConnectCredentials is IDTokenCredentials; signInWithIdToken(credentials:) is signInWithIDToken(_:); AuthMetaSecurity is internal. See docs/migrations/v3/Auth.md.
* **auth:** refreshSession and an expired session() can throw a cached error or AuthError.Kind.excessiveRefresh without a request, and callers of a refresh that signOut cancels get CancellationError.
* **supabase:** a data request that gets a 401 is retried once, for every HTTP method, after a refresh when needed.
* **auth:** refreshSession and an expired session() can throw a cached error or AuthError.Kind.excessiveRefresh without a request, and callers of a refresh that signOut cancels get CancellationError.
* **realtime:** RealtimeMessageV2 and PushStatus are no longer public.
* **supabase:** `RealtimeClientOptions.logger` is `Logging.Logger?`, and its default is `nil`.
* **auth:** refreshSession and an expired session() can throw a cached error or AuthError.Kind.excessiveRefresh without a request, and callers of a refresh that signOut cancels get CancellationError.
* **realtime:** RealtimePostgresFilterValue requires realtimeFilterValue instead of rawValue, and conforming types must be Sendable.
* **realtime:** RealtimeClientOptions.logLevel and LogLevel are now serverLogLevel and RealtimeServerLogLevel, and .warn is .warning.
* **auth:** `AuthClient.Configuration.automaticallyRefreshesToken`, `defaultAutomaticallyRefreshesToken`, and `SupabaseClientOptions.AuthOptions.automaticallyRefreshesToken` are replaced by `autoRefresh`. `startAutoRefresh()` and `stopAutoRefresh()` are async. Auto refresh starts with the client on every platform, and `linkIdentity` without `launchURL` throws where the platform cannot open a URL. See docs/migrations/v3/Auth.md.
* **realtime:** broadcasts(event:) yields BroadcastMessage instead of JSONObject, and its payload holds only the sender's payload. broadcastData(event:), InsertAction, UpdateAction, DeleteAction, AnyAction, PostgresAction, HasRecord, HasOldRecord and Column are removed. Payload decode failures throw RealtimeError with kind .decoding. See docs/migrations/v3/Realtime.md.
* **auth:** the client judges expiry from the local receipt time, not from expiresAt against the device clock. startAutoRefresh() no longer polls every 30 s.
* **auth:** refreshSession() can throw .sessionInvalidated while the session stays signed in. React to the .signedOut event to show sign-in.
* **auth:** refreshSession and an expired session() can throw a cached error or AuthError.Kind.excessiveRefresh without a request, and callers of a refresh that signOut cancels get CancellationError.
* **realtime:** PresenceV2 and PresenceAction are removed. presenceChanges() now yields PresenceChange, track(state:) is replaced by track(_:encoder:), and track and untrack wait for the server reply even when acknowledgeBroadcasts is off. See docs/migrations/v3/Realtime.md.
* **realtime:** RealtimeClientStatus and RealtimeChannelStatus are enums with associated values and are not Equatable. The client reports `.reconnecting` while it waits to reconnect, and a channel whose subscribe failed reports `.failed`. HeartbeatStatus is replaced by HeartbeatEvent, `systemMessages()` by `events()`. RealtimeMessageV2.EventType and `eventType` are removed, and ChannelEvent is no longer public. See docs/migrations/v3/Realtime.md.
* **realtime:** `RealtimeClientOptions(maxRetryAttempts:)`, `RealtimeClientOptions.defaultMaxRetryAttempts`, `RealtimeError.Kind.maxRetryAttemptsReached` and `RealtimeError.maxRetryAttemptsReached` are removed. `subscribe()` has no attempt limit: it retries until the join succeeds, fails for good, or its task is cancelled. A fatal join error or a refused upgrade throws at once. With `connectOnSubscribe` off and no connection, `subscribe()` throws `.notConnected` at once.
* **auth:** storage errors now surface instead of reading as signed out, the stored session is read once per client, two clients for one project and storage key share the session, and auth events are delivered asynchronously. See docs/migrations/v3/Auth.md.
* **auth:** when the server rejects the session or refresh token (refresh_token_not_found, refresh_token_already_used, session_expired, session_not_found, user_banned, or invalid_grant on refresh), AuthError has kind .sessionInvalidated instead of .sessionMissing. .sessionMissing now means only that no session is stored.
* **realtime:** `defaultReconnectDelay` is 1 s (was 7 s) and the n-th reconnect wait is drawn from `0...min(30s, reconnectDelay * 2^(n-1))`. A reconnect refused with HTTP 401/403/404 ends in `.disconnected`. `connect()` called during a reconnect attempts at once instead of waiting for it.
* **realtime:** track(_:) and untrack() are rate limited to one call per six seconds per channel, and the channel re-tracks after a rejoin. A presence_diff that arrives before the first presence_state is delivered after it.
* **realtime:** `RealtimeClientV2`/`RealtimeChannelV2` are renamed to `RealtimeClient`/`RealtimeChannel` and are actors. Callback APIs and `RealtimeSubscription` are removed in favor of `AsyncStream`s. A WebSocket `broadcast` on a channel that is not subscribed no longer falls back to the REST endpoint; use `httpSend`. See docs/migrations/v3/Realtime.md.
* **realtime:** `statusSnapshot` is removed; `statusChanges` and `heartbeats` are now `async` methods.
* **realtime:** `broadcast`, `track` and `untrack` are `async throws` and return `Void`; `PushHandle` and `PushStatus.timeout` are removed.
* **realtime:** `RealtimeClientV2`/`RealtimeChannelV2` are renamed to `RealtimeClient`/`RealtimeChannel` and are actors. Callback APIs and `RealtimeSubscription` are removed in favor of `AsyncStream`s. A WebSocket `broadcast` on a channel that is not subscribed no longer falls back to the REST endpoint; use `httpSend`. See docs/migrations/v3/Realtime.md.
* **storage:** BucketOptions is replaced by CreateBucketOptions and UpdateBucketOptions. See V3_MIGRATION.md.
* **storage:** purgeCache(bucket:transformationsOnly:) and purgeCache(path:transformationsOnly:) are now purgeCache(bucket:includingTransformations:) and purgeCache(path:includingTransformations:).
* **storage:** copy returns UploadedObject instead of String; see V3_MIGRATION.md.
* **storage:** DestinationOptions is removed; see V3_MIGRATION.md.
* **storage:** Bucket.owner is removed; read Bucket.ownerId. See V3_MIGRATION.md.
* **storage:** SearchOptions and SortBy are removed; see V3_MIGRATION.md.
* **storage:** download returns DownloadResponse instead of Data; add .data() to keep the old result. See V3_MIGRATION.md.
* **storage:** download's query: and cacheNonce: parameters are replaced by DownloadOptions. See V3_MIGRATION.md.
* **storage:** `StorageClientConfiguration.headers` is `HTTPFields`, and `setHeader(_:forKey:)` is `setHeader(name:value:)`.
* **storage:** download: String? overloads, SignedURL and CreateSignedUploadURLOptions are removed; publicURL is non-throwing. See V3_MIGRATION.md.
* **storage:** BucketOptions fields are optional, StorageByteCount is ByteCount, and updateBucket no longer resets fields you did not pass. See V3_MIGRATION.md.
* **storage:** FileObject is StorageObject, FileObjectV2 is ObjectInfo, FileUploadResponse and SignedURLUploadResponse are UploadedObject, and metadata is typed. See V3_MIGRATION.md.
* **storage:** createSignedURL and createSignedURLs take expiresIn: Duration instead of Int. See V3_MIGRATION.md.
* **storage:** TransformOptions is ImageTransform and the argument label is transform: on download and publicURL. See V3_MIGRATION.md.
* **storage:** FileOptions is UploadOptions. See V3_MIGRATION.md.
* **storage:** StorageError.ServerError.statusCode is Int? instead of String?. See V3_MIGRATION.md.
* **storage:** SupabaseStorageClient is StorageClient and StorageFileApi is StorageBucket. See V3_MIGRATION.md.
* **postgrest:** the typed-API types are renamed with a `_` prefix, and a typed query needs `@_spi(Experimental) import Supabase`. See V3_MIGRATION.md.
* **realtime:** `RealtimeClientOptions(vsn:)`/`protocolVersion:` and `RealtimeProtocolVersion` are removed; `RealtimeMessageV2` no longer conforms to `Codable`. Requires Realtime server v2.63.0 or later. See V3_MIGRATION.md.
* **storage:** throw CancellationError when the caller's task is cancelled ([#1434](https://github.com/supabase/supabase-swift/issues/1434))
* **supabase:** `SupabaseClient` no longer overwrites a per-request `Authorization` header on PostgREST, Storage or Functions requests, and its `ClientMiddleware`s see those requests without the bearer. `FunctionsOptions.init(region: String?)` is removed. See `V3_MIGRATION.md`.
* **functions:** `_invokeWithStreamedResponse` is removed; iterating an `HTTPBody` from a cancelled task throws `CancellationError`. See `V3_MIGRATION.md`.
* **functions:** rebuild the module around Configuration, FunctionBody and FunctionResponse ([#1443](https://github.com/supabase/supabase-swift/issues/1443))
* **functions,realtime:** throw CancellationError when the caller's task is cancelled ([#1442](https://github.com/supabase/supabase-swift/issues/1442))
* **postgrest:** the three typed wrapper types are renamed. See V3_MIGRATION.md.
* **postgrest:** the three typed wrapper types are renamed. See V3_MIGRATION.md.
* **postgrest:** order() no longer forces NULLS LAST by default ([#1417](https://github.com/supabase/supabase-swift/issues/1417))
* **postgrest:** insert and upsert on the string-based builder return PostgrestTransformBuilder instead of PostgrestFilterBuilder. See V3_MIGRATION.md.
* SDK async functions now run on the caller's executor, and ClientMiddleware conformances in modules without the flag must spell `next` as nonisolated(nonsending). See V3_MIGRATION.md.
* **postgrest:** the three typed wrapper types are renamed. See V3_MIGRATION.md.
* exhaustive switches over the seven types above need a default: case, init(rawValue:) is no longer failable, and direct string interpolation prints the struct description instead of the case name.
* **realtime:** RealtimeClientOptions intervals and the httpSend timeout are Duration; timeoutInterval is now timeout and defaultTimeoutInterval is now defaultTimeout. See V3_MIGRATION.md.
* **auth:** AuthMFAChallengeResponse.id and MFAVerifyParams.challengeId change from String to UUID. See V3_MIGRATION.md.
* **realtime:** fold RealtimeError.Kind.connection into transport ([#1407](https://github.com/supabase/supabase-swift/issues/1407))
* **auth:** reduce AuthError.Kind from 12 values to 7 ([#1406](https://github.com/supabase/supabase-swift/issues/1406))
* **postgrest:** fold PostgrestError.Kind.unexpectedResponse into server and decoding ([#1405](https://github.com/supabase/supabase-swift/issues/1405))
* **storage:** fold StorageError.Kind.unexpectedResponse into server; rename invalidURL to invalidRequest ([#1404](https://github.com/supabase/supabase-swift/issues/1404))
* **functions:** rename FunctionsError.Kind.http to server ([#1403](https://github.com/supabase/supabase-swift/issues/1403))
* **postgrest:** name a relation's schema with a type ([#1372](https://github.com/supabase/supabase-swift/issues/1372))
* **storage:** Storage upload requests are no longer multipart/form-data. Public Swift API is unchanged; middleware, proxies, or fixtures that match on the multipart body must read the raw body and the x-metadata header instead. See V3_MIGRATION.md.
* **auth:** `AuthClient` is a `final class`, not an `actor`. See V3_MIGRATION.md.
* **storage:** align remaining API with the Swift API Design Guidelines ([#1368](https://github.com/supabase/supabase-swift/issues/1368))
* `get`-prefixed accessors, identifier argument labels, boolean property names, `RealtimeClientOptions.vsn` and `User.aud` have all been renamed. See V3_MIGRATION.md.
* retry timing changes for every module (jitter instead of a fixed schedule; Auth makes 3 attempts instead of 2), Storage and Functions start retrying transient failures by default, and only `URLError` counts as a retryable transport failure. See V3_MIGRATION.md.
* **helpers:** `URLSessionTransport` returns a 307/308 response as-is when the request body is `.single`, and fails a `.known` streamed body whose byte count does not match. See V3_MIGRATION.md.
* `FunctionInvokeOptions.init(... timeoutInterval: TimeInterval?)` is now `timeout: Duration?`, and `FunctionsClient.requestIdleTimeout` is a `Duration`. See V3_MIGRATION.md.
* **auth:** OAuthClient.redirectUris, OAuthClient.grantTypes and OAuthClient.responseTypes are optional.
* **auth:** OAuthClient.clientName, OAuthAuthorizationClient.name, OAuthAuthorizationUser.email and OAuthAuthorizationDetails.scope are now String? instead of String. See V3_MIGRATION.md.
* **realtime:** public RealtimeError with kind; remove WebSocketError and NSError placeholders ([#1338](https://github.com/supabase/supabase-swift/issues/1338))
* **auth:** make AuthError a struct with kind, HTTP context and wrapped failures ([#1337](https://github.com/supabase/supabase-swift/issues/1337))
* **postgrest:** make PostgrestError a wrapper with ServerError payload; remove HTTPError ([#1336](https://github.com/supabase/supabase-swift/issues/1336))
* **storage:** make StorageError a struct with kind, server payload and HTTP context ([#1335](https://github.com/supabase/supabase-swift/issues/1335))
* **functions:** make FunctionsError a struct with kind and HTTP context ([#1334](https://github.com/supabase/supabase-swift/issues/1334))
* `HTTPError.response`, `PostgrestResponse.response`, `AuthError.api(underlyingResponse:)` and `FunctionsClient.invoke(decode:)` carry `HTTPTypes.HTTPResponse` instead of `HTTPURLResponse`. See V3_MIGRATION.md.
* `GlobalOptions.init` has no `session:` parameter and `GlobalOptions.session` is removed. See V3_MIGRATION.md.
* `AuthError` gains `oauthFlowFailed(message:)`, which breaks exhaustive switches over `AuthError`. See V3_MIGRATION.md.
* **postgrest:** no public symbol moved module, changed shape, or was renamed, and no call site needs editing. What changed is the guarantee: PostgREST's pre-v3 builders stop receiving behavior fixes as of this release, are deprecated later in v3, and are removed in v4. See V3_MIGRATION.md.
* **postgrest:** `Optional` no longer conforms to `PostgrestFilterValue`. Use `is(_:value:)` to test for NULL. See V3_MIGRATION.md.
* **postgrest,realtime:** standardize per-call encoder/decoder overrides ([#1248](https://github.com/supabase/supabase-swift/issues/1248))
* **storage:** drop encoder/decoder customization ([#1247](https://github.com/supabase/supabase-swift/issues/1247))
* **storage:** make Storage client types stateless structs ([#1246](https://github.com/supabase/supabase-swift/issues/1246))
* **postgrest:** make client and builders stateless value types ([#1240](https://github.com/supabase/supabase-swift/issues/1240))
* **functions:** make FunctionsClient stateless and a struct ([#1233](https://github.com/supabase/supabase-swift/issues/1233))
* **auth:** always emit locally stored session as initial session ([#1214](https://github.com/supabase/supabase-swift/issues/1214))
* **helpers:** rename AnyJSON to JSONValue ([#1232](https://github.com/supabase/supabase-swift/issues/1232))
* **functions:** convert FunctionInvokeOptions.Method to a RawRepresentable struct ([#1229](https://github.com/supabase/supabase-swift/issues/1229))
* **postgrest:** convert TextSearchType to a RawRepresentable struct ([#1228](https://github.com/supabase/supabase-swift/issues/1228))
* **postgrest:** convert PostgrestReturningOptions to a RawRepresentable struct ([#1227](https://github.com/supabase/supabase-swift/issues/1227))
* **postgrest:** convert CountOption to a RawRepresentable struct ([#1226](https://github.com/supabase/supabase-swift/issues/1226))
* **postgrest:** convert PostgrestFilterBuilder.Operator to a RawRepresentable struct ([#1225](https://github.com/supabase/supabase-swift/issues/1225))
* **auth:** convert SignOutScope to a RawRepresentable struct ([#1224](https://github.com/supabase/supabase-swift/issues/1224))
* **auth:** convert ResendMobileType to a RawRepresentable struct ([#1223](https://github.com/supabase/supabase-swift/issues/1223))
* **auth:** convert ResendEmailType to a RawRepresentable struct ([#1222](https://github.com/supabase/supabase-swift/issues/1222))
* **auth:** convert EmailOTPType to a RawRepresentable struct ([#1221](https://github.com/supabase/supabase-swift/issues/1221))
* **auth:** convert MobileOTPType to a RawRepresentable struct ([#1220](https://github.com/supabase/supabase-swift/issues/1220))
* **auth:** convert OpenIDConnectCredentials.Provider to a RawRepresentable struct ([#1219](https://github.com/supabase/supabase-swift/issues/1219))
* **auth:** convert Provider to a RawRepresentable struct ([#1217](https://github.com/supabase/supabase-swift/issues/1217))
* **auth:** convert MessagingChannel to a RawRepresentable struct ([#1216](https://github.com/supabase/supabase-swift/issues/1216))
* **auth:** convert FactorStatus to a RawRepresentable struct ([#1215](https://github.com/supabase/supabase-swift/issues/1215))
* **auth:** fix macOS Keychain consent prompt and storage contract ([#1208](https://github.com/supabase/supabase-swift/issues/1208))
* **auth:** drop LocalStorage implementation for Windows platform ([#1213](https://github.com/supabase/supabase-swift/issues/1213))
* **auth,storage,realtime,helpers:** narrow Codable conformances to their actual usage direction ([#1209](https://github.com/supabase/supabase-swift/issues/1209))
* SupabaseLogger, SupabaseLogMessage, SupabaseLogLevel, SupabaseLoggerTaskLocal, and OSLogSupabaseLogger are removed. Use Logging.Logger (swift-log) directly. See V3_MIGRATION.md.
* remove all deprecated pre-v3 APIs ([#1206](https://github.com/supabase/supabase-swift/issues/1206))
* **auth:** `AuthResponse.user` is now `User?` instead of `User`. Update call sites that access `response.user` directly to handle the optional (e.g. `response.user?.email`).
* ) must touch a file under docs/migrations/.

### Features

* **auth:** add a standalone AuthAdmin initializer ([#1397](https://github.com/supabase/supabase-swift/issues/1397)) ([613bb73](https://github.com/supabase/supabase-swift/commit/613bb73c2aca6a537ccb4f6282a62d4e6508a60d))
* **auth:** add admin MFA factor listing and deletion ([#1357](https://github.com/supabase/supabase-swift/issues/1357)) ([308d53b](https://github.com/supabase/supabase-swift/commit/308d53bd7597a8f4c193e628ac0911b9d01cf811))
* **auth:** add an AsyncSequence paginator over admin listUsers ([#1352](https://github.com/supabase/supabase-swift/issues/1352)) ([e8f9cd7](https://github.com/supabase/supabase-swift/commit/e8f9cd7ba1fa7d0ff31d49d846d57cb2297e26ca))
* **auth:** add async AuthStorage with in-memory and Keychain storage ([#1624](https://github.com/supabase/supabase-swift/issues/1624)) ([9b83cad](https://github.com/supabase/supabase-swift/commit/9b83cadc27d899f41ef20732000a93d9eb11b735))
* **auth:** add AuthModel, an @Observable mirror of the auth status for SwiftUI ([#1713](https://github.com/supabase/supabase-swift/issues/1713)) ([1d6b533](https://github.com/supabase/supabase-swift/commit/1d6b533d7614b68b715481783275f385aec841f5))
* **auth:** add MFA recovery codes ([#1380](https://github.com/supabase/supabase-swift/issues/1380)) ([c115df0](https://github.com/supabase/supabase-swift/commit/c115df05b76a8e0146f25df7eb7514d224eaa7fe))
* **auth:** add v3 user, identity, and claims calls with a per-client JWKS cache ([#1684](https://github.com/supabase/supabase-swift/issues/1684)) ([040d4d4](https://github.com/supabase/supabase-swift/commit/040d4d433510dad079f815e53a0dad0c624efd9b))
* **auth:** add WebAuthenticationSessionPresenter for SwiftUI ([#1800](https://github.com/supabase/supabase-swift/issues/1800)) ([699475b](https://github.com/supabase/supabase-swift/commit/699475bcc17d3cfbf1202d61f4ba235f3e33b5d8))
* **auth:** cancel the web auth session with the task and listen for HTTPS callbacks ([#1720](https://github.com/supabase/supabase-swift/issues/1720)) ([d5cbd84](https://github.com/supabase/supabase-swift/commit/d5cbd84d8faec87fa24bfa4b1574cf815bfdef78))
* **auth:** clean up Configuration and use Date and Duration in the public model ([#1718](https://github.com/supabase/supabase-swift/issues/1718)) ([b653731](https://github.com/supabase/supabase-swift/commit/b65373121076191cb93aeda0155e13fba8f656e2))
* **auth:** decode the three GoTrue error shapes in ErrorDecoder ([#1623](https://github.com/supabase/supabase-swift/issues/1623)) ([a44f7b1](https://github.com/supabase/supabase-swift/commit/a44f7b1a396f5b5a07cecba72852c335b4d9ff76))
* **auth:** flatten the MFA API and make MFA values open-set structs ([#1686](https://github.com/supabase/supabase-swift/issues/1686)) ([292e802](https://github.com/supabase/supabase-swift/commit/292e802f42bac24d51cd35e10944c0a1be78698e))
* **auth:** keep the Keychain session on this device and update its accessibility in place ([#1726](https://github.com/supabase/supabase-swift/issues/1726)) ([d735266](https://github.com/supabase/supabase-swift/commit/d7352667ecf8bd5a3ed100644027ded1362563c6))
* **auth:** make AuthError a struct with kind, HTTP context and wrapped failures ([#1337](https://github.com/supabase/supabase-swift/issues/1337)) ([cd5cbf4](https://github.com/supabase/supabase-swift/commit/cd5cbf4a1bd907df43d634e0789b27a59b78a220))
* **auth:** one OAuth entry point, WebAuthPresenter, FlowStore, and an idempotent handleRedirect ([#1678](https://github.com/supabase/supabase-swift/issues/1678)) ([bee7e48](https://github.com/supabase/supabase-swift/commit/bee7e48f83b6ed0b4bb5c07927cfc9d2e7948d2b))
* **auth:** public AuthStatus, AuthEvent, AuthChange, SignOutReason, and a lossless events() stream ([#1674](https://github.com/supabase/supabase-swift/issues/1674)) ([ddeb307](https://github.com/supabase/supabase-swift/commit/ddeb3071d371ad5aa32c43b7e13c8976962f5f3a))
* **auth:** redact secrets from Auth logs, signpost refresh, name Auth tasks ([#1717](https://github.com/supabase/supabase-swift/issues/1717)) ([d8b97f9](https://github.com/supabase/supabase-swift/commit/d8b97f95734a07bf142f1e576f3d58c2e0c83274))
* **auth:** reduce AuthError.Kind from 12 values to 7 ([#1406](https://github.com/supabase/supabase-swift/issues/1406)) ([2e2e31a](https://github.com/supabase/supabase-swift/commit/2e2e31a1f950e1886f442271d0055182c383eabb))
* **auth:** refresh an expired stored session once before delivering .initialSession ([#1711](https://github.com/supabase/supabase-swift/issues/1711)) ([b7a2c3b](https://github.com/supabase/supabase-swift/commit/b7a2c3bc61d4082d57c0ff7741e5b5be133961e4))
* **auth:** refresh the session on a deadline from the local receipt time ([#1636](https://github.com/supabase/supabase-swift/issues/1636)) ([493c061](https://github.com/supabase/supabase-swift/commit/493c0614568763dcca4881c6e4377b7ece66234b))
* **auth:** regroup passkeys under client.passkeys and client.mfa ([#1680](https://github.com/supabase/supabase-swift/issues/1680)) ([4cda59a](https://github.com/supabase/supabase-swift/commit/4cda59a93ddf1e4477e90e56e495f608304b33bf))
* **auth:** session() and importSession, and signOut defaulting to .local per the sign-out spec ([#1679](https://github.com/supabase/supabase-swift/issues/1679)) ([e8a76b1](https://github.com/supabase/supabase-swift/commit/e8a76b104f75c7421d2374ad89988a39ec7adbeb))
* **auth:** sign out only when a rejected refresh leaves an expired session ([#1635](https://github.com/supabase/supabase-swift/issues/1635)) ([d17ce1f](https://github.com/supabase/supabase-swift/commit/d17ce1f7e265ed8109c9d707cd027f3fbe876465))
* **auth:** sign-up and sign-in verbs with named results, userMetadata, and IDTokenCredentials ([#1673](https://github.com/supabase/supabase-swift/issues/1673)) ([eafbaf9](https://github.com/supabase/supabase-swift/commit/eafbaf99ea47f80cec067ae724e2e22ca574519c))
* **auth:** standalone AuthAdminClient with customProviders ([#1710](https://github.com/supabase/supabase-swift/issues/1710)) ([3356c75](https://github.com/supabase/supabase-swift/commit/3356c75154aea77e0f6c3d8c5b4b008c1f3528d7))
* **auth:** start auto refresh with the client and follow the app lifecycle ([#1637](https://github.com/supabase/supabase-swift/issues/1637)) ([776c4df](https://github.com/supabase/supabase-swift/commit/776c4df1a88b409bf0b51866264ef88fd1fdd0a8))
* **auth:** support concurrent PKCE flows via flow id ([#1245](https://github.com/supabase/supabase-swift/issues/1245)) ([e7b2325](https://github.com/supabase/supabase-swift/commit/e7b2325cd6938ac6faa0ca0dba6df28615e3abf0))
* **auth:** treat a locked Keychain as storage unavailable, not signed out ([#1638](https://github.com/supabase/supabase-swift/issues/1638)) ([0de6ec3](https://github.com/supabase/supabase-swift/commit/0de6ec3a7d55176c92c5ca6e0b906535c60de2f0))
* **auth:** typed OTP kinds, VerifyOTPResult, resetPassword(email:), and SSO through a presenter ([#1688](https://github.com/supabase/supabase-swift/issues/1688)) ([f181ff4](https://github.com/supabase/supabase-swift/commit/f181ff4b3ae3bced49f452392fa846a4eb0a1d79))
* **auth:** verify ES256 JWTs locally in getClaims ([#1316](https://github.com/supabase/supabase-swift/issues/1316)) ([ef14b8b](https://github.com/supabase/supabase-swift/commit/ef14b8bfac48dfcaa00baef20661d3f84db69c4c))
* **client:** add db.retry option to disable PostgREST retries ([#1244](https://github.com/supabase/supabase-swift/issues/1244)) ([894ad20](https://github.com/supabase/supabase-swift/commit/894ad20c248b380b654f6c8546809eb98945a69f))
* **examples:** resumable upload screen with pause, resume, cancel ([#1554](https://github.com/supabase/supabase-swift/issues/1554)) ([181a0c0](https://github.com/supabase/supabase-swift/commit/181a0c0a00070700e08c0c3b45f7dfce67eb0209))
* expose clock injection and set explicit AsyncStream buffering policies ([#1351](https://github.com/supabase/supabase-swift/issues/1351)) ([25e1865](https://github.com/supabase/supabase-swift/commit/25e1865d6bf16a3c927c83368f89cbb7ab2a4d45))
* expose one public transport protocol and middleware chain across all modules ([#1325](https://github.com/supabase/supabase-swift/issues/1325)) ([a83b4b2](https://github.com/supabase/supabase-swift/commit/a83b4b2f18ac90f6a0e5ce9a56512d3ca7b851d8))
* **functions:** make FunctionsError a struct with kind and HTTP context ([#1334](https://github.com/supabase/supabase-swift/issues/1334)) ([333afd6](https://github.com/supabase/supabase-swift/commit/333afd68b9268d4a96512f66dcbe099c8266e216))
* **functions:** rebuild the module around Configuration, FunctionBody and FunctionResponse ([#1443](https://github.com/supabase/supabase-swift/issues/1443)) ([e243735](https://github.com/supabase/supabase-swift/commit/e2437359296003886d99ceecce37b9ec4d238928))
* **functions:** rename FunctionsError.Kind.http to server ([#1403](https://github.com/supabase/supabase-swift/issues/1403)) ([0a380b9](https://github.com/supabase/supabase-swift/commit/0a380b9b05376fbcded3ee99f63d6d6d45cc4f85))
* **functions:** stream(_:body:options:) returns FunctionStreamResponse ([#1445](https://github.com/supabase/supabase-swift/issues/1445)) ([e14e038](https://github.com/supabase/supabase-swift/commit/e14e03870dce131faa1416362f3ed68107c4bf93))
* **helpers:** add immediate tasks, TaskStorage, and a non-Sendable withTimeout ([#1590](https://github.com/supabase/supabase-swift/issues/1590)) ([83a7fda](https://github.com/supabase/supabase-swift/commit/83a7fda4d302f7db46d20e5cc437369228cc2275))
* **helpers:** add SupabaseError root and HTTPErrorResponse ([#1333](https://github.com/supabase/supabase-swift/issues/1333)) ([4da4dd2](https://github.com/supabase/supabase-swift/commit/4da4dd2670e284a92bd0e1586b31a80daf21dc22))
* **helpers:** HTTPBody.write(to:) replaces the file atomically ([#1533](https://github.com/supabase/supabase-swift/issues/1533)) ([8c57db0](https://github.com/supabase/supabase-swift/commit/8c57db09ce402a765da5d26d0fd83e584fa59180))
* **helpers:** report real upload progress on Linux ([#1437](https://github.com/supabase/supabase-swift/issues/1437)) ([4e5c9f9](https://github.com/supabase/supabase-swift/commit/4e5c9f9abea94d7d604f149a55395dcfdd0b2edf))
* make the request timeout configurable per client and per call ([#1343](https://github.com/supabase/supabase-swift/issues/1343)) ([35ca100](https://github.com/supabase/supabase-swift/commit/35ca1003db3a5f20d516fc2935844de19ceab715))
* **postgrest,realtime:** standardize per-call encoder/decoder overrides ([#1248](https://github.com/supabase/supabase-swift/issues/1248)) ([4f7d8a8](https://github.com/supabase/supabase-swift/commit/4f7d8a8c9b14c4fd45418ad7cc625c7a5886b9aa))
* **postgrest:** accept a collection of rows in typed insert and upsert ([#1306](https://github.com/supabase/supabase-swift/issues/1306)) ([fbf2bb7](https://github.com/supabase/supabase-swift/commit/fbf2bb7319e665c3e62caba180d204124bc32b6b))
* **postgrest:** accept Decimal, Float and sized integers as filter values ([#1346](https://github.com/supabase/supabase-swift/issues/1346)) ([3f2f8da](https://github.com/supabase/supabase-swift/commit/3f2f8da3317f342c7f485725c741f1b59b901bd9))
* **postgrest:** add @Aggregate for aggregates in @SelectionOf ([#1495](https://github.com/supabase/supabase-swift/issues/1495)) ([b94247b](https://github.com/supabase/supabase-swift/commit/b94247b46fc079bc068cee375550fbc5d13ba0ea))
* **postgrest:** add @Function and the typed rpc(_:) ([#1470](https://github.com/supabase/supabase-swift/issues/1470)) ([acf367a](https://github.com/supabase/supabase-swift/commit/acf367a1e43e131b47403f7fb8ef9c84e45b59ea))
* **postgrest:** add @Generated for columns the database refuses to be written ([#1469](https://github.com/supabase/supabase-swift/issues/1469)) ([c976846](https://github.com/supabase/supabase-swift/commit/c9768464eef24b74a7d3e08b33ede6ac918110de))
* **postgrest:** add @Relationship and embeds in selections ([#1307](https://github.com/supabase/supabase-swift/issues/1307)) ([1689765](https://github.com/supabase/supabase-swift/commit/16897652032664e3836746decc7614dcaf89a6ea))
* **postgrest:** add @SelectionOf for column subsets ([#1260](https://github.com/supabase/supabase-swift/issues/1260)) ([f47933e](https://github.com/supabase/supabase-swift/commit/f47933e7767f79135961c72ca458be517707ea88))
* **postgrest:** add actionable macro diagnostics ([#1261](https://github.com/supabase/supabase-swift/issues/1261)) ([8ee0a6b](https://github.com/supabase/supabase-swift/commit/8ee0a6bf3aefbdbd7c7bc61dfa181031c13d0bb2))
* **postgrest:** add aggregate functions as select-only expressions ([#1294](https://github.com/supabase/supabase-swift/issues/1294)) ([4d944f7](https://github.com/supabase/supabase-swift/commit/4d944f72554a47ca4b904f607a68882f5202040d))
* **postgrest:** add casts and JSON paths as column expressions ([#1293](https://github.com/supabase/supabase-swift/issues/1293)) ([1852b9e](https://github.com/supabase/supabase-swift/commit/1852b9e0122b2d05f696c8d4b2b16cd5e98f54b6))
* **postgrest:** add column expressions and the filter tree ([#1288](https://github.com/supabase/supabase-swift/issues/1288)) ([b6bfaa6](https://github.com/supabase/supabase-swift/commit/b6bfaa6258451e9cf9d54ee199055dc0ac6cc940))
* **postgrest:** add comparison operators for typed filters ([#1499](https://github.com/supabase/supabase-swift/issues/1499)) ([0c452a6](https://github.com/supabase/supabase-swift/commit/0c452a641438ea8e36132c352c6b3860515edb43))
* **postgrest:** add count and head to the typed surface ([#1305](https://github.com/supabase/supabase-swift/issues/1305)) ([13132e3](https://github.com/supabase/supabase-swift/commit/13132e31961276783d96f3ad8b61093271fafd3e))
* **postgrest:** add defaultToNull to insert and upsert ([#1311](https://github.com/supabase/supabase-swift/issues/1311)) ([37e7464](https://github.com/supabase/supabase-swift/commit/37e7464ef0412235ede06aeae5995c6751e67e91))
* **postgrest:** add embedded relations to the column namespace ([#1295](https://github.com/supabase/supabase-swift/issues/1295)) ([4253a08](https://github.com/supabase/supabase-swift/commit/4253a08a0002e2bbc6a76c759222afdd4f52edd6))
* **postgrest:** add from(_ type:) and a typed whole-row select ([#1253](https://github.com/supabase/supabase-swift/issues/1253)) ([52eec30](https://github.com/supabase/supabase-swift/commit/52eec30c20207cd32d389be01f4a9d9518c99459))
* **postgrest:** add key-path filters and modifiers to the typed query ([#1254](https://github.com/supabase/supabase-swift/issues/1254)) ([d177ab6](https://github.com/supabase/supabase-swift/commit/d177ab646b0ab02a2061d2d7d719ebabbdf83aef))
* **postgrest:** add maxAffected and dryRun to the typed mutation ([#1426](https://github.com/supabase/supabase-swift/issues/1426)) ([e73d6d0](https://github.com/supabase/supabase-swift/commit/e73d6d0e4036d96212b673a25a5ee9959a782438))
* **postgrest:** add range to the typed query ([#1318](https://github.com/supabase/supabase-swift/issues/1318)) ([9d28f22](https://github.com/supabase/supabase-swift/commit/9d28f22f8af312f751cffcb29fb1af1e20b4adb9))
* **postgrest:** add the @Table macro and its marker attributes ([#1259](https://github.com/supabase/supabase-swift/issues/1259)) ([7a2c450](https://github.com/supabase/supabase-swift/commit/7a2c450157819997dc1d70d4e3a4880a1c3ac6bd))
* **postgrest:** add the embedded and requiring scope ([#1458](https://github.com/supabase/supabase-swift/issues/1458)) ([e52251e](https://github.com/supabase/supabase-swift/commit/e52251ea9569fb207cbcc5396f8ddbc25fa22405))
* **postgrest:** add the PostgrestMacros targets ([#1258](https://github.com/supabase/supabase-swift/issues/1258)) ([c26da5b](https://github.com/supabase/supabase-swift/commit/c26da5bdf52d3c356052f144f83cd66903ec2705))
* **postgrest:** add the relation and selection protocols ([#1252](https://github.com/supabase/supabase-swift/issues/1252)) ([f2f37d2](https://github.com/supabase/supabase-swift/commit/f2f37d2e11aadf1d75e42bc4f804b0468d8e55c5))
* **postgrest:** add the remaining filter operators ([#1289](https://github.com/supabase/supabase-swift/issues/1289)) ([2638f4a](https://github.com/supabase/supabase-swift/commit/2638f4ac95b26cc6e704cac4290a18063856448e))
* **postgrest:** add the where and order closures ([#1291](https://github.com/supabase/supabase-swift/issues/1291)) ([8345ea0](https://github.com/supabase/supabase-swift/commit/8345ea01da3c05e0636f25b144a9353b2796587c))
* **postgrest:** add typed writes gated on the writable refinement ([#1255](https://github.com/supabase/supabase-swift/issues/1255)) ([b595383](https://github.com/supabase/supabase-swift/commit/b5953839d5e5e99d8796d9258fbdf1b4657ab3b8))
* **postgrest:** allow isNull() on a JSON path ([#1304](https://github.com/supabase/supabase-swift/issues/1304)) ([4d0f178](https://github.com/supabase/supabase-swift/commit/4d0f1784ad47967946370855898af20d2bf25937))
* **postgrest:** computed fields and computed relationships in the typed query API ([#1475](https://github.com/supabase/supabase-swift/issues/1475)) ([ca80f84](https://github.com/supabase/supabase-swift/commit/ca80f848854d67fc720354712f3c4fdce3cdb83d))
* **postgrest:** deprecate the filter aliases on the untyped builder ([#1466](https://github.com/supabase/supabase-swift/issues/1466)) ([07cf009](https://github.com/supabase/supabase-swift/commit/07cf00951e13a7a45d176c571d70c41a3069a115))
* **postgrest:** diagnose stored properties with no type annotation ([#1274](https://github.com/supabase/supabase-swift/issues/1274)) ([d57414c](https://github.com/supabase/supabase-swift/commit/d57414c7e3c68ef5f27c1939ceba288069c1a8f3))
* **postgrest:** fold PostgrestError.Kind.unexpectedResponse into server and decoding ([#1405](https://github.com/supabase/supabase-swift/issues/1405)) ([b6991cb](https://github.com/supabase/supabase-swift/commit/b6991cbfd99474c6980d25a2632c5a4314db6016))
* **postgrest:** gate the typed API behind @_spi(Experimental) and lock the macro boundary ([#1494](https://github.com/supabase/supabase-swift/issues/1494)) ([c9b7de8](https://github.com/supabase/supabase-swift/commit/c9b7de844144c65c790b94c442e400d4dc23c4d2))
* **postgrest:** gate typed JSON methods on JSONValue columns and take JSONValue operands ([#1500](https://github.com/supabase/supabase-swift/issues/1500)) ([bbc636c](https://github.com/supabase/supabase-swift/commit/bbc636cd2d882c7b5fb1843dae510da5004acaab))
* **postgrest:** generate @Table structs with a Swift typegen ([#1488](https://github.com/supabase/supabase-swift/issues/1488)) ([5ff732b](https://github.com/supabase/supabase-swift/commit/5ff732be8ecd047e12f2446908f36449c672966e))
* **postgrest:** generate a Columns namespace from @Table ([#1290](https://github.com/supabase/supabase-swift/issues/1290)) ([845ff60](https://github.com/supabase/supabase-swift/commit/845ff6064e327eab6f78f625cfdf5d2cfa145de8))
* **postgrest:** let a typed upsert ignore duplicates instead of merging them ([#1309](https://github.com/supabase/supabase-swift/issues/1309)) ([3204541](https://github.com/supabase/supabase-swift/commit/32045417f2cbfe9ea05c56bef1200a07077c3679))
* **postgrest:** make PostgrestError a wrapper with ServerError payload; remove HTTPError ([#1336](https://github.com/supabase/supabase-swift/issues/1336)) ([370bb4d](https://github.com/supabase/supabase-swift/commit/370bb4db194a4f9d59e24b7bc969b381d6f587de))
* **postgrest:** map each Postgres type to one Swift type in the typegen ([#1519](https://github.com/supabase/supabase-swift/issues/1519)) ([264cace](https://github.com/supabase/supabase-swift/commit/264cace8cc85b8662e14cb7db35840ebb5e640c1))
* **postgrest:** name a relation's schema with a type ([#1372](https://github.com/supabase/supabase-swift/issues/1372)) ([29c978e](https://github.com/supabase/supabase-swift/commit/29c978e97d778f9c7f157c33a3f1718ebf31c3b3))
* **postgrest:** one request core for typed and untyped requests ([#1454](https://github.com/supabase/supabase-swift/issues/1454)) ([dd10883](https://github.com/supabase/supabase-swift/commit/dd108836d1efcafffed3a7bbe70dd9fbf8f2177f))
* **postgrest:** rename the typed wrappers and rebuild them on PostgrestRequest ([#1422](https://github.com/supabase/supabase-swift/issues/1422)) ([942ba75](https://github.com/supabase/supabase-swift/commit/942ba75a6e5bb7e0ff6543ababdec8eaa93e2da4))
* **postgrest:** require a filter on typed update and delete, and none on insert ([#1425](https://github.com/supabase/supabase-swift/issues/1425)) ([abf81ff](https://github.com/supabase/supabase-swift/commit/abf81ff336d5ae618c776af043a1438ec977d867))
* **postgrest:** send features=typed-api in X-Client-Info for typed API requests ([#1641](https://github.com/supabase/supabase-swift/issues/1641)) ([977b417](https://github.com/supabase/supabase-swift/commit/977b417e3726e2abd20267308bd8ab0e45920745))
* **realtime:** accept presence streams opened after subscribe when presence is on ([#1746](https://github.com/supabase/supabase-swift/issues/1746)) ([e65033c](https://github.com/supabase/supabase-swift/commit/e65033c3224bceee732dd80bc6c44488ff7a6b47))
* **realtime:** add BroadcastMessage, PostgresChange, PostgresRow and lazy TypedPostgresChange ([#1658](https://github.com/supabase/supabase-swift/issues/1658)) ([0339cd6](https://github.com/supabase/supabase-swift/commit/0339cd60ed0aa964a3109e4c5779dc1e0feba7b2))
* **realtime:** add the RealtimeEngine actor with supervisor, serial writer and fan-out ([#1459](https://github.com/supabase/supabase-swift/issues/1459)) ([0236e94](https://github.com/supabase/supabase-swift/commit/0236e94f28b245758ea382e6eb8d32427b7cd4ac))
* **realtime:** add token state and the presence tracker to the engine ([#1460](https://github.com/supabase/supabase-swift/issues/1460)) ([cedf006](https://github.com/supabase/supabase-swift/commit/cedf006b98a9c26a5f55114839acd8b0a6bf05c5))
* **realtime:** adopt Duration for the remaining TimeInterval intervals ([#1401](https://github.com/supabase/supabase-swift/issues/1401)) ([01a626b](https://github.com/supabase/supabase-swift/commit/01a626b83bcc105dae02728ff76d29f7e8dde5f7))
* **realtime:** clean up the RealtimeChannel API and add RealtimeChannelConfiguration ([#1663](https://github.com/supabase/supabase-swift/issues/1663)) ([4bc3865](https://github.com/supabase/supabase-swift/commit/4bc3865a4798723b27d62f254880c6eb3705c3ee))
* **realtime:** clean up the RealtimeClient and RealtimeClientOptions API ([#1661](https://github.com/supabase/supabase-swift/issues/1661)) ([d5fddaf](https://github.com/supabase/supabase-swift/commit/d5fddaff7b8656c9de30a236bcec52ac2a4646ae))
* **realtime:** collapse RealtimeClient and RealtimeChannel into actors on one executor ([#1591](https://github.com/supabase/supabase-swift/issues/1591)) ([f01f23b](https://github.com/supabase/supabase-swift/commit/f01f23b5cceb8a0e72a6b3bddc8155efd2b2bfba))
* **realtime:** drop protocol 1.0.0 and forward kind-4 broadcast metadata ([#1453](https://github.com/supabase/supabase-swift/issues/1453)) ([939957f](https://github.com/supabase/supabase-swift/commit/939957f9f5888f1b4b15e6255243b2beeee5a5f4))
* **realtime:** error classification and the package WebSocketTransport seam ([#1455](https://github.com/supabase/supabase-swift/issues/1455)) ([a092a6b](https://github.com/supabase/supabase-swift/commit/a092a6b588993c2552d8008e812dc0288be480cc))
* **realtime:** expose status through the actors and drop StatusMirror ([#1597](https://github.com/supabase/supabase-swift/issues/1597)) ([d19eed6](https://github.com/supabase/supabase-swift/commit/d19eed66f3f85d5ab11e4f2c3f4b6229ecc8e571))
* **realtime:** fail fast on watchOS with a .transport error citing TN3135 ([#1725](https://github.com/supabase/supabase-swift/issues/1725)) ([52d794a](https://github.com/supabase/supabase-swift/commit/52d794a9a34fab31e0fc11a405ded23c9c182112))
* **realtime:** fold RealtimeError.Kind.connection into transport ([#1407](https://github.com/supabase/supabase-swift/issues/1407)) ([0141de0](https://github.com/supabase/supabase-swift/commit/0141de0e677a373a97fbc8a856a33ac63e0a093e))
* **realtime:** keep presence state on the channel with Phoenix sync semantics ([#1604](https://github.com/supabase/supabase-swift/issues/1604)) ([3d5100d](https://github.com/supabase/supabase-swift/commit/3d5100d8e352d174c1dc243eac9db57bb9c0fa62))
* **realtime:** make broadcast, track and untrack async throws and drop PushHandle ([#1596](https://github.com/supabase/supabase-swift/issues/1596)) ([af28ef7](https://github.com/supabase/supabase-swift/commit/af28ef76f6bce1e5047149cc8bfd781657d4b775))
* **realtime:** presence public API on RealtimeChannel ([#1657](https://github.com/supabase/supabase-swift/issues/1657)) ([77da3f8](https://github.com/supabase/supabase-swift/commit/77da3f81a22cec3fd0b6c6e1d51d7efa53e4418b))
* **realtime:** probe the socket on foreground and wake from network changes ([#1724](https://github.com/supabase/supabase-swift/issues/1724)) ([ab9f53b](https://github.com/supabase/supabase-swift/commit/ab9f53bc56624dee1535f51eb635db8975720daf))
* **realtime:** public RealtimeError with kind; remove WebSocketError and NSError placeholders ([#1338](https://github.com/supabase/supabase-swift/issues/1338)) ([8a366c8](https://github.com/supabase/supabase-swift/commit/8a366c8197aaf45cab00ec08207d8a35498f8c8d))
* **realtime:** pure ConnectionMachine and ChannelMachine with table-driven tests ([#1457](https://github.com/supabase/supabase-swift/issues/1457)) ([33e7401](https://github.com/supabase/supabase-swift/commit/33e7401c0a0be9ebf8d7984e748d9ba3617bbe6d))
* **realtime:** run Realtime on a sans-IO core with all state on the client actor ([#1677](https://github.com/supabase/supabase-swift/issues/1677)) ([102cb4d](https://github.com/supabase/supabase-swift/commit/102cb4d917cf8e57fee37986321fa5aa6188bd70))
* **realtime:** status enums with reasons, channel events, heartbeat events ([#1655](https://github.com/supabase/supabase-swift/issues/1655)) ([2a7606b](https://github.com/supabase/supabase-swift/commit/2a7606b8770a58411a2f2ba6a880f12cf15bf165))
* **realtime:** token state with proactive refresh before exp, throttle and generation ([#1603](https://github.com/supabase/supabase-swift/issues/1603)) ([ddcdff2](https://github.com/supabase/supabase-swift/commit/ddcdff20a243f693352198ffaaa6ec0e68954279))
* replace Helpers.HTTPRequest/HTTPResponse with swift-http-types across the HTTP layer ([#1327](https://github.com/supabase/supabase-swift/issues/1327)) ([75dd30a](https://github.com/supabase/supabase-swift/commit/75dd30accea99b97bec5e72ddef8c4279a6624e4))
* share one jittered retry middleware across Auth and PostgREST ([#1341](https://github.com/supabase/supabase-swift/issues/1341)) ([f0d0d7b](https://github.com/supabase/supabase-swift/commit/f0d0d7bb8091f9faa9c93c1b52141da521a22910))
* stop trapping on dynamic values in library code ([#1323](https://github.com/supabase/supabase-swift/issues/1323)) ([c30c199](https://github.com/supabase/supabase-swift/commit/c30c199b81a3bc5c3248689dcdb2cb77daf6e2e6))
* **storage,postgrest:** rename setHeader to settingHeader and align its signature ([#1734](https://github.com/supabase/supabase-swift/issues/1734)) ([8c69d5b](https://github.com/supabase/supabase-swift/commit/8c69d5b7116ef6ae29d67fbd10f5b75331aef30b))
* **storage:** add CDN cache purging for files and buckets ([#1358](https://github.com/supabase/supabase-swift/issues/1358)) ([6e069a6](https://github.com/supabase/supabase-swift/commit/6e069a6286f32192465f9d302fd638a2d5686387))
* **storage:** add vector bucket CRUD (alpha) ([#1153](https://github.com/supabase/supabase-swift/issues/1153)) ([a4ad8af](https://github.com/supabase/supabase-swift/commit/a4ad8af5077453056adfd7805392ee81bb0764ca))
* **storage:** add vector index and vector data operations (alpha) ([#1181](https://github.com/supabase/supabase-swift/issues/1181)) ([3882e79](https://github.com/supabase/supabase-swift/commit/3882e7901cbcca98c5ec3eb82b519143a3aa1a0d))
* **storage:** all-optional BucketOptions, partial updateBucket, ByteCount ([#1514](https://github.com/supabase/supabase-swift/issues/1514)) ([f3d5aba](https://github.com/supabase/supabase-swift/commit/f3d5abadc3add5cb60e1a8e373a4c6f0622af0b6))
* **storage:** bucket lifecycle get, set and delete ([#1545](https://github.com/supabase/supabase-swift/issues/1545)) ([172172d](https://github.com/supabase/supabase-swift/commit/172172d513c0bab11db7a7ea1b4470e79c340d28))
* **storage:** bucket versioning status, split BucketOptions into create and update options ([#1569](https://github.com/supabase/supabase-swift/issues/1569)) ([c19cf18](https://github.com/supabase/supabase-swift/commit/c19cf1844092e1606057143a72bd3a48b76fa880))
* **storage:** copy takes CopyOptions and returns UploadedObject ([#1544](https://github.com/supabase/supabase-swift/issues/1544)) ([fc931d2](https://github.com/supabase/supabase-swift/commit/fc931d257433111320df006ebfe6555214c10eea))
* **storage:** download returns a DownloadResponse that streams the object ([#1532](https://github.com/supabase/supabase-swift/issues/1532)) ([5dde841](https://github.com/supabase/supabase-swift/commit/5dde841f7455e7ca561f6411452867e689cab37e))
* **storage:** download takes DownloadOptions with range, versionId, cacheNonce and headers ([#1531](https://github.com/supabase/supabase-swift/issues/1531)) ([cb734d2](https://github.com/supabase/supabase-swift/commit/cb734d22b8337bdaedbfa650d53fed3080f1a5b8))
* **storage:** drop the String download overloads and SignedURL; publicURL no longer throws ([#1515](https://github.com/supabase/supabase-swift/issues/1515)) ([d53afa7](https://github.com/supabase/supabase-swift/commit/d53afa76804b7f2490e933b7221a8c6eb512bf16))
* **storage:** expiresIn on signed URLs is a Duration ([#1512](https://github.com/supabase/supabase-swift/issues/1512)) ([c46d715](https://github.com/supabase/supabase-swift/commit/c46d715aec59c191c78321ce71ee24eac4c294b3))
* **storage:** expose AccessTokenMiddleware; headers are HTTPFields; setHeader merges ([#1516](https://github.com/supabase/supabase-swift/issues/1516)) ([0b32d79](https://github.com/supabase/supabase-swift/commit/0b32d79163374a3aaf22475d7302ff60a9d302cc))
* **storage:** expose the error code from Storage error responses ([#1370](https://github.com/supabase/supabase-swift/issues/1370)) ([b9aecd8](https://github.com/supabase/supabase-swift/commit/b9aecd8e00ef5888a6d1855ca76c71785bcfa283))
* **storage:** fold StorageError.Kind.unexpectedResponse into server; rename invalidURL to invalidRequest ([#1404](https://github.com/supabase/supabase-swift/issues/1404)) ([35c5944](https://github.com/supabase/supabase-swift/commit/35c59440c5e99a364ec46869c1f688196c5a3258))
* **storage:** ImageTransform replaces TransformOptions and adds gravity and focal point ([#1511](https://github.com/supabase/supabase-swift/issues/1511)) ([b24ca56](https://github.com/supabase/supabase-swift/commit/b24ca567024456efac3b33b95325fa93fa0c7bce))
* **storage:** infer common content types on Linux ([#1563](https://github.com/supabase/supabase-swift/issues/1563)) ([9c6ed1c](https://github.com/supabase/supabase-swift/commit/9c6ed1cf683d95a17ab87d5230467967d2f748e2))
* **storage:** integration and memory tests for resumable uploads ([#1553](https://github.com/supabase/supabase-swift/issues/1553)) ([68a4b9f](https://github.com/supabase/supabase-swift/commit/68a4b9f4aa0c8cc9d99d4404ab0924e70af53121))
* **storage:** listBuckets(options:), Bucket.type and BucketType ([#1541](https://github.com/supabase/supabase-swift/issues/1541)) ([34ec629](https://github.com/supabase/supabase-swift/commit/34ec62910795d87b4e80a378d8816977e2fd12f5))
* **storage:** ListOptions replaces SearchOptions and SortBy ([#1538](https://github.com/supabase/supabase-swift/issues/1538)) ([960014c](https://github.com/supabase/supabase-swift/commit/960014cfc172052066d0b607393663900fe2bde1))
* **storage:** make StorageError a struct with kind, server payload and HTTP context ([#1335](https://github.com/supabase/supabase-swift/issues/1335)) ([229d423](https://github.com/supabase/supabase-swift/commit/229d423c043cdb10247a43ddc0e48b3ad729dc49))
* **storage:** mark the resumable upload API @_spi(Experimental) ([#1562](https://github.com/supabase/supabase-swift/issues/1562)) ([ed04d11](https://github.com/supabase/supabase-swift/commit/ed04d11933351993d8def4db0b491ee47f570079))
* **storage:** objects(prefix:options:) lists through list-v2 as an AsyncSequence ([#1539](https://github.com/supabase/supabase-swift/issues/1539)) ([6b13596](https://github.com/supabase/supabase-swift/commit/6b1359635dd55d5994354cae7f0e7b1cc82506c2))
* **storage:** progress closure on upload, update and uploadToSignedURL ([#1529](https://github.com/supabase/supabase-swift/issues/1529)) ([8414e2b](https://github.com/supabase/supabase-swift/commit/8414e2b49b7387349dd0637f715f5ed9f55b0222))
* **storage:** promote code and serverStatusCode on StorageError, add isNotFound ([#1508](https://github.com/supabase/supabase-swift/issues/1508)) ([1be2fad](https://github.com/supabase/supabase-swift/commit/1be2fad8f37d2fc81b31977ee4108505e647651a))
* **storage:** purgeCache takes includingTransformations, and bucket nil purges every bucket ([#1546](https://github.com/supabase/supabase-swift/issues/1546)) ([936fa2a](https://github.com/supabase/supabase-swift/commit/936fa2a2c98eed1ef8f3489e30dbe8fe592cdd21))
* **storage:** registry and storage host for resumable uploads ([#1552](https://github.com/supabase/supabase-swift/issues/1552)) ([e0c3c8a](https://github.com/supabase/supabase-swift/commit/e0c3c8a7a0b974322dfc987842626d2a381e49fc))
* **storage:** rename StorageFileApi to StorageBucket and SupabaseStorageClient to StorageClient ([#1506](https://github.com/supabase/supabase-swift/issues/1506)) ([9164d6a](https://github.com/supabase/supabase-swift/commit/9164d6aaee747932eb6621953c0ec0f2b5e20d93))
* **storage:** resumable uploads with pause, resume and cancel ([#1551](https://github.com/supabase/supabase-swift/issues/1551)) ([b75b6d1](https://github.com/supabase/supabase-swift/commit/b75b6d1d8306dddf71e03a9d74328374ccfabc7e))
* **storage:** ResumableStore persists resumable upload records ([#1550](https://github.com/supabase/supabase-swift/issues/1550)) ([d4cd30a](https://github.com/supabase/supabase-swift/commit/d4cd30a75e13ef736276ae0e30478356341489e7))
* **storage:** retry transient failures of Storage reads ([#1436](https://github.com/supabase/supabase-swift/issues/1436)) ([55ad42e](https://github.com/supabase/supabase-swift/commit/55ad42ef58d862d8cc5ee66fd3f0da93b03c6c82))
* **storage:** send uploads as the raw file body instead of multipart ([#1400](https://github.com/supabase/supabase-swift/issues/1400)) ([2d04c76](https://github.com/supabase/supabase-swift/commit/2d04c761e12f316a77d27cd0ec399ffd9977368f))
* **storage:** StorageAnalyticsClient creates, lists and deletes analytics buckets ([#1542](https://github.com/supabase/supabase-swift/issues/1542)) ([a41690d](https://github.com/supabase/supabase-swift/commit/a41690d39fcb0588b77e4de126141d8b1107f48a))
* **storage:** StorageObject, ObjectMetadata, ObjectInfo and UploadedObject replace the object types ([#1513](https://github.com/supabase/supabase-swift/issues/1513)) ([f0dc01a](https://github.com/supabase/supabase-swift/commit/f0dc01aa2cc8b7a9f7b94d59aab5961dce613939))
* **storage:** tus 1.0 session over upload/resumable ([#1549](https://github.com/supabase/supabase-swift/issues/1549)) ([eb47b4b](https://github.com/supabase/supabase-swift/commit/eb47b4b98bacde264caa9e0f0458ceabd7f8b410))
* **storage:** upload a Transferable item ([#1564](https://github.com/supabase/supabase-swift/issues/1564)) ([775b6bf](https://github.com/supabase/supabase-swift/commit/775b6bfdc3587abfc9ef927d155bd920c3985d03))
* **storage:** upload, update and uploadToSignedURL take an HTTPBody stream ([#1530](https://github.com/supabase/supabase-swift/issues/1530)) ([75e5da1](https://github.com/supabase/supabase-swift/commit/75e5da1c3c8e545f3d5e68c79b026742a4a6b526))
* **storage:** UploadOptions replaces FileOptions with a typed CacheControl ([#1510](https://github.com/supabase/supabase-swift/issues/1510)) ([de02d52](https://github.com/supabase/supabase-swift/commit/de02d520bd2866309d4bcef9949358d4a6d8d426))
* **storage:** Vectors list through PagedListing and decode Date timestamps ([#1540](https://github.com/supabase/supabase-swift/issues/1540)) ([bfb5a67](https://github.com/supabase/supabase-swift/commit/bfb5a67cfcdc473fc49d9bbdda45c8914a6d6dcf))
* **storage:** versionId on info, sign, publicURL, move and copy; remove(versions:) ([#1543](https://github.com/supabase/supabase-swift/issues/1543)) ([3d29f23](https://github.com/supabase/supabase-swift/commit/3d29f23f72c9b88b77f7fcba2bf57798332e76f3))
* **supabase:** add http, logger, and clock overrides to AuthOptions ([#1733](https://github.com/supabase/supabase-swift/issues/1733)) ([4e0c7a4](https://github.com/supabase/supabase-swift/commit/4e0c7a4beb3c5d6edb7a6935c0984e5672b38433))
* **supabase:** live query stream(_:where:) and LiveQuery observable ([#1671](https://github.com/supabase/supabase-swift/issues/1671)) ([fc19360](https://github.com/supabase/supabase-swift/commit/fc193605d676521afecd561b25852e1a9a88856e))
* **supabase:** one Authorization rule for the data clients; cached supabase.functions; FunctionsOptions gains http and logger ([#1446](https://github.com/supabase/supabase-swift/issues/1446)) ([17d580f](https://github.com/supabase/supabase-swift/commit/17d580f849be86369ec192c2045398ed425aab7f))
* **supabase:** retry a data request rejected for a stale token once, with the current token or after one refresh ([#1634](https://github.com/supabase/supabase-swift/issues/1634)) ([88c8444](https://github.com/supabase/supabase-swift/commit/88c8444ab4a4e3ddda4151402a79e67f770f56d2))
* **supabase:** ship a SwiftUI \.supabase environment value ([#1820](https://github.com/supabase/supabase-swift/issues/1820)) ([ab19260](https://github.com/supabase/supabase-swift/commit/ab192606ac346b2418bbda235858e9d8ec0a814c))
* **supabase:** typed postgresChanges(for:where:) over _PostgrestRelation ([#1670](https://github.com/supabase/supabase-swift/issues/1670)) ([287cfcc](https://github.com/supabase/supabase-swift/commit/287cfcc5bdd007e3e76b5e6fcb47201b8ea4061d))
* throw from client initializers on an invalid configuration ([#1762](https://github.com/supabase/supabase-swift/issues/1762)) ([1e9e416](https://github.com/supabase/supabase-swift/commit/1e9e416a8638e591e28e732c01ba4c55e4b8b6be))
* **typegen:** generate client.rpc methods that call the typed rpc ([#1731](https://github.com/supabase/supabase-swift/issues/1731)) ([16a5f8a](https://github.com/supabase/supabase-swift/commit/16a5f8aedcfcc11a5979c7b5d5ec9cf7ae3b41ba))
* **typegen:** start the generated file with a do-not-edit notice ([#1819](https://github.com/supabase/supabase-swift/issues/1819)) ([54f42c2](https://github.com/supabase/supabase-swift/commit/54f42c2651880c6c6596fc72b49786debc07bdbb))


### Bug Fixes

* **auth,storage,realtime,helpers:** narrow Codable conformances to their actual usage direction ([#1209](https://github.com/supabase/supabase-swift/issues/1209)) ([0b558d5](https://github.com/supabase/supabase-swift/commit/0b558d53cda2f2e4b80f944b1ffab240ea21c2f5))
* **auth:** a failed linkIdentityURL request removes its PKCE flow ([#1712](https://github.com/supabase/supabase-swift/issues/1712)) ([836ff22](https://github.com/supabase/supabase-swift/commit/836ff221f94fad78472d44e922dff98ceaf05ce0))
* **auth:** address code-review findings on VerifyOTPResponse ([#1205](https://github.com/supabase/supabase-swift/issues/1205)) ([f285277](https://github.com/supabase/supabase-swift/commit/f285277a8570a66d622d4b44d8a4a015cc2ec2dd))
* **auth:** always emit locally stored session as initial session ([#1214](https://github.com/supabase/supabase-swift/issues/1214)) ([12cfe79](https://github.com/supabase/supabase-swift/commit/12cfe799b7efa4321a250eeb1165b855559c665b))
* **auth:** complete signOut when the server no longer has the session ([#1399](https://github.com/supabase/supabase-swift/issues/1399)) ([525bb25](https://github.com/supabase/supabase-swift/commit/525bb25de2566150f2b496b301ab0facb855c295))
* **auth:** convert EmailOTPType to a RawRepresentable struct ([#1221](https://github.com/supabase/supabase-swift/issues/1221)) ([9dc627e](https://github.com/supabase/supabase-swift/commit/9dc627ef2d80ffb49f142f3e9d61066d70aed563))
* **auth:** convert FactorStatus to a RawRepresentable struct ([#1215](https://github.com/supabase/supabase-swift/issues/1215)) ([2fa8d76](https://github.com/supabase/supabase-swift/commit/2fa8d76bb19cc50e1778a69468d82b469da48412))
* **auth:** convert MessagingChannel to a RawRepresentable struct ([#1216](https://github.com/supabase/supabase-swift/issues/1216)) ([14dbc6a](https://github.com/supabase/supabase-swift/commit/14dbc6ab83bcf4cf2cd315ca94e52f2430f40d49))
* **auth:** convert MobileOTPType to a RawRepresentable struct ([#1220](https://github.com/supabase/supabase-swift/issues/1220)) ([3c39d48](https://github.com/supabase/supabase-swift/commit/3c39d4811d500dc1bbb98b6818d2b7906fc1c99f))
* **auth:** convert OpenIDConnectCredentials.Provider to a RawRepresentable struct ([#1219](https://github.com/supabase/supabase-swift/issues/1219)) ([23e1793](https://github.com/supabase/supabase-swift/commit/23e1793d5d7287307caff755d346e47c04fc8519))
* **auth:** convert Provider to a RawRepresentable struct ([#1217](https://github.com/supabase/supabase-swift/issues/1217)) ([dd7fcb2](https://github.com/supabase/supabase-swift/commit/dd7fcb2275c1dfb58ef48ec7b4e49d84a4d04319))
* **auth:** convert ResendEmailType to a RawRepresentable struct ([#1222](https://github.com/supabase/supabase-swift/issues/1222)) ([42f66bd](https://github.com/supabase/supabase-swift/commit/42f66bd9c924ff92697e463c5b64a9b38e5eb81f))
* **auth:** convert ResendMobileType to a RawRepresentable struct ([#1223](https://github.com/supabase/supabase-swift/issues/1223)) ([b1c877d](https://github.com/supabase/supabase-swift/commit/b1c877dbe3bbd2d1f9653fbabd31a1ef2781c798))
* **auth:** convert SignOutScope to a RawRepresentable struct ([#1224](https://github.com/supabase/supabase-swift/issues/1224)) ([0c63222](https://github.com/supabase/supabase-swift/commit/0c63222ea6f94f03d9c8094d86025ae3c773a100))
* **auth:** convert WebAuthnChallengeType to a RawRepresentable struct ([#1218](https://github.com/supabase/supabase-swift/issues/1218)) ([966859b](https://github.com/supabase/supabase-swift/commit/966859bab598b836e3de90d323b9aa559ad52556))
* **auth:** decode OAuth clients that omit redirect URIs, grant types or response types ([#1349](https://github.com/supabase/supabase-swift/issues/1349)) ([0ed1e8c](https://github.com/supabase/supabase-swift/commit/0ed1e8cf5db6dafe75e2ee553db5adbd956feef4))
* **auth:** decode OAuth server responses that omit optional fields ([#1347](https://github.com/supabase/supabase-swift/issues/1347)) ([b2b6c30](https://github.com/supabase/supabase-swift/commit/b2b6c3039b3970d6785f29898a49c58dfedebd33))
* **auth:** discard a token refresh that outlived its session ([#1374](https://github.com/supabase/supabase-swift/issues/1374)) ([8de0e62](https://github.com/supabase/supabase-swift/commit/8de0e62aa6b8e8914d33c7e9eef56f12cd6de92e))
* **auth:** drop LocalStorage implementation for Windows platform ([#1213](https://github.com/supabase/supabase-swift/issues/1213)) ([7bf6da1](https://github.com/supabase/supabase-swift/commit/7bf6da15853c72eb50f8edd7ba197e92237618a6))
* **auth:** drop refresh token from log metadata, inject client logger into event emitter ([#1211](https://github.com/supabase/supabase-swift/issues/1211)) ([48e6438](https://github.com/supabase/supabase-swift/commit/48e6438ddf0b273a3822c9e9c960cc1eae781788))
* **auth:** encode confirmsEmail and confirmsPhone as email_confirm and phone_confirm ([#1388](https://github.com/supabase/supabase-swift/issues/1388)) ([17f720b](https://github.com/supabase/supabase-swift/commit/17f720bef7eb22ad70d383833a3ebdfc66798a1a))
* **auth:** exchangeCodeForSession fails before the request when the PKCE verifier is missing ([#1523](https://github.com/supabase/supabase-swift/issues/1523)) ([8a45672](https://github.com/supabase/supabase-swift/commit/8a456726772572944094631f2b676ace2ad440f2))
* **auth:** fall back to the JWT header alg when the JWK omits one ([#1348](https://github.com/supabase/supabase-swift/issues/1348)) ([977ded6](https://github.com/supabase/supabase-swift/commit/977ded62e7ec6257273ca1cfe471128f85567727))
* **auth:** fix macOS Keychain consent prompt and storage contract ([#1208](https://github.com/supabase/supabase-swift/issues/1208)) ([528bd5f](https://github.com/supabase/supabase-swift/commit/528bd5fbb1689c3beff32875e7ff450d688d8db3))
* **auth:** give each client its own session store and keep refreshes across user updates ([#1640](https://github.com/supabase/supabase-swift/issues/1640)) ([8d03136](https://github.com/supabase/supabase-swift/commit/8d03136588c4eec10b20cf1e74866f874c5d0675))
* **auth:** handle only redirects to a known callback, drop sb_flow_id, share the flow index per key ([#1743](https://github.com/supabase/supabase-swift/issues/1743)) ([5f0257f](https://github.com/supabase/supabase-swift/commit/5f0257f09ea4666b7aa9cc401c7bb642d1c6c409))
* **auth:** keep a fixed Keychain service for every KeychainLocalStorage ([#1394](https://github.com/supabase/supabase-swift/issues/1394)) ([c7d6ef2](https://github.com/supabase/supabase-swift/commit/c7d6ef2a6078db69d8d3e4fde0e759256cc65252))
* **auth:** keep a newer stored session and guard user updates by user id ([#1741](https://github.com/supabase/supabase-swift/issues/1741)) ([6316b83](https://github.com/supabase/supabase-swift/commit/6316b83f2b7aa182b6901af61b379f7f085960d3))
* **auth:** keep a newer stored session when a rejected refresh signs out ([#1660](https://github.com/supabase/supabase-swift/issues/1660)) ([9be2716](https://github.com/supabase/supabase-swift/commit/9be27161b2076cc6b13246efd41c607235c975ef))
* **auth:** keep adminClient alive across awaited signOut in integration test ([#1178](https://github.com/supabase/supabase-swift/issues/1178)) ([c5d0671](https://github.com/supabase/supabase-swift/commit/c5d0671d1fa275751af3ce80e73194aa139eaa31))
* **auth:** listen on the callback scheme the provider redirects to ([#1363](https://github.com/supabase/supabase-swift/issues/1363)) ([ba8ebab](https://github.com/supabase/supabase-swift/commit/ba8ebab3ca8233602d6bb82295371e5beb69fce1))
* **auth:** parse the admin pagination Link header without trapping ([#1379](https://github.com/supabase/supabase-swift/issues/1379)) ([7681d6c](https://github.com/supabase/supabase-swift/commit/7681d6c8e507f358d9816104c53bc9a62d4b9f71))
* **auth:** pass the session being signed out as SessionOwnership ([#1416](https://github.com/supabase/supabase-swift/issues/1416)) ([6c7d3b5](https://github.com/supabase/supabase-swift/commit/6c7d3b521c37ca8866d41b1d10f9da6aa848cb07))
* **auth:** post admin invites to the /invite route the Auth server serves ([#1505](https://github.com/supabase/supabase-swift/issues/1505)) ([f0fcd36](https://github.com/supabase/supabase-swift/commit/f0fcd36341e7117bf38bab9bc067f5b6aa61a05a)), closes [#1471](https://github.com/supabase/supabase-swift/issues/1471)
* **auth:** preserve status context for non-JSON 5xx errors ([#1392](https://github.com/supabase/supabase-swift/issues/1392)) ([6fc12f3](https://github.com/supabase/supabase-swift/commit/6fc12f35ab71463b75798efcae26912cb542b622))
* **auth:** remove AuthClient from Dependencies registry on deinit ([#1176](https://github.com/supabase/supabase-swift/issues/1176)) ([0826b28](https://github.com/supabase/supabase-swift/commit/0826b287b85ee7999cc25bb5b07ba5637984a439))
* **auth:** remove legacy session data that does not decode ([#1632](https://github.com/supabase/supabase-swift/issues/1632)) ([75e3b86](https://github.com/supabase/supabase-swift/commit/75e3b86565023cb90fc1983463bf323acf050327))
* **auth:** return VerifyOTPResponse from verifyOTP instead of AuthResponse ([#1088](https://github.com/supabase/supabase-swift/issues/1088)) ([dd5e825](https://github.com/supabase/supabase-swift/commit/dd5e82513da43bfe16eabb24d2932548d75d36bb))
* **auth:** scope session cleanup to the access token a request carries ([#1432](https://github.com/supabase/supabase-swift/issues/1432)) ([1199c95](https://github.com/supabase/supabase-swift/commit/1199c958a737feffc7488fa5b94fc4c20ab6f978))
* **auth:** scope session cleanup to the session a request redeems ([#1402](https://github.com/supabase/supabase-swift/issues/1402)) ([7785b56](https://github.com/supabase/supabase-swift/commit/7785b56d8e14ffa9c888ec35d2fe99019fa0c23b))
* **auth:** send skip_http_redirect so signInWithSSO gets JSON instead of a 303 ([#1321](https://github.com/supabase/supabase-swift/issues/1321)) ([321c961](https://github.com/supabase/supabase-swift/commit/321c9617392ffbddcc21a63d8743f4c029394bfc))
* **auth:** set authStateChanges onTermination before returning the stream ([#1428](https://github.com/supabase/supabase-swift/issues/1428)) ([eca66a2](https://github.com/supabase/supabase-swift/commit/eca66a265c38b97a37e3101f6166d4f019b5e156))
* **auth:** stop auto-refresh task on AuthClient deinit ([#1193](https://github.com/supabase/supabase-swift/issues/1193)) ([c6a5d99](https://github.com/supabase/supabase-swift/commit/c6a5d99a204c17da2f4db8555edcc27f46b8f2cd))
* **auth:** stop treating any message link as an email-change redirect ([#1708](https://github.com/supabase/supabase-swift/issues/1708)) ([8d14787](https://github.com/supabase/supabase-swift/commit/8d147875ff12d8efc49633e8ecc8e5d2471b6c79))
* **auth:** use UUID for MFA challenge identifiers ([#1412](https://github.com/supabase/supabase-swift/issues/1412)) ([ae9fd5f](https://github.com/supabase/supabase-swift/commit/ae9fd5fef7ed2e181a51ab5675968d594ae2bbec))
* **ci:** compute coverage from this run's profile and every test bundle ([#1615](https://github.com/supabase/supabase-swift/issues/1615)) ([3723c28](https://github.com/supabase/supabase-swift/commit/3723c28055b9a6307231b1d7bab75dabe8ad505d))
* **ci:** fail loudly instead of silently exporting stale coverage ([#1242](https://github.com/supabase/supabase-swift/issues/1242)) ([5f59480](https://github.com/supabase/supabase-swift/commit/5f5948004e87d9882f65e482a766f250d15aca5d))
* **ci:** purge stale Clang module cache in xcodebuild legacy job ([#1243](https://github.com/supabase/supabase-swift/issues/1243)) ([1a8b451](https://github.com/supabase/supabase-swift/commit/1a8b45128fb93a034cb47e8647811244fbf38e74))
* **docs:** match DocC's current warning phrasing and fix stale symbol links ([#1241](https://github.com/supabase/supabase-swift/issues/1241)) ([80ad2a1](https://github.com/supabase/supabase-swift/commit/80ad2a1006547bab98d78757a1cc5c3c3218124e))
* flaky CI in AuthTests and RealtimeTests ([#1164](https://github.com/supabase/supabase-swift/issues/1164)) ([3585688](https://github.com/supabase/supabase-swift/commit/358568852992c3b5cc05567f11f6d885a0d52eba))
* **functions,realtime:** throw CancellationError when the caller's task is cancelled ([#1442](https://github.com/supabase/supabase-swift/issues/1442)) ([92a5411](https://github.com/supabase/supabase-swift/commit/92a541153344ad9d08f05d1acf87f51d3cc0db9e))
* **functions:** convert FunctionInvokeOptions.Method to a RawRepresentable struct ([#1229](https://github.com/supabase/supabase-swift/issues/1229)) ([3df400c](https://github.com/supabase/supabase-swift/commit/3df400c48a2640f10b8678856e313e03a478fc18))
* **functions:** invalidate URLSession in streamed response ([#1122](https://github.com/supabase/supabase-swift/issues/1122)) ([68a78ab](https://github.com/supabase/supabase-swift/commit/68a78abefd5b2d1af89e96052bb271e9dd68ad10))
* **helpers:** extend Swift version detection ladder, drop unsupported floors ([#1160](https://github.com/supabase/supabase-swift/issues/1160)) ([186daf0](https://github.com/supabase/supabase-swift/commit/186daf067cdfa3c6361514a66303b2cd61465b6e))
* **helpers:** HTTPClient owns cancellation mapping, the error-body cap, and the 429 rule ([#1775](https://github.com/supabase/supabase-swift/issues/1775)) ([c7ee9d7](https://github.com/supabase/supabase-swift/commit/c7ee9d7aa5818270eccfe5a40456aff8a48d2f16))
* **helpers:** keep LoggerInterceptor from failing a request when a body outgrows its declared length ([#1796](https://github.com/supabase/supabase-swift/issues/1796)) ([a60242e](https://github.com/supabase/supabase-swift/commit/a60242e0761c2e7f3e6b1d32003a5df8bc5dc383))
* **helpers:** keep the early response when URLSession stops reading a streamed body ([#1548](https://github.com/supabase/supabase-swift/issues/1548)) ([ff4d529](https://github.com/supabase/supabase-swift/commit/ff4d5295aa9b9618d29b75d2ef328a04a8967feb))
* **helpers:** make OSLogHandler internal-only ([#1212](https://github.com/supabase/supabase-swift/issues/1212)) ([04c7383](https://github.com/supabase/supabase-swift/commit/04c73836da126c1efb3deb9db304cc44a62c1f89))
* **helpers:** parse Postgres timestamp offsets instead of dropping them ([#1427](https://github.com/supabase/supabase-swift/issues/1427)) ([ede2210](https://github.com/supabase/supabase-swift/commit/ede22108bae44575efe8ab1e8b881a2a80837f89))
* **helpers:** report an unknown length for an encoded response body ([#1806](https://github.com/supabase/supabase-swift/issues/1806)) ([3291b73](https://github.com/supabase/supabase-swift/commit/3291b734b49e509d2f3590b66d4dcf45d2b84f8f))
* **helpers:** write the UTC designator when encoding a Date ([#1431](https://github.com/supabase/supabase-swift/issues/1431)) ([5980c53](https://github.com/supabase/supabase-swift/commit/5980c5379a99e1b78cca126e5bef5a1e3980a8eb))
* keep the default X-Client-Info out of configuration, and expose Auth retryEnabled on the facade ([#1787](https://github.com/supabase/supabase-swift/issues/1787)) ([b22b029](https://github.com/supabase/supabase-swift/commit/b22b029cd1f4d2d634faab751497ba80ac787be9))
* make `isRetryable` internal; the SDK owns retry decisions ([#1784](https://github.com/supabase/supabase-swift/issues/1784)) ([f3f2f94](https://github.com/supabase/supabase-swift/commit/f3f2f940036403b3a9fe46299c16dac0f05e12b3))
* middleware is the one way to send an access token, with one failure shape ([#1779](https://github.com/supabase/supabase-swift/issues/1779)) ([5e11a3a](https://github.com/supabase/supabase-swift/commit/5e11a3a9a1c4f2922ebe8e6770750e598c18dce0))
* **postgrest:** close the typed upsert's missing conflict target ([#1283](https://github.com/supabase/supabase-swift/issues/1283)) ([06f5c75](https://github.com/supabase/supabase-swift/commit/06f5c75e4bca159223908de3546d698b6f9802a6))
* **postgrest:** convert CountOption to a RawRepresentable struct ([#1226](https://github.com/supabase/supabase-swift/issues/1226)) ([672c438](https://github.com/supabase/supabase-swift/commit/672c4381f366811a43be7d5e61c0b3e79a0cdfb4))
* **postgrest:** convert PostgrestFilterBuilder.Operator to a RawRepresentable struct ([#1225](https://github.com/supabase/supabase-swift/issues/1225)) ([1149c6f](https://github.com/supabase/supabase-swift/commit/1149c6f9c5b3bdac95e9dd9b94deb79dc72c724f))
* **postgrest:** convert PostgrestReturningOptions to a RawRepresentable struct ([#1227](https://github.com/supabase/supabase-swift/issues/1227)) ([068c6fd](https://github.com/supabase/supabase-swift/commit/068c6fdb9ff992d4d7eee604fd2f40a632b1d7fd))
* **postgrest:** convert TextSearchType to a RawRepresentable struct ([#1228](https://github.com/supabase/supabase-swift/issues/1228)) ([3dd7e62](https://github.com/supabase/supabase-swift/commit/3dd7e62606ee47857eecfee4eb649cf8ab335d1f))
* **postgrest:** decode PostgrestError details field ([#1159](https://github.com/supabase/supabase-swift/issues/1159)) ([b9296f6](https://github.com/supabase/supabase-swift/commit/b9296f62344db6678f5f7562062d4ddc8f2ff796))
* **postgrest:** diagnose @Column on a multi-binding declaration and @PrimaryKey on an Optional ([#1467](https://github.com/supabase/supabase-swift/issues/1467)) ([c8f6281](https://github.com/supabase/supabase-swift/commit/c8f62815d5c61846d5dc34162d4d39855ad162b0))
* **postgrest:** encode a Date in a typed update with the encoder's date strategy ([#1821](https://github.com/supabase/supabase-swift/issues/1821)) ([e11fd0f](https://github.com/supabase/supabase-swift/commit/e11fd0fc063b3ebe698de5f58716d0b2b1292ee7))
* **postgrest:** escape reserved characters in array filter values ([#1126](https://github.com/supabase/supabase-swift/issues/1126)) ([e0ef7b3](https://github.com/supabase/supabase-swift/commit/e0ef7b393f49c73f7fe2997e823e76c0e28f5e30))
* **postgrest:** give each range type its own _PostgresRange bound marker ([#1575](https://github.com/supabase/supabase-swift/issues/1575)) ([4eeecbd](https://github.com/supabase/supabase-swift/commit/4eeecbd7062fd5b95b21b8e4f32c90be708e0df4))
* **postgrest:** jsonObject returns JSONValue and JSON comparisons encode their operand ([#1501](https://github.com/supabase/supabase-swift/issues/1501)) ([786e153](https://github.com/supabase/supabase-swift/commit/786e153e902ce254d3c3fb7dafb0191f018cb98a))
* **postgrest:** keep a client-level Prefer header in rpc(count:) ([#1440](https://github.com/supabase/supabase-swift/issues/1440)) ([99c1961](https://github.com/supabase/supabase-swift/commit/99c1961b85adc16ca3c59d2e2f3e34f1e976fe6e))
* **postgrest:** keep resolution=merge-duplicates when returning() follows upsert ([#1308](https://github.com/supabase/supabase-swift/issues/1308)) ([7e64c05](https://github.com/supabase/supabase-swift/commit/7e64c05c9c343c41a0ecf410d0e06542e11d7a9f))
* **postgrest:** let a typed update clear a nullable column ([#1281](https://github.com/supabase/supabase-swift/issues/1281)) ([bc52fc7](https://github.com/supabase/supabase-swift/commit/bc52fc709b8dd040854e70ed7168ef75401c587f))
* **postgrest:** let Update change a primary key column ([#1280](https://github.com/supabase/supabase-swift/issues/1280)) ([62bb21b](https://github.com/supabase/supabase-swift/commit/62bb21beb3b3a41451a6534e55bc9502ee308677))
* **postgrest:** make @Table, @SelectionOf, and @Function expansions compile under default MainActor isolation ([#1747](https://github.com/supabase/supabase-swift/issues/1747)) ([82e978e](https://github.com/supabase/supabase-swift/commit/82e978e7a0c1f02baa0e3a6abf3996ecee5fb668))
* **postgrest:** make the primary key optional in Insert, not absent ([#1278](https://github.com/supabase/supabase-swift/issues/1278)) ([a595e61](https://github.com/supabase/supabase-swift/commit/a595e61a9e17a9e2b8b6e491b0905634407155fc))
* **postgrest:** maybeSingle() no-row status and exact GET RPC arguments ([#1789](https://github.com/supabase/supabase-swift/issues/1789)) ([f34d688](https://github.com/supabase/supabase-swift/commit/f34d688641649428cc99be8b89eb62609164c50c))
* **postgrest:** name the failed constraint when a typed source is misused ([#1421](https://github.com/supabase/supabase-swift/issues/1421)) ([deb4033](https://github.com/supabase/supabase-swift/commit/deb4033a48374df690a8bfb91f9d3395ca6c5db1))
* **postgrest:** order() no longer forces NULLS LAST by default ([#1417](https://github.com/supabase/supabase-swift/issues/1417)) ([894f35d](https://github.com/supabase/supabase-swift/commit/894f35dd0bdb73e7090265b885eb01ace5b5cafc))
* **postgrest:** quote array elements in rpc GET/HEAD params ([#1383](https://github.com/supabase/supabase-swift/issues/1383)) ([380f8a9](https://github.com/supabase/supabase-swift/commit/380f8a9109a81e5a32e0a8fb212d9aa583a2737e))
* **postgrest:** quote filter values and array elements with surrounding newlines ([#1413](https://github.com/supabase/supabase-swift/issues/1413)) ([5ab5032](https://github.com/supabase/supabase-swift/commit/5ab5032d9dbc3f32884d44e449d19a5569122131))
* **postgrest:** quote JSON path keys and add an Int array-index overload ([#1498](https://github.com/supabase/supabase-swift/issues/1498)) ([db53237](https://github.com/supabase/supabase-swift/commit/db53237798004192340b740a0b8394a1fc4b66ba))
* **postgrest:** reject nil filter operands at compile time ([#1238](https://github.com/supabase/supabase-swift/issues/1238)) ([61f6fb4](https://github.com/supabase/supabase-swift/commit/61f6fb44b701d32185ff0545a248c727b8765e27))
* **postgrest:** return PostgrestTransformBuilder from legacy insert and upsert ([#1420](https://github.com/supabase/supabase-swift/issues/1420)) ([25b4410](https://github.com/supabase/supabase-swift/commit/25b441093eacb15ac4f775a883732e30990ad52b))
* **postgrest:** strip nulls through the Accept media type, not Prefer ([#1382](https://github.com/supabase/supabase-swift/issues/1382)) ([d7fd461](https://github.com/supabase/supabase-swift/commit/d7fd461ca83ff8e90e617dcfd465909c038574fe))
* **postgrest:** surface a throwing access-token provider as a PostgrestError ([#1465](https://github.com/supabase/supabase-swift/issues/1465)) ([4573907](https://github.com/supabase/supabase-swift/commit/4573907943cde737a9c2b4396f89f1fcc85a36d6))
* **postgrest:** throw on multi-row result from maybeSingle when throw-on-error is enabled ([#1180](https://github.com/supabase/supabase-swift/issues/1180)) ([3b2730e](https://github.com/supabase/supabase-swift/commit/3b2730e02af60565573b81249d2bbd173e578a0b))
* **realtime:** classify channel join errors and fail fast on fatal ones ([#1614](https://github.com/supabase/supabase-swift/issues/1614)) ([76c8a69](https://github.com/supabase/supabase-swift/commit/76c8a690bd3e8c199288244f9caf81a76687cbdf))
* **realtime:** close WebSocket connection on RealtimeClientV2 deinit ([#1192](https://github.com/supabase/supabase-swift/issues/1192)) ([c7d17c7](https://github.com/supabase/supabase-swift/commit/c7d17c7d4df7dba14893a61c89393d8981adeb63))
* **realtime:** don't rejoin a channel the caller unsubscribed across a reconnect ([#1601](https://github.com/supabase/supabase-swift/issues/1601)) ([7567bd1](https://github.com/supabase/supabase-swift/commit/7567bd1bb4005e982394ff99e0af6cbefe8b3375))
* **realtime:** end a cancelled connect() or subscribe() wait at once ([#1653](https://github.com/supabase/supabase-swift/issues/1653)) ([8f67b45](https://github.com/supabase/supabase-swift/commit/8f67b458cfc78ba2bfb0fe2d1e0a731fc49a2baf))
* **realtime:** httpSend sends the configured headers, and Authorization only with a token ([#1780](https://github.com/supabase/supabase-swift/issues/1780)) ([3058fea](https://github.com/supabase/supabase-swift/commit/3058feaa7f0edda6d814c4b49f0e08036aa782d6))
* **realtime:** import HTTPTypes with an explicit access level ([#1648](https://github.com/supabase/supabase-swift/issues/1648)) ([522db81](https://github.com/supabase/supabase-swift/commit/522db81f4083e51d2b136c901bc9516fdfe87aba)), closes [#1647](https://github.com/supabase/supabase-swift/issues/1647)
* **realtime:** let a subscribed channel join again after disconnect() ([#1669](https://github.com/supabase/supabase-swift/issues/1669)) ([78918f4](https://github.com/supabase/supabase-swift/commit/78918f41ccb719ee6fa2323dbd65c19918ee1437))
* **realtime:** rejoin a channel after a server phx_error ([#1744](https://github.com/supabase/supabase-swift/issues/1744)) ([d0b82f9](https://github.com/supabase/supabase-swift/commit/d0b82f963a5efdefbe84f3b8bb5547dd149ce9b1))
* **realtime:** retry auto-reconnect with backoff instead of giving up after one attempt ([#1198](https://github.com/supabase/supabase-swift/issues/1198)) ([0ee6089](https://github.com/supabase/supabase-swift/commit/0ee608976c0dbd42ad4a491ec0d846f0834ba1f6))
* **realtime:** stale subscribe no longer resets the rejoined channel ([#1578](https://github.com/supabase/supabase-swift/issues/1578)) ([79e5cd0](https://github.com/supabase/supabase-swift/commit/79e5cd07af6af15296b2dd4400cd9eef00b442d5))
* **realtime:** throw invalidRequest from broadcast when a header field is over 255 bytes ([#1788](https://github.com/supabase/supabase-swift/issues/1788)) ([d51f4df](https://github.com/supabase/supabase-swift/commit/d51f4df3cca5158877b901a1d8eae55c840fa150))
* **release:** select the prerelease versioning strategy ([#1202](https://github.com/supabase/supabase-swift/issues/1202)) ([9212b0d](https://github.com/supabase/supabase-swift/commit/9212b0dcd25d4be28dd41f0b9ff3252ce36c8908))
* **security:** redact secrets in the logs of every module, not only Auth ([#1751](https://github.com/supabase/supabase-swift/issues/1751)) ([a1e004b](https://github.com/supabase/supabase-swift/commit/a1e004b588c6867e02debef317171016cfc09bd0))
* shared error kinds, and wrap every client-side refusal as `.invalidRequest` ([#1778](https://github.com/supabase/supabase-swift/issues/1778)) ([31b1087](https://github.com/supabase/supabase-swift/commit/31b10874fd0d6166f1814f363d0cd94009ffbfcd))
* split Package.swift by tools-version for the swift-issue-reporting migration ([#1393](https://github.com/supabase/supabase-swift/issues/1393)) ([d3215d9](https://github.com/supabase/supabase-swift/commit/d3215d988bf1931d08a2e2c8c6c2a32954fb691d))
* stop sending backend-default values on the wire (Prefer return=, listUsers/listClients paging) ([#1419](https://github.com/supabase/supabase-swift/issues/1419)) ([274668b](https://github.com/supabase/supabase-swift/commit/274668b5c60248ebd8a1d08df1170fbfa7c62fde))
* **storage:** cancel() during start() removes the resumable record and server upload ([#1792](https://github.com/supabase/supabase-swift/issues/1792)) ([2296df9](https://github.com/supabase/supabase-swift/commit/2296df90730ad329519153eea139fcf698c0883d))
* **storage:** clean object paths sent in request bodies ([#1441](https://github.com/supabase/supabase-swift/issues/1441)) ([a2b5ab2](https://github.com/supabase/supabase-swift/commit/a2b5ab22636fdf2229da196c02de9c4fc5bb56a4))
* **storage:** clean object paths sent in the request URL ([#1463](https://github.com/supabase/supabase-swift/issues/1463)) ([ffec207](https://github.com/supabase/supabase-swift/commit/ffec207dc2fa0d68623782691cde1c28a36e0c88))
* **storage:** derive content type for signed URL uploads ([#1158](https://github.com/supabase/supabase-swift/issues/1158)) ([1b6071c](https://github.com/supabase/supabase-swift/commit/1b6071c18e4c01d79033d89f16e9a3a3a1f50874))
* **storage:** drop encoder/decoder customization ([#1247](https://github.com/supabase/supabase-swift/issues/1247)) ([353e87d](https://github.com/supabase/supabase-swift/commit/353e87db6937ebaa67eb04d5c2bf0ec37d0853f5))
* **storage:** every concurrent ResumableUpload.cancel() waits for the cleanup ([#1799](https://github.com/supabase/supabase-swift/issues/1799)) ([4954194](https://github.com/supabase/supabase-swift/commit/4954194971f21a7e8fb811e0b1dc29108e79b7c2))
* **storage:** exists(path:) reads object/info and is false only for NoSuchKey ([#1509](https://github.com/supabase/supabase-swift/issues/1509)) ([270c2c9](https://github.com/supabase/supabase-swift/commit/270c2c96338930dafa8675726b5748091e4b8836))
* **storage:** forward resumable options, skip empty sign transform, document listing retries ([#1568](https://github.com/supabase/supabase-swift/issues/1568)) ([1e45699](https://github.com/supabase/supabase-swift/commit/1e4569915a53de3c1948298eebb2c8676786b7ca))
* **storage:** one corrupt resumable-upload record no longer blocks pending, resumeAll, and clear ([#1768](https://github.com/supabase/supabase-swift/issues/1768)) ([caac297](https://github.com/supabase/supabase-swift/commit/caac2979f053bb95e5ba8e59a955cdce7ddb3e65))
* **storage:** rename purgeCache includingTransformations to transformationsOnly ([#1656](https://github.com/supabase/supabase-swift/issues/1656)) ([47feaaf](https://github.com/supabase/supabase-swift/commit/47feaaf28b5ea9a5fcb354d9b1eef4f5da462da9))
* **storage:** resumable upload cancel on a pending handle and resume after a failed start ([#1802](https://github.com/supabase/supabase-swift/issues/1802)) ([68ee583](https://github.com/supabase/supabase-swift/commit/68ee583745054ab0e311f9261de4e94340041199))
* **storage:** throw CancellationError when the caller's task is cancelled ([#1434](https://github.com/supabase/supabase-swift/issues/1434)) ([f28731f](https://github.com/supabase/supabase-swift/commit/f28731f3c1c610a18987a9481f7356d07ebc0038))
* **supabase:** do not build realtime on auth events; keep the user logger ([#1664](https://github.com/supabase/supabase-swift/issues/1664)) ([5f5f03b](https://github.com/supabase/supabase-swift/commit/5f5f03b34b00f0e05826bae7d24669dd515ac0da))
* **supabase:** one resolver passes shared settings to every sub-client ([#1782](https://github.com/supabase/supabase-swift/issues/1782)) ([7773387](https://github.com/supabase/supabase-swift/commit/77733879dd80d439a6b759c84adb346682cf1cd3))
* **supabase:** propagate access-token provider errors instead of swallowing them ([#1236](https://github.com/supabase/supabase-swift/issues/1236)) ([84f3370](https://github.com/supabase/supabase-swift/commit/84f3370a9dc5d1ac7c1855b1fabab825781480de))
* **supabase:** share one refresh when a refresh commits during the retry check ([#1707](https://github.com/supabase/supabase-swift/issues/1707)) ([973477c](https://github.com/supabase/supabase-swift/commit/973477c71664f4c22e2770ab691e98eedc985216))
* **supabase:** stop listenForAuthEvents task from leaking SupabaseClient ([#1191](https://github.com/supabase/supabase-swift/issues/1191)) ([99cb526](https://github.com/supabase/supabase-swift/commit/99cb526312e1c4ff496ed5152153af95d5e6e2c0)), closes [#1187](https://github.com/supabase/supabase-swift/issues/1187)
* **tests:** avoid persisting WebSocket test identities in login keychain ([#1430](https://github.com/supabase/supabase-swift/issues/1430)) ([d0af657](https://github.com/supabase/supabase-swift/commit/d0af657f90facee1daea0e1e4c4ca35e28244537))
* **tests:** make request snapshot assertions actually fail ([#1239](https://github.com/supabase/supabase-swift/issues/1239)) ([72b36cc](https://github.com/supabase/supabase-swift/commit/72b36cc8f6f54eece8b62fa22400f43ad3780a6b))
* **typegen:** emit nonisolated Columns extensions for computed fields and relationships ([#1748](https://github.com/supabase/supabase-swift/issues/1748)) ([a1f2a47](https://github.com/supabase/supabase-swift/commit/a1f2a479bdb10ad80e69704bcc7765973602c144))


### Performance Improvements

* **helpers:** stream request bodies instead of buffering them before upload ([#1342](https://github.com/supabase/supabase-swift/issues/1342)) ([a61ef23](https://github.com/supabase/supabase-swift/commit/a61ef238da3a1f2a489a27743c58ee186f9c5b8e))
* **helpers:** tell URLSession how many bytes an upload will send ([#1435](https://github.com/supabase/supabase-swift/issues/1435)) ([74ef040](https://github.com/supabase/supabase-swift/commit/74ef04097b129ee1d7527a060032e58fbce9b3c7))
* **postgrest:** encode and decode _PostgresBytes hex without a String per byte ([#1574](https://github.com/supabase/supabase-swift/issues/1574)) ([be56881](https://github.com/supabase/supabase-swift/commit/be568819dbdbf2b47f99682f36938d450a4fa28a))
* **realtime:** route inbound frames through a per-topic channel index ([#1723](https://github.com/supabase/supabase-swift/issues/1723)) ([da1a258](https://github.com/supabase/supabase-swift/commit/da1a25863d9291d6c236af1710b06dfb2c70248b))


### Documentation

* **postgrest:** correct the bulk-insert columns doc comment ([#1423](https://github.com/supabase/supabase-swift/issues/1423)) ([f6e5a67](https://github.com/supabase/supabase-swift/commit/f6e5a67e702f7e93481f6ea70829bd48559f1326))


### Miscellaneous Chores

* configure v3 beta prereleases and document migration-guide policy ([#1199](https://github.com/supabase/supabase-swift/issues/1199)) ([f6687c5](https://github.com/supabase/supabase-swift/commit/f6687c522d545ecb4a9b98470a1e2f7ecac61d0b))
* **deps:** require swift-crypto 4.0.0 and its CryptoExtras product ([#1687](https://github.com/supabase/supabase-swift/issues/1687)) ([981ebb2](https://github.com/supabase/supabase-swift/commit/981ebb28bf216a0b2ff6367a00d3b74f960c71ea))
* enable NonisolatedNonsendingByDefault for every SDK target ([#1429](https://github.com/supabase/supabase-swift/issues/1429)) ([214043d](https://github.com/supabase/supabase-swift/commit/214043d6e7b1c77bd280fcbcf7cf1824f296b8a9))
* **realtime:** remove v2 leftovers and finalize the Realtime v3 migration guide ([#1667](https://github.com/supabase/supabase-swift/issues/1667)) ([2fcabed](https://github.com/supabase/supabase-swift/commit/2fcabede9b16246ce14e38757cb6ec1f06334d3c))


### Code Refactoring

* align the public API with the Swift API Design Guidelines ([#1355](https://github.com/supabase/supabase-swift/issues/1355)) ([5beafd9](https://github.com/supabase/supabase-swift/commit/5beafd9a7eeec0ee40fcef882e0bf12860ff8499))
* **auth:** admin API naming, payload labels, and type suffixes ([#1783](https://github.com/supabase/supabase-swift/issues/1783)) ([2ee84f6](https://github.com/supabase/supabase-swift/commit/2ee84f64d12f2276d35dea533c7bc860a9fc9428))
* **auth:** bridge AuthClient onto SessionStore ([#1628](https://github.com/supabase/supabase-swift/issues/1628)) ([737b25d](https://github.com/supabase/supabase-swift/commit/737b25d90b3c714f4df1bfa9ccfa4e8fa3279edb))
* **auth:** make AuthClient a final class instead of an actor ([#1396](https://github.com/supabase/supabase-swift/issues/1396)) ([4d12dbf](https://github.com/supabase/supabase-swift/commit/4d12dbfd28bb2989a561fb22af89fca9783d7a7c))
* **auth:** move the refresh single-flight into SessionStore with cooldown and refresh window ([#1633](https://github.com/supabase/supabase-swift/issues/1633)) ([1e0e16a](https://github.com/supabase/supabase-swift/commit/1e0e16a1e54588761c57b9cd21ff675c86b526d5))
* **auth:** simplify Phase 2 session internals ([#1644](https://github.com/supabase/supabase-swift/issues/1644)) ([0b5032e](https://github.com/supabase/supabase-swift/commit/0b5032e4001c602037f12d074dc2b860e9bb0a8c))
* **auth:** uppercase ID, URL, and URI in public names; explicit CodingKeys, no key strategy ([#1757](https://github.com/supabase/supabase-swift/issues/1757)) ([4a6bd71](https://github.com/supabase/supabase-swift/commit/4a6bd71fa7131d588cbda1f5f81ee5218b3cac34))
* code: &lt;Module&gt;Error.Code? in every error, and one open-set shape ([#1767](https://github.com/supabase/supabase-swift/issues/1767)) ([0e7e07b](https://github.com/supabase/supabase-swift/commit/0e7e07bfd7ddfcfe203daebae532d696c19fc204))
* convert seven open-set enums to RawRepresentable structs ([#1409](https://github.com/supabase/supabase-swift/issues/1409)) ([ec1118e](https://github.com/supabase/supabase-swift/commit/ec1118eaa4c61d0d1a814668f95d1828d668484b))
* **functions:** make FunctionsClient stateless and a struct ([#1233](https://github.com/supabase/supabase-swift/issues/1233)) ([88a5efe](https://github.com/supabase/supabase-swift/commit/88a5efe7d0f533f5d432164d91e8d67a1e18f9db))
* **helpers:** keep a JSON number's exact digits in JSONValue ([#1790](https://github.com/supabase/supabase-swift/issues/1790)) ([1cd4511](https://github.com/supabase/supabase-swift/commit/1cd45114e743a286221c1e403b30e7539fedc3ee))
* **helpers:** rename AnyJSON to JSONValue ([#1232](https://github.com/supabase/supabase-swift/issues/1232)) ([9f40f8f](https://github.com/supabase/supabase-swift/commit/9f40f8fa4b0621753be5d31076dc507449ca5e13))
* move optional request settings into per-method options structs ([#1736](https://github.com/supabase/supabase-swift/issues/1736)) ([f23e6e4](https://github.com/supabase/supabase-swift/commit/f23e6e44d919c66feabfb75c9289afd6a6ad90fe))
* one field layout for response wrappers (status, headers, body, requestID) ([#1755](https://github.com/supabase/supabase-swift/issues/1755)) ([2aef2e0](https://github.com/supabase/supabase-swift/commit/2aef2e071b28f42ffa0bfb1e5301f38025d8139a))
* one name per setting across the facade and the modules ([#1770](https://github.com/supabase/supabase-swift/issues/1770)) ([84debe6](https://github.com/supabase/supabase-swift/commit/84debe6e1bedd8a73e4c6bd5403bf0fc9bd105de))
* one paged AsyncSequence shape (PageSequence) for Auth and Storage ([#1759](https://github.com/supabase/supabase-swift/issues/1759)) ([d78fc03](https://github.com/supabase/supabase-swift/commit/d78fc03ba97eb6777066b4ffc956e054051a825e))
* one policy for event types and status streams (openness, replay, naming) ([#1773](https://github.com/supabase/supabase-swift/issues/1773)) ([5623162](https://github.com/supabase/supabase-swift/commit/562316227d066b5689fc53005e81426a3a8f9b31))
* one type and one name per concept, in both directions ([#1781](https://github.com/supabase/supabase-swift/issues/1781)) ([53ae692](https://github.com/supabase/supabase-swift/commit/53ae69247b13295273c1994c3f25bddd05b32201))
* per-call coders are X? = nil, and no public shared coder instances ([#1769](https://github.com/supabase/supabase-swift/issues/1769)) ([65b3547](https://github.com/supabase/supabase-swift/commit/65b35478e0f845d31b35414166759ff41eba3de7))
* **postgrest:** make client and builders stateless value types ([#1240](https://github.com/supabase/supabase-swift/issues/1240)) ([b52d385](https://github.com/supabase/supabase-swift/commit/b52d385ce55719ace132bb321c19337cbc556668))
* **postgrest:** move PostgrestError to PostgREST, delete ObservationToken ([#1753](https://github.com/supabase/supabase-swift/issues/1753)) ([cefe278](https://github.com/supabase/supabase-swift/commit/cefe2789bb80958a5c7f18fa160c8670b3829465))
* **postgrest:** move today's builders under Legacy/ ([#1267](https://github.com/supabase/supabase-swift/issues/1267)) ([d96ed5d](https://github.com/supabase/supabase-swift/commit/d96ed5d4b1c49b8cdfa3a8b1b8a09f4eb065c58d))
* **realtime:** boolean settings read as assertions ([#1786](https://github.com/supabase/supabase-swift/issues/1786)) ([fff4710](https://github.com/supabase/supabase-swift/commit/fff4710745945066bd64e2cbc9acb1eeb2fda7e0))
* **realtime:** full-jitter reconnect with attempt and error in the connection state ([#1605](https://github.com/supabase/supabase-swift/issues/1605)) ([313fd9c](https://github.com/supabase/supabase-swift/commit/313fd9c803f6de9db3067700e63e147761ed5c95))
* remove all deprecated pre-v3 APIs ([#1206](https://github.com/supabase/supabase-swift/issues/1206)) ([6182b19](https://github.com/supabase/supabase-swift/commit/6182b195699d7cc5e38f82008f0b4da528cd1de8))
* replace SupabaseLogger with swift-log (SDK-1412) ([#1210](https://github.com/supabase/supabase-swift/issues/1210)) ([7325a6f](https://github.com/supabase/supabase-swift/commit/7325a6f1ffe11f087cc5920add57c36a77da53f4))
* **storage:** align remaining API with the Swift API Design Guidelines ([#1368](https://github.com/supabase/supabase-swift/issues/1368)) ([0e4b166](https://github.com/supabase/supabase-swift/commit/0e4b1661aa28fa1d068399d626891982f366ed01))
* **storage:** align the experimental (SPI) Storage APIs with the shared rules ([#1765](https://github.com/supabase/supabase-swift/issues/1765)) ([0520609](https://github.com/supabase/supabase-swift/commit/0520609a8f520cebeb9df1d8930da1338b4b6b5d))
* **storage:** make Storage client types stateless structs ([#1246](https://github.com/supabase/supabase-swift/issues/1246)) ([1dac92d](https://github.com/supabase/supabase-swift/commit/1dac92dff5d59a97bc35dcb43b28532a5a8214ef))
* **storage:** uppercase ID in public names ([#1756](https://github.com/supabase/supabase-swift/issues/1756)) ([01b4f8d](https://github.com/supabase/supabase-swift/commit/01b4f8dc5cbe488345f04c42f8ce2258e30bf273))
* **typegen:** emit ID, URL, URI, JWT and OTP in uppercase ([#1758](https://github.com/supabase/supabase-swift/issues/1758)) ([2a2785b](https://github.com/supabase/supabase-swift/commit/2a2785b24a56b0078d465b87aa97aa1dcee84588))
* use HTTPFields for every public header API, and share header names in Helpers ([#1774](https://github.com/supabase/supabase-swift/issues/1774)) ([732e097](https://github.com/supabase/supabase-swift/commit/732e0977b8b2f21cfdb30797eade6d8364df85a6))


### Tests

* **auth:** add a deterministic race suite for the session lifecycle ([#1642](https://github.com/supabase/supabase-swift/issues/1642)) ([fe89523](https://github.com/supabase/supabase-swift/commit/fe8952391d18146fb4e0c86c9127dc1ecdc5ddc4))
* **realtime:** run the Realtime suites on Linux, serially in CI, and fix a stale join-waiter cancellation ([#1598](https://github.com/supabase/supabase-swift/issues/1598)) ([990206e](https://github.com/supabase/supabase-swift/commit/990206e8bdaa9ea96a934eaa620276ec26685db9))

## [2.55.7](https://github.com/supabase/supabase-swift/compare/v2.55.6...v2.55.7) (2026-11-16)

### Bug Fixes

* **auth:** clear the stored session when a refresh is refused with user_banned ([#1631](https://github.com/supabase/supabase-swift/issues/1631)) ([37a4560](https://github.com/supabase/supabase-swift/commit/37a456047fdc7315d66c096fa7ce7e81d085aab7)), closes [#1613](https://github.com/supabase/supabase-swift/issues/1613)
* **auth:** exchangeCodeForSession fails before the request when the PKCE verifier is missing (v2 backport) ([#1681](https://github.com/supabase/supabase-swift/issues/1681)) ([0d92fea](https://github.com/supabase/supabase-swift/commit/0d92fea25b587f15eae0f50464df984618265809))
* **ci:** repair release/v2 integration tests and spell check ([#1825](https://github.com/supabase/supabase-swift/issues/1825)) ([c3258c6](https://github.com/supabase/supabase-swift/commit/c3258c699a6123218c5ffa47af2ae91cf7c4c1bd))
* **security:** redact secrets in verbose HTTP logs (v2 backport) ([#1822](https://github.com/supabase/supabase-swift/issues/1822)) ([3b96aea](https://github.com/supabase/supabase-swift/commit/3b96aea8d74d1e2fe5b59a683dc439d18af6d562)), closes [#1705](https://github.com/supabase/supabase-swift/issues/1705)

## [2.55.6](https://github.com/supabase/supabase-swift/compare/v2.55.5...v2.55.6) (2026-10-29)

### Bug Fixes

* **realtime:** import HTTPTypes with an explicit access level in RealtimeV2 ([#1649](https://github.com/supabase/supabase-swift/issues/1649)) ([f9c41ee](https://github.com/supabase/supabase-swift/commit/f9c41ee1bb30129d300dc3cc84e31bb18cc1a96a)), closes [#1647](https://github.com/supabase/supabase-swift/issues/1647)

## [2.55.5](https://github.com/supabase/supabase-swift/compare/v2.55.4...v2.55.5) (2026-10-26)

### Bug Fixes

* **ci:** compute coverage from this run's profile and every test bundle ([#1615](https://github.com/supabase/supabase-swift/issues/1615)) ([#1621](https://github.com/supabase/supabase-swift/issues/1621)) ([dcd45fd](https://github.com/supabase/supabase-swift/commit/dcd45fd8632659b16a2411cd98de3d638ab7b856))
* **realtime:** don't rejoin a channel the caller unsubscribed across a reconnect (v2 backport) ([#1602](https://github.com/supabase/supabase-swift/issues/1602)) ([bf3123c](https://github.com/supabase/supabase-swift/commit/bf3123ced6a96d7c90b2e42ecd11479635d96682))
* **realtime:** stale subscribe no longer resets the rejoined channel ([#1606](https://github.com/supabase/supabase-swift/issues/1606)) ([d16ddc7](https://github.com/supabase/supabase-swift/commit/d16ddc762474aa149cc0f2710b6b3289802e7ac5))

## [2.55.4](https://github.com/supabase/supabase-swift/compare/v2.55.3...v2.55.4) (2026-10-13)

### Bug Fixes

* **auth:** post admin invites to the /invite route the Auth server serves ([#1505](https://github.com/supabase/supabase-swift/issues/1505)) ([#1518](https://github.com/supabase/supabase-swift/issues/1518)) ([19528e2](https://github.com/supabase/supabase-swift/commit/19528e2edefb4735ffc9eea8a0e90b00dd5d3c5a))
* **ci:** bump swift-custom-dump pin in the workspace to 1.7.0 ([#1525](https://github.com/supabase/supabase-swift/issues/1525)) ([8cb9819](https://github.com/supabase/supabase-swift/commit/8cb9819ab16bb45236b579f1f794fd0587e2f7a0))
* **release:** stop release-please making beta prereleases on release/v2 ([#1522](https://github.com/supabase/supabase-swift/issues/1522)) ([6b214f7](https://github.com/supabase/supabase-swift/commit/6b214f71a643ede2ac07dbc0b38faeb26810e741))

## [2.55.3](https://github.com/supabase/supabase-swift/compare/v2.55.2...v2.55.3) (2026-09-29)

### Bug Fixes

* **auth:** discard a token refresh that outlived its session ([#1374](https://github.com/supabase/supabase-swift/issues/1374)) ([#1389](https://github.com/supabase/supabase-swift/issues/1389)) ([8edd308](https://github.com/supabase/supabase-swift/commit/8edd308d8f5cfdb367fb8b9618225a270ea3d3e7))

## [2.55.2](https://github.com/supabase/supabase-swift/compare/v2.55.1...v2.55.2) (2026-09-09)

### Bug Fixes

* **auth:** send skip_http_redirect so signInWithSSO gets JSON instead of a 303 ([#1322](https://github.com/supabase/supabase-swift/issues/1322)) ([4d21170](https://github.com/supabase/supabase-swift/commit/4d21170308f966a354a4e7e9a381705d4fa473d5))


## [2.55.1](https://github.com/supabase/supabase-swift/compare/v2.55.0...v2.55.1) (2026-08-13)

### Bug Fixes

* **release:** select the prerelease versioning strategy ([#1202](https://github.com/supabase/supabase-swift/issues/1202)) ([9212b0d](https://github.com/supabase/supabase-swift/commit/9212b0dcd25d4be28dd41f0b9ff3252ce36c8908))


### Miscellaneous Chores

* configure v3 beta prereleases and document migration-guide policy ([#1199](https://github.com/supabase/supabase-swift/issues/1199)) ([f6687c5](https://github.com/supabase/supabase-swift/commit/f6687c522d545ecb4a9b98470a1e2f7ecac61d0b))

## [2.55.0](https://github.com/supabase/supabase-swift/compare/v2.54.1...v2.55.0) (2026-08-12)


### Features

* **storage:** add vector bucket CRUD (alpha) ([#1153](https://github.com/supabase/supabase-swift/issues/1153)) ([a4ad8af](https://github.com/supabase/supabase-swift/commit/a4ad8af5077453056adfd7805392ee81bb0764ca))
* **storage:** add vector index and vector data operations (alpha) ([#1181](https://github.com/supabase/supabase-swift/issues/1181)) ([3882e79](https://github.com/supabase/supabase-swift/commit/3882e7901cbcca98c5ec3eb82b519143a3aa1a0d))


### Bug Fixes

* **auth:** keep adminClient alive across awaited signOut in integration test ([#1178](https://github.com/supabase/supabase-swift/issues/1178)) ([c5d0671](https://github.com/supabase/supabase-swift/commit/c5d0671d1fa275751af3ce80e73194aa139eaa31))
* **auth:** remove AuthClient from Dependencies registry on deinit ([#1176](https://github.com/supabase/supabase-swift/issues/1176)) ([0826b28](https://github.com/supabase/supabase-swift/commit/0826b287b85ee7999cc25bb5b07ba5637984a439))
* **auth:** stop auto-refresh task on AuthClient deinit ([#1193](https://github.com/supabase/supabase-swift/issues/1193)) ([c6a5d99](https://github.com/supabase/supabase-swift/commit/c6a5d99a204c17da2f4db8555edcc27f46b8f2cd))
* flaky CI in AuthTests and RealtimeTests ([#1164](https://github.com/supabase/supabase-swift/issues/1164)) ([3585688](https://github.com/supabase/supabase-swift/commit/358568852992c3b5cc05567f11f6d885a0d52eba))
* **functions:** invalidate URLSession in streamed response ([#1122](https://github.com/supabase/supabase-swift/issues/1122)) ([68a78ab](https://github.com/supabase/supabase-swift/commit/68a78abefd5b2d1af89e96052bb271e9dd68ad10))
* **helpers:** extend Swift version detection ladder, drop unsupported floors ([#1160](https://github.com/supabase/supabase-swift/issues/1160)) ([186daf0](https://github.com/supabase/supabase-swift/commit/186daf067cdfa3c6361514a66303b2cd61465b6e))
* **postgrest:** decode PostgrestError details field ([#1159](https://github.com/supabase/supabase-swift/issues/1159)) ([b9296f6](https://github.com/supabase/supabase-swift/commit/b9296f62344db6678f5f7562062d4ddc8f2ff796))
* **postgrest:** escape reserved characters in array filter values ([#1126](https://github.com/supabase/supabase-swift/issues/1126)) ([e0ef7b3](https://github.com/supabase/supabase-swift/commit/e0ef7b393f49c73f7fe2997e823e76c0e28f5e30))
* **postgrest:** throw on multi-row result from maybeSingle when throw-on-error is enabled ([#1180](https://github.com/supabase/supabase-swift/issues/1180)) ([3b2730e](https://github.com/supabase/supabase-swift/commit/3b2730e02af60565573b81249d2bbd173e578a0b))
* **realtime:** close WebSocket connection on RealtimeClientV2 deinit ([#1192](https://github.com/supabase/supabase-swift/issues/1192)) ([c7d17c7](https://github.com/supabase/supabase-swift/commit/c7d17c7d4df7dba14893a61c89393d8981adeb63))
* **realtime:** rejoin channels concurrently on reconnect ([#1110](https://github.com/supabase/supabase-swift/issues/1110)) ([3a47076](https://github.com/supabase/supabase-swift/commit/3a470765efc442e5ea92f89011bef370c59e3b60))
* **realtime:** retry auto-reconnect with backoff instead of giving up after one attempt ([#1198](https://github.com/supabase/supabase-swift/issues/1198)) ([0ee6089](https://github.com/supabase/supabase-swift/commit/0ee608976c0dbd42ad4a491ec0d846f0834ba1f6))
* **storage:** derive content type for signed URL uploads ([#1158](https://github.com/supabase/supabase-swift/issues/1158)) ([1b6071c](https://github.com/supabase/supabase-swift/commit/1b6071c18e4c01d79033d89f16e9a3a3a1f50874))
* **supabase:** stop listenForAuthEvents task from leaking SupabaseClient ([#1191](https://github.com/supabase/supabase-swift/issues/1191)) ([99cb526](https://github.com/supabase/supabase-swift/commit/99cb526312e1c4ff496ed5152153af95d5e6e2c0)), closes [#1187](https://github.com/supabase/supabase-swift/issues/1187)

## [2.54.1](https://github.com/supabase/supabase-swift/compare/v2.54.0...v2.54.1) (2026-07-29)


### Bug Fixes

* **realtime:** fix AsyncValueSubject deadlock, then inline and delete it ([#1155](https://github.com/supabase/supabase-swift/issues/1155)) ([0e91b2f](https://github.com/supabase/supabase-swift/commit/0e91b2f00cfe8aaa4dd5f489a7f22c4abcfc8a2d))
* **realtime:** resume WebSocket continuations outside the lock ([#1156](https://github.com/supabase/supabase-swift/issues/1156)) ([625a278](https://github.com/supabase/supabase-swift/commit/625a278d49050507c5616be27fed93bb735d4f99))

## [2.54.0](https://github.com/supabase/supabase-swift/compare/v2.53.0...v2.54.0) (2026-07-27)


### Features

* **auth:** add admin generateLink and signOut ([#1152](https://github.com/supabase/supabase-swift/issues/1152)) ([f82b248](https://github.com/supabase/supabase-swift/commit/f82b2481b944342f9149cc6d43f64ceda5515711))
* **auth:** add admin passkey list/delete methods ([#1137](https://github.com/supabase/supabase-swift/issues/1137)) ([99114ee](https://github.com/supabase/supabase-swift/commit/99114eeed0c6fd965d471d52622de79db20c08e3))
* **auth:** add signInWithWeb3 (Sign in with Ethereum / Solana) ([#1138](https://github.com/supabase/supabase-swift/issues/1138)) ([d364154](https://github.com/supabase/supabase-swift/commit/d3641540c792e797460fbce5a8bab3695b71654c))
* **functions:** add per-invocation timeout override ([#1144](https://github.com/supabase/supabase-swift/issues/1144)) ([9453077](https://github.com/supabase/supabase-swift/commit/9453077cb80f3b636fdcde745adee579f4e59fa3))
* **functions:** replace FunctionRegion enum with open struct ([#1053](https://github.com/supabase/supabase-swift/issues/1053)) ([102eaf7](https://github.com/supabase/supabase-swift/commit/102eaf71ab76750ee145f4354cacd87fc977bf3a))


### Bug Fixes

* **functions:** check x-relay-error before response status ([#1112](https://github.com/supabase/supabase-swift/issues/1112)) ([ee58fc3](https://github.com/supabase/supabase-swift/commit/ee58fc36b9094b4f9dc7d8cdaf87f6868a667917))
* **realtime:** make subscribe converge after a failed auto-reconnect ([#1146](https://github.com/supabase/supabase-swift/issues/1146)) ([1e0fe6f](https://github.com/supabase/supabase-swift/commit/1e0fe6f313b2c0c2a318d304e27c7e17064b8599)), closes [#1148](https://github.com/supabase/supabase-swift/issues/1148)
* **test:** align Web3 integration tests with Swift Testing migration ([#1140](https://github.com/supabase/supabase-swift/issues/1140)) ([bfb761b](https://github.com/supabase/supabase-swift/commit/bfb761bfe1ae27094a3d3858e9e03b49dd13248e))

## [2.53.0](https://github.com/supabase/supabase-swift/compare/v2.52.0...v2.53.0) (2026-07-21)


### Features

* **auth:** add OAuth 2.1 authorization server support ([#1115](https://github.com/supabase/supabase-swift/issues/1115)) ([4132009](https://github.com/supabase/supabase-swift/commit/4132009258a1320095c89ccc299f902fdfeee7ca))
* **postgrest:** add notIn filter, dryRun and maybeSingle modifiers ([#1114](https://github.com/supabase/supabase-swift/issues/1114)) ([0bbdbec](https://github.com/supabase/supabase-swift/commit/0bbdbecba9b4161e1936f0d1032ff0901f0359f1))
* **realtime:** support certificate pinning on the WebSocket connection ([#1123](https://github.com/supabase/supabase-swift/issues/1123)) ([b74a8fa](https://github.com/supabase/supabase-swift/commit/b74a8fac4c7792bc741ca90592e0b01784399dbe))


### Bug Fixes

* **client,functions:** warn instead of throw on unrecognized sb_ key subtype; never send new-format key as Bearer ([#1130](https://github.com/supabase/supabase-swift/issues/1130)) ([286ce5f](https://github.com/supabase/supabase-swift/commit/286ce5f1d19f9b42bcf9256993d42c44612a0184))
* **helpers:** await full retry backoff delay instead of truncating to whole seconds ([#1125](https://github.com/supabase/supabase-swift/issues/1125)) ([f6d39cb](https://github.com/supabase/supabase-swift/commit/f6d39cb1a05ea27ccc58bb1a259ad2a3b7844acf))
* **realtime:** don't leak disconnected heartbeat status to consumers ([#1129](https://github.com/supabase/supabase-swift/issues/1129)) ([dc37cd6](https://github.com/supabase/supabase-swift/commit/dc37cd612c718adc7ceb45b7b2cefe5b4bf82e62))
* **realtime:** invalidate dedicated session when connect fails before opening ([#1134](https://github.com/supabase/supabase-swift/issues/1134)) ([bbf3533](https://github.com/supabase/supabase-swift/commit/bbf3533241eb8f8ed4f5873679356e6682b6d90a))

## [2.52.0](https://github.com/supabase/supabase-swift/compare/v2.51.0...v2.52.0) (2026-07-13)


### Features

* **supabase:** add W3C trace context propagation via OpenTelemetry trait ([#1101](https://github.com/supabase/supabase-swift/issues/1101)) ([8f147ec](https://github.com/supabase/supabase-swift/commit/8f147ecc9ff5f64746203f58c342b06587e0f354))


### Bug Fixes

* **postgrest:** preserve existing Prefer header in select(count:) ([#1107](https://github.com/supabase/supabase-swift/issues/1107)) ([6ff542a](https://github.com/supabase/supabase-swift/commit/6ff542a955c12cc3a0397e2168cb1f008f8f85e2))
* **realtime:** reset channel state on phx_error ([#1109](https://github.com/supabase/supabase-swift/issues/1109)) ([a4b0f04](https://github.com/supabase/supabase-swift/commit/a4b0f042b0e22188fcaef58fb53b5ef705a0c60f))
* **storage:** clean path in signed upload URL and response ([#1108](https://github.com/supabase/supabase-swift/issues/1108)) ([ebef170](https://github.com/supabase/supabase-swift/commit/ebef170a4a6820d064e5909dd4f54e4341f12eb5))
* **storage:** honor options.contentType for fileURL uploads ([#1124](https://github.com/supabase/supabase-swift/issues/1124)) ([bd33aad](https://github.com/supabase/supabase-swift/commit/bd33aadd570837cf50d3091e26503bca3aed2499))
* **storage:** return cleaned path in upload response ([#1104](https://github.com/supabase/supabase-swift/issues/1104)) ([ba23665](https://github.com/supabase/supabase-swift/commit/ba2366564ef983de765f654d14d198e1cc57e896))
* **storage:** strip leading slash from object paths ([#1111](https://github.com/supabase/supabase-swift/issues/1111)) ([ae8c467](https://github.com/supabase/supabase-swift/commit/ae8c4678691c3ce96e24b58bf2f14ff94f783949))

## [2.51.0](https://github.com/supabase/supabase-swift/compare/v2.50.0...v2.51.0) (2026-07-08)


### Features

* **realtime:** update httpSend() to per-event broadcast URL format with binary support ([#1086](https://github.com/supabase/supabase-swift/issues/1086)) ([adb4928](https://github.com/supabase/supabase-swift/commit/adb4928dd556f9af4409fe56ee13cad5b7519583))


### Bug Fixes

* **auth:** harden RSA JWK verification against malformed keys ([#1079](https://github.com/supabase/supabase-swift/issues/1079)) ([8b29aeb](https://github.com/supabase/supabase-swift/commit/8b29aeb5cc65733b011083cfad2604550adeea44))
* **auth:** include code_challenge in resend() when using PKCE flow ([#1085](https://github.com/supabase/supabase-swift/issues/1085)) ([c781371](https://github.com/supabase/supabase-swift/commit/c78137130f36b3c11b83e0e5d93be1e07a8aa416))
* **postgrest:** encode rpc GET/HEAD scalar params by JSON type ([#1092](https://github.com/supabase/supabase-swift/issues/1092)) ([6e53a6f](https://github.com/supabase/supabase-swift/commit/6e53a6f36982294c9b1d44ff543dce58281f3b10))
* **realtime:** keep current access token when token fetch fails in setAuth ([#1077](https://github.com/supabase/supabase-swift/issues/1077)) ([e62ebe0](https://github.com/supabase/supabase-swift/commit/e62ebe0901b87caa49db41c466f9b015cdc6bcde))
* **storage:** preserve limit/offset defaults when list() receives partial options ([#1087](https://github.com/supabase/supabase-swift/issues/1087)) ([0e859d6](https://github.com/supabase/supabase-swift/commit/0e859d69b024933fea25487508b15c65be6424f9))
* **storage:** preserve sortBy defaults when list() receives partial sortBy ([#1084](https://github.com/supabase/supabase-swift/issues/1084)) ([ccd33f2](https://github.com/supabase/supabase-swift/commit/ccd33f27d42f2ffaf8f72f885e832bb33fa52d7c))

## [2.50.0](https://github.com/supabase/supabase-swift/compare/v2.49.0...v2.50.0) (2026-07-06)


### Features

* drop Swift 5.10 support and require Swift 6.1+ ([#1066](https://github.com/supabase/supabase-swift/issues/1066)) ([1ba29f6](https://github.com/supabase/supabase-swift/commit/1ba29f606cea63fdb71bb638d4653eff49e8bbf6))
* raise minimum platform versions to iOS 16 and equivalents ([#1067](https://github.com/supabase/supabase-swift/issues/1067)) ([9e292aa](https://github.com/supabase/supabase-swift/commit/9e292aa0bde4d7923a341cd5f81a392a446a64fe))


### Bug Fixes

* **auth:** decode callback URL params once, with form semantics ([#1070](https://github.com/supabase/supabase-swift/issues/1070)) ([3b749aa](https://github.com/supabase/supabase-swift/commit/3b749aaef919d873c1340d9b06c6e9e9d7326e54))
* **postgrest:** quote column names in insert()/upsert() columns list ([#1068](https://github.com/supabase/supabase-swift/issues/1068)) ([6350a1c](https://github.com/supabase/supabase-swift/commit/6350a1c0f5927ceb78df00b8a27bc00fb8c017d4))
* **realtime:** break retain cycle in heartbeat task ([#1078](https://github.com/supabase/supabase-swift/issues/1078)) ([5df4044](https://github.com/supabase/supabase-swift/commit/5df404499e8e8a41d763687d1dfa91e2afb9744c))
* **realtime:** send bare topic in broadcast REST body ([#1065](https://github.com/supabase/supabase-swift/issues/1065)) ([94f3895](https://github.com/supabase/supabase-swift/commit/94f389500a08f0c7ab7dade2b00b2a013651cd48))

## [2.49.0](https://github.com/supabase/supabase-swift/compare/v2.48.0...v2.49.0) (2026-07-03)


### Features

* **postgrest:** add ExplainFormat enum for explain(format:) ([#1050](https://github.com/supabase/supabase-swift/issues/1050)) ([441abb8](https://github.com/supabase/supabase-swift/commit/441abb80294c6f4b37820de1b2c21402a5830e1f))
* **realtime:** support replication-ready system event, new postgres_changes filter operators, and broadcast `select` option ([#1063](https://github.com/supabase/supabase-swift/issues/1063)) ([52c71dd](https://github.com/supabase/supabase-swift/commit/52c71dd21381a60a52f407bae18418a71aa992db))
* **storage:** add `StorageByteCount`, `ResizeMode`, `ImageFormat`, `SortOrder`, and `DownloadBehavior` typed value types, non-breaking backport from v3 ([#1049](https://github.com/supabase/supabase-swift/issues/1049)) ([d464945](https://github.com/supabase/supabase-swift/commit/d464945de0829186a5883182fe112c22c69f3cec))


### Bug Fixes

* **postgrest:** quote in() filter values containing reserved characters ([#1061](https://github.com/supabase/supabase-swift/issues/1061)) ([a09725f](https://github.com/supabase/supabase-swift/commit/a09725fc56ee08338422f1bec88f5c0af2961062))
* **postgrest:** remove invalid quotes from explain() plan media type ([#1048](https://github.com/supabase/supabase-swift/issues/1048)) ([261aba0](https://github.com/supabase/supabase-swift/commit/261aba01229111c72d5f30fc2e87b9a519b919ea))
* **realtime:** make `lifecycleManager` Sendable and `withTimeout` throwing, removing the `Result`-wrapping anti-pattern at call sites, backported from v3 ([#1052](https://github.com/supabase/supabase-swift/issues/1052)) ([3de1327](https://github.com/supabase/supabase-swift/commit/3de1327b1dd158bf032a1b1f861671982eb895ff))
* **storage:** restore source compatibility for deprecated overloads ([#1062](https://github.com/supabase/supabase-swift/issues/1062)) ([0485d41](https://github.com/supabase/supabase-swift/commit/0485d4170c7565722539e4be0b1b7b2b925eac36))

## [2.48.0](https://github.com/supabase/supabase-swift/compare/v2.47.2...v2.48.0) (2026-06-17)


### Features

* **auth:** add WebAuthn/passkey support ([#1013](https://github.com/supabase/supabase-swift/issues/1013)) ([9d65216](https://github.com/supabase/supabase-swift/commit/9d652160366ffaabfc370f23b94568505003ac42))

## [2.47.2](https://github.com/supabase/supabase-swift/compare/v2.47.1...v2.47.2) (2026-06-16)


### Bug Fixes

* **realtime:** prevent deaf socket from duplicate handleConnected (SDK-959) ([#1003](https://github.com/supabase/supabase-swift/issues/1003)) ([2681ba0](https://github.com/supabase/supabase-swift/commit/2681ba06e5eafd8745ecabe58f6eabdc48589d39))

## [2.47.1](https://github.com/supabase/supabase-swift/compare/v2.47.0...v2.47.1) (2026-06-15)


### Bug Fixes

* **auth:** recognize ?error= query param in implicit grant redirect URLs ([#1009](https://github.com/supabase/supabase-swift/issues/1009)) ([92d7c6f](https://github.com/supabase/supabase-swift/commit/92d7c6f1daac771f1fc7db22a1ef22cda14e6573))
* **tests:** grant API access to integration test tables and functions ([#1018](https://github.com/supabase/supabase-swift/issues/1018)) ([8372c18](https://github.com/supabase/supabase-swift/commit/8372c181cb04104d6725b2afb5e8238db086289f))

## [2.47.0](https://github.com/supabase/supabase-swift/compare/v2.46.0...v2.47.0) (2026-06-08)


### Features

* **supabase:** consolidate client metadata into structured X-Client-Info header ([#986](https://github.com/supabase/supabase-swift/issues/986)) ([c62510d](https://github.com/supabase/supabase-swift/commit/c62510da51c93d06e6a22a59a74901b59545f3f0))


### Bug Fixes

* **spm:** declare missing direct product dependencies for strict framework linking ([#1004](https://github.com/supabase/supabase-swift/issues/1004)) ([60c56c8](https://github.com/supabase/supabase-swift/commit/60c56c8661014bd89d879ab7f69f9f240b6f590a)), closes [#1000](https://github.com/supabase/supabase-swift/issues/1000)

## [2.46.0](https://github.com/supabase/supabase-swift/compare/v2.45.0...v2.46.0) (2026-04-28)


### Features

* **functions:** support custom JSON encoder and decoder ([#975](https://github.com/supabase/supabase-swift/issues/975)) ([b7e6a63](https://github.com/supabase/supabase-swift/commit/b7e6a63d31b50506c793525aefe2ad7703e7c3a9))


### Bug Fixes

* **ci:** remove path filters so CI always runs ([#985](https://github.com/supabase/supabase-swift/issues/985)) ([15aefe5](https://github.com/supabase/supabase-swift/commit/15aefe5bd8de32bd3d434f3d9c748fd11bf32e82))

## [2.45.0](https://github.com/supabase/supabase-swift/compare/v2.44.1...v2.45.0) (2026-04-24)


### Features

* **postgrest:** add stripNulls method for null value stripping ([#972](https://github.com/supabase/supabase-swift/issues/972)) ([984c263](https://github.com/supabase/supabase-swift/commit/984c2634e4cf201feba9f3718a2b37ff7497a9ec))
* **realtime:** add deferred disconnect on empty channels ([#973](https://github.com/supabase/supabase-swift/issues/973)) ([770670f](https://github.com/supabase/supabase-swift/commit/770670f1f9a64997c75cae84db7985b1de0a4b84))
* **realtime:** handle app lifecycle background/foreground transitions ([#967](https://github.com/supabase/supabase-swift/issues/967)) ([6039ede](https://github.com/supabase/supabase-swift/commit/6039edeaf385b43c488467988f7f10e45cff31b0))
* **storage:** add cacheNonce parameter for cache invalidation ([#970](https://github.com/supabase/supabase-swift/issues/970)) ([6397521](https://github.com/supabase/supabase-swift/commit/6397521dc4e95de1b9285b435f10fca2c01b0752))


### Bug Fixes

* **auth:** include Cloudflare error codes in retryable network errors ([#969](https://github.com/supabase/supabase-swift/issues/969)) ([e9eafd7](https://github.com/supabase/supabase-swift/commit/e9eafd7c7cf0018d4007abea3c1807591b095e67))
* **realtime:** resolve subscribe/unsubscribe lifecycle races via ChannelStateManager actor ([#974](https://github.com/supabase/supabase-swift/issues/974)) ([8130762](https://github.com/supabase/supabase-swift/commit/813076247356d371ca1118090f07210ef295dbf2))
* **storage:** guard against empty transform routing through render endpoint ([#968](https://github.com/supabase/supabase-swift/issues/968)) ([bee53cc](https://github.com/supabase/supabase-swift/commit/bee53cc42125c012e6716e61afb5cfaa300b5e3f))
* **supabase:** propagate custom URLSession to Realtime client ([#971](https://github.com/supabase/supabase-swift/issues/971)) ([52db062](https://github.com/supabase/supabase-swift/commit/52db0621c5387246c8cbb53cef6d48c13716e98e))

## [2.44.1](https://github.com/supabase/supabase-swift/compare/v2.44.0...v2.44.1) (2026-04-22)


### Bug Fixes

* **realtime:** extract ConnectionManager actor and fix connection lifecycle races ([#855](https://github.com/supabase/supabase-swift/issues/855)) ([dcbc63d](https://github.com/supabase/supabase-swift/commit/dcbc63d59dac46da96cec26e69d298e4735d217e))

## [2.44.0](https://github.com/supabase/supabase-swift/compare/v2.43.1...v2.44.0) (2026-04-20)


### Features

* **realtime:** add protocol 2.0.0 support with binary broadcast frames ([#908](https://github.com/supabase/supabase-swift/issues/908)) ([83f8a9c](https://github.com/supabase/supabase-swift/commit/83f8a9c52dda65f9c1cbad4215871bf165c1b9ff))


### Bug Fixes

* **storage:** make signedURL optional in createSignedURLs response ([#958](https://github.com/supabase/supabase-swift/issues/958)) ([52c44ba](https://github.com/supabase/supabase-swift/commit/52c44ba919616f471e98f791fbf2f6f3a4f3837d))
* use host(percentEncoded:) to avoid iOS 26 crash in SupabaseClient ([#962](https://github.com/supabase/supabase-swift/issues/962)) ([e56fd8a](https://github.com/supabase/supabase-swift/commit/e56fd8ac6b543e4f545b1ce85c16412430351f7f))

## [2.43.1](https://github.com/supabase/supabase-swift/compare/v2.43.0...v2.43.1) (2026-04-07)


### Bug Fixes

* **functions:** import Functions directly in FunctionsErrorTests instead of Supabase ([#947](https://github.com/supabase/supabase-swift/issues/947)) ([ff6cae0](https://github.com/supabase/supabase-swift/commit/ff6cae07647887e8c2e0bf8102eddaf4a50e340c))
* **postgrest:** drop sendability from rpc param ([#951](https://github.com/supabase/supabase-swift/issues/951)) ([bdc95b0](https://github.com/supabase/supabase-swift/commit/bdc95b0c10e34331bd663f3a8b938618e4a5dde5))
* **postgrest:** retry on HTTP 503 (Service Unavailable) errors ([#939](https://github.com/supabase/supabase-swift/issues/939)) ([1725e92](https://github.com/supabase/supabase-swift/commit/1725e92d6fead50aedc6af6f367c14cea7c3bb97))
* **realtime:** reject presence and postgres change callbacks while subscribing or subscribed ([#938](https://github.com/supabase/supabase-swift/issues/938)) ([824d9d1](https://github.com/supabase/supabase-swift/commit/824d9d185d90513ac96e05a74508e296becaf76d))

## [2.43.0](https://github.com/supabase/supabase-swift/compare/v2.42.0...v2.43.0) (2026-03-23)


### Features

* **postgrest:** add automatic retries for transient errors ([#927](https://github.com/supabase/supabase-swift/issues/927)) ([fe75f12](https://github.com/supabase/supabase-swift/commit/fe75f12d3225f4d1688eafb161748c31dba450e6))

## [2.42.0](https://github.com/supabase/supabase-swift/compare/v2.41.1...v2.42.0) (2026-03-19)


### Features

* **storage:** implement setHeader method on storage client ([#910](https://github.com/supabase/supabase-swift/issues/910)) ([55a64a4](https://github.com/supabase/supabase-swift/commit/55a64a40350f4947da1b5e74ab051bbb3e734050))


### Bug Fixes

* **realtime:** use URLRequest headers instead of httpAdditionalHeaders for WebSocket ([#920](https://github.com/supabase/supabase-swift/issues/920)) ([47969d5](https://github.com/supabase/supabase-swift/commit/47969d52a871f5ef420e3134cc0e54ba66a3eeb8))

## [2.41.1](https://github.com/supabase/supabase-swift/compare/v2.41.0...v2.41.1) (2026-02-06)


### Bug Fixes

* **auth:** decode MFA unenroll response id field ([#905](https://github.com/supabase/supabase-swift/issues/905)) ([7f42d92](https://github.com/supabase/supabase-swift/commit/7f42d9291008aa8c3863e9f5e677009499676f37))

## [2.41.0](https://github.com/supabase/supabase-swift/compare/v2.40.0...v2.41.0) (2026-01-28)


### Features

* **ci:** enhance CI with format check, API stability, and success summary ([#887](https://github.com/supabase/supabase-swift/issues/887)) ([a15b888](https://github.com/supabase/supabase-swift/commit/a15b88809ca210693687bc7eefd937290b71d292))


### Bug Fixes

* improve Swift concurrency thread safety and documentation ([#891](https://github.com/supabase/supabase-swift/issues/891)) ([eb73450](https://github.com/supabase/supabase-swift/commit/eb73450d01ba61c9f3d2d51631d48a42d716cfe3))

## [2.40.0](https://github.com/supabase/supabase-swift/compare/v2.39.0...v2.40.0) (2026-01-13)


### Features

* **storage:** add support for additional query items in download method ([#871](https://github.com/supabase/supabase-swift/issues/871)) ([4b201af](https://github.com/supabase/supabase-swift/commit/4b201af8a993fbe0d74cdf5d6c81222efd5c519c))


### Bug Fixes

* **ci:** add GitHub App token generation to release workflow ([#879](https://github.com/supabase/supabase-swift/issues/879)) ([19d38f9](https://github.com/supabase/supabase-swift/commit/19d38f9273210ed85f4bed0008db2ebfc322baed))
* **functions:** sync auth headers on auth state change ([#878](https://github.com/supabase/supabase-swift/issues/878)) ([a219239](https://github.com/supabase/supabase-swift/commit/a219239515cd347800c070849311acc823f0394e))

## [2.39.0](https://github.com/supabase/supabase-swift/compare/v2.38.1...v2.39.0) (2025-12-16)


### Features

* **auth:** add X (OAuth 2.0) provider ([#872](https://github.com/supabase/supabase-swift/issues/872)) ([61573b7](https://github.com/supabase/supabase-swift/commit/61573b79c62d91b763b3d45ba45203d92e6444b9))

## [2.38.1](https://github.com/supabase/supabase-swift/compare/v2.38.0...v2.38.1) (2025-12-10)


### Bug Fixes

* **realtime:** resolve race conditions and connection bugs ([#866](https://github.com/supabase/supabase-swift/issues/866)) ([1266707](https://github.com/supabase/supabase-swift/commit/1266707c2a0926851e499935b6fd89324272c0ff))

## [2.38.0](https://github.com/supabase/supabase-swift/compare/v2.37.0...v2.38.0) (2025-12-05)


### Features

* **postgrest:** add missing operators match, imatch, and isDistinct ([#857](https://github.com/supabase/supabase-swift/issues/857)) ([af786cb](https://github.com/supabase/supabase-swift/commit/af786cb012b472dd502974c29c6817f11923901b))
* **realtime:** improve task lifecycle management and expose public APIs ([#851](https://github.com/supabase/supabase-swift/issues/851)) ([bab4ec0](https://github.com/supabase/supabase-swift/commit/bab4ec0939f719425019a623d2075110cf986059))

## [2.37.0](https://github.com/supabase/supabase-swift/compare/v2.36.0...v2.37.0) (2025-11-03)


### Features

* **auth:** add method for updating OAuth client ([#840](https://github.com/supabase/supabase-swift/issues/840)) ([a83512b](https://github.com/supabase/supabase-swift/commit/a83512bd9069201eee4af3a5f79e874db6766e87))


### Bug Fixes

* use IssueReporting ([#826](https://github.com/supabase/supabase-swift/issues/826)) ([4ebf243](https://github.com/supabase/supabase-swift/commit/4ebf2437296f75204c528218a5df23bff6f75ad4))
* **auth:** replace trait with runtime configuration flag ([#844](https://github.com/supabase/supabase-swift/pull/844)) ([e0bdfe8](https://github.com/supabase/supabase-swift/commit/e0bdfe897737e17ae9d8a6e41abfd77dbbe7db64))

## [2.36.0](https://github.com/supabase/supabase-swift/compare/v2.35.0...v2.36.0) (2025-10-15)


### Features

* **examples:** comprehensive UX overhaul with inline code examples ([#819](https://github.com/supabase/supabase-swift/issues/819)) ([70e8c18](https://github.com/supabase/supabase-swift/commit/70e8c18c52dd1efeab82030e449d5fadbd2a3d7d))


### Bug Fixes

* **auth:** emit local stored session as the initial session ([#822](https://github.com/supabase/supabase-swift/issues/822)) ([c5721fe](https://github.com/supabase/supabase-swift/commit/c5721fe540df0789239eb8497fe26acdec3c62ca))
* exclude __Snapshots__ directories from test targets ([#815](https://github.com/supabase/supabase-swift/issues/815)) ([f05a1bf](https://github.com/supabase/supabase-swift/commit/f05a1bf68f7b5091eb15c86e98af1b345681de06))

## [2.35.0](https://github.com/supabase/supabase-swift/compare/v2.34.0...v2.35.0) (2025-10-13)


### Features

* **realtime:** add explicit REST API broadcast method ([#818](https://github.com/supabase/supabase-swift/issues/818)) ([bc0d779](https://github.com/supabase/supabase-swift/commit/bc0d7790b3b836684db80196d4b65b4b259acc63))

## [2.34.0](https://github.com/supabase/supabase-swift/compare/v2.33.2...v2.34.0) (2025-10-07)


### Features

* add support for broadcast replay configuration ([#805](https://github.com/supabase/supabase-swift/issues/805)) ([8083464](https://github.com/supabase/supabase-swift/commit/8083464ad605bb99ea18df688f827ea5f417c040))
* **auth:** add OAuth 2.1 client admin endpoints ([#809](https://github.com/supabase/supabase-swift/issues/809)) ([a2320ec](https://github.com/supabase/supabase-swift/commit/a2320ec64ad8a0bb10de2fcab51822a1c5e91618))
* **auth:** introduce getClaims method to verify and extract JWT claims ([#812](https://github.com/supabase/supabase-swift/issues/812)) ([fda262b](https://github.com/supabase/supabase-swift/commit/fda262bdb0959e4f7bdb232bdec986f0fbd0f7d5))
* **functions:** add region as forceFunctionRegion query parameter ([#806](https://github.com/supabase/supabase-swift/issues/806)) ([45ec3d6](https://github.com/supabase/supabase-swift/commit/45ec3d6647c0bac26552d48fb22bffaa67fa8f0d))

## [2.33.2](https://github.com/supabase/supabase-swift/compare/v2.33.1...v2.33.2) (2025-09-25)


### Bug Fixes

* **auth:** remove session when it has been revoked ([#802](https://github.com/supabase/supabase-swift/issues/802)) ([c6aa8ef](https://github.com/supabase/supabase-swift/commit/c6aa8efef6dffc33749622168d64cbc1a422c8e2))

## [2.33.1](https://github.com/supabase/supabase-swift/compare/v2.33.0...v2.33.1) (2025-09-23)

### Bug Fixes

* **postgrest:** drop Sendable requirements in generic types ([#798](https://github.com/supabase/supabase-swift/issues/798)) ([db3f4ab](https://github.com/supabase/supabase-swift/commit/db3f4ab9de5621fdd33956e7710db0df390ddf5a))

## [2.33.0](https://github.com/supabase/supabase-swift/compare/v2.32.0...v2.33.0) (2025-09-22)

### Features

* **postgrest:** implement maxAffected method for row limit enforcement ([#795](https://github.com/supabase/supabase-swift/issues/795)) ([78fbd8a](https://github.com/supabase/supabase-swift/commit/78fbd8a0ad39e6beef1ee2a167aff799350d7275))

## [2.32.0](https://github.com/supabase/supabase-swift/compare/v2.31.2...v2.32.0) (2025-09-15)

### Features

* **auth:** implement linkIdentity with OIDC ([#776](https://github.com/supabase/supabase-swift/issues/776)) ([661e321](https://github.com/supabase/supabase-swift/commit/661e3218d18235179efc30c33b456a8f485f9ff7))

## [2.31.2](https://github.com/supabase/supabase-swift/compare/v2.31.1...v2.31.2) (2025-08-05)

### Dependencies

* bump github.com/apple/swift-crypto from 3.12.3 to 3.13.3 ([#765](https://github.com/supabase/supabase-swift/issues/765)) ([a32faf2](https://github.com/supabase/supabase-swift/commit/a32faf2))
* bump github.com/pointfreeco/swift-snapshot-testing ([#764](https://github.com/supabase/supabase-swift/issues/764)) ([8180660](https://github.com/supabase/supabase-swift/commit/8180660))
* bump github.com/pointfreeco/xctest-dynamic-overlay ([#763](https://github.com/supabase/supabase-swift/issues/763)) ([e072a58](https://github.com/supabase/supabase-swift/commit/e072a58))

## [2.31.1](https://github.com/supabase/supabase-swift/compare/v2.31.0...v2.31.1) (2025-08-01)

### Bug Fixes

* **storage:** use dedicated storage host ([#761](https://github.com/supabase/supabase-swift/issues/761)) ([9272f1e](https://github.com/supabase/supabase-swift/commit/9272f1e))
* **realtime:** make Apikey required ([#760](https://github.com/supabase/supabase-swift/issues/760)) ([237ac9c](https://github.com/supabase/supabase-swift/commit/237ac9c))

## [2.31.0](https://github.com/supabase/supabase-swift/compare/v2.30.2...v2.31.0) (2025-07-30)

### Features

* add OSLogSupabaseLogger type ([#757](https://github.com/supabase/supabase-swift/issues/757)) ([c067c52](https://github.com/supabase/supabase-swift/commit/c067c52))
* **realtime:** subscribe retry improvements ([#747](https://github.com/supabase/supabase-swift/issues/747)) ([34a70ac](https://github.com/supabase/supabase-swift/commit/34a70ac))
* migrate from release-please to semantic-release ([#748](https://github.com/supabase/supabase-swift/issues/748)) ([be133fe](https://github.com/supabase/supabase-swift/commit/be133fe))

### Bug Fixes

* **realtime:** implement event buffering for URLSessionWebSocket ([#752](https://github.com/supabase/supabase-swift/issues/752)) ([faf2d0e](https://github.com/supabase/supabase-swift/commit/faf2d0e))

### Tests

* add comprehensive Realtime test coverage ([#755](https://github.com/supabase/supabase-swift/issues/755)) ([771ee18](https://github.com/supabase/supabase-swift/commit/771ee18))

## [2.30.2](https://github.com/supabase/supabase-swift/compare/v2.30.1...v2.30.2) (2025-07-21)


### Bug Fixes

* **realtime:** wildcard event not handled in onBroadcast callback ([#749](https://github.com/supabase/supabase-swift/issues/749)) ([78b7bb4](https://github.com/supabase/supabase-swift/commit/78b7bb4f04dda49b75f46744c1aa2fe79f95d19e))

## [2.30.1](https://github.com/supabase/supabase-swift/compare/v2.30.0...v2.30.1) (2025-07-10)


### Bug Fixes

* drop Swift 5.9 ([#745](https://github.com/supabase/supabase-swift/issues/745)) ([8054bbe](https://github.com/supabase/supabase-swift/commit/8054bbe0ffa48834d20ec26d5205f6913cdde968))

## [2.30.0](https://github.com/supabase/supabase-swift/compare/v2.29.3...v2.30.0) (2025-07-03)


### Features

* **realtime:** add presence-enabled flag to join push ([#736](https://github.com/supabase/supabase-swift/issues/736)) ([7de5b8b](https://github.com/supabase/supabase-swift/commit/7de5b8b0b88a070046112026a3add7aa08b5fa3a))

## [2.29.3](https://github.com/supabase/supabase-swift/compare/v2.29.2...v2.29.3) (2025-06-10)


### Bug Fixes

* **auth:** allow to pass a Keychain storage without a service defined ([#730](https://github.com/supabase/supabase-swift/issues/730)) ([6b1d60f](https://github.com/supabase/supabase-swift/commit/6b1d60f4d3900cdbf96fd6d1be9a00711790c2ca))
* **functions:** set request timeout to 150 seconds when invoking functions ([#728](https://github.com/supabase/supabase-swift/issues/728)) ([3d2930d](https://github.com/supabase/supabase-swift/commit/3d2930d90bf5005ecf479a27a9dd7930a819e06c))

## [2.29.2](https://github.com/supabase/supabase-swift/compare/v2.29.1...v2.29.2) (2025-05-31)


### Bug Fixes

* re-export Helpers module ([#724](https://github.com/supabase/supabase-swift/issues/724)) ([fd97d99](https://github.com/supabase/supabase-swift/commit/fd97d99d780c6b6e5bff58663e8b13979853d593))

## [2.29.1](https://github.com/supabase/supabase-swift/compare/v2.29.0...v2.29.1) (2025-05-28)


### Bug Fixes

* **realtime:** make Push associated to MainActor ([#721](https://github.com/supabase/supabase-swift/issues/721)) ([7d6870f](https://github.com/supabase/supabase-swift/commit/7d6870ffa980ad3728c272acc03fc3e3c0251fe4))

## [2.29.0](https://github.com/supabase/supabase-swift/compare/v2.28.0...v2.29.0) (2025-05-20)


### Features

* **auth:** add missing auth admin methods ([#715](https://github.com/supabase/supabase-swift/issues/715)) ([04661f8](https://github.com/supabase/supabase-swift/commit/04661f86773161ec9a64feb0bcbd29b964646cfd))

## [2.28.0](https://github.com/supabase/supabase-swift/compare/v2.27.0...v2.28.0) (2025-05-03)


### Features

* add standard client headers ([#685](https://github.com/supabase/supabase-swift/issues/685)) ([ad031c7](https://github.com/supabase/supabase-swift/commit/ad031c7e14c4881b76ac1e24ef2738c8c1cf621e))

## [2.27.0](https://github.com/supabase/supabase-swift/compare/v2.26.1...v2.27.0) (2025-05-02)


### Features

* **realtime:** add heartbeat callback ([#709](https://github.com/supabase/supabase-swift/issues/709)) ([5f3d75c](https://github.com/supabase/supabase-swift/commit/5f3d75ce163df4a882975425c2c603198e2a7272))


### Bug Fixes

* **auth:** do not remove session in case of network failure ([#712](https://github.com/supabase/supabase-swift/issues/712)) ([f001b60](https://github.com/supabase/supabase-swift/commit/f001b602ddf7022e8e556ca9f8285f6cf9b3b2be))
* decoder and encoder default instances ([#711](https://github.com/supabase/supabase-swift/issues/711)) ([0104331](https://github.com/supabase/supabase-swift/commit/01043316f94c6c4a55f73442c7155389e2b15ef6))
* update outdated error doc ([#699](https://github.com/supabase/supabase-swift/issues/699)) ([b9dc3a3](https://github.com/supabase/supabase-swift/commit/b9dc3a3005968e3bd1b8348005f1f178d44dff1c))

## [2.26.1](https://github.com/supabase/supabase-swift/compare/v2.26.0...v2.26.1) (2025-03-31)


### Bug Fixes

* avoid sharing schemes with library users ([#696](https://github.com/supabase/supabase-swift/issues/696)) ([3caa69f](https://github.com/supabase/supabase-swift/commit/3caa69fa8fb71eb8c4d89dac8ba498a9782b26fc))

## [2.26.0](https://github.com/supabase/supabase-swift/compare/v2.25.0...v2.26.0) (2025-03-06)


### Features

* add Android support ([#673](https://github.com/supabase/supabase-swift/issues/673)) ([6ec2cdd](https://github.com/supabase/supabase-swift/commit/6ec2cdd994f80cc754f310b4aaf307671454f992))


### Bug Fixes

* **auth:** add missing `@MainActor` ([#684](https://github.com/supabase/supabase-swift/issues/684)) ([16ffdd4](https://github.com/supabase/supabase-swift/commit/16ffdd4a2f996626be8cb595ab6f31d94e8eeb4b))

## [2.25.0](https://github.com/supabase/supabase-swift/compare/v2.24.7...v2.25.0) (2025-02-20)


### Features

* **realtime:** add predefined filters instead of regular `String` ([#669](https://github.com/supabase/supabase-swift/issues/669)) ([3dc9b82](https://github.com/supabase/supabase-swift/commit/3dc9b82e90a5158664d163caeb397e220f58d8dd))

## [2.24.7](https://github.com/supabase/supabase-swift/compare/v2.24.6...v2.24.7) (2025-02-18)


### Bug Fixes

* **realtime:** Set default heartbeat interval to 25s ([#667](https://github.com/supabase/supabase-swift/issues/667)) ([14c590d](https://github.com/supabase/supabase-swift/commit/14c590d08898e5a3c1c131ad704966d73df7e538))

## [2.24.6](https://github.com/supabase/supabase-swift/compare/v2.24.5...v2.24.6) (2025-02-14)


### Bug Fixes

* **auth:** make AuthClient an Actor ([#664](https://github.com/supabase/supabase-swift/issues/664)) ([bdf1961](https://github.com/supabase/supabase-swift/commit/bdf19614b35b76281f2a50e785b6d21fa9578e40))

## [2.24.5](https://github.com/supabase/supabase-swift/compare/v2.24.4...v2.24.5) (2025-02-10)


### Bug Fixes

* **realtime:** remove jwt check ([#658](https://github.com/supabase/supabase-swift/issues/658)) ([4c95559](https://github.com/supabase/supabase-swift/commit/4c955592c58c7d0aafbd0c32ae8a85e213303caa))

## [2.24.4](https://github.com/supabase/supabase-swift/compare/v2.24.3...v2.24.4) (2025-01-16)


### Bug Fixes

* Make the return value of accessToken nullable ([#641](https://github.com/supabase/supabase-swift/issues/641)) ([af9b774](https://github.com/supabase/supabase-swift/commit/af9b77453892da562c444e94ff7538051a2dd0a4))

## [2.24.3](https://github.com/supabase/supabase-swift/compare/v2.24.2...v2.24.3) (2025-01-14)


### Bug Fixes

* remove usage of `nonisolated(unsafe)` from codebase ([#638](https://github.com/supabase/supabase-swift/issues/638)) ([3d87608](https://github.com/supabase/supabase-swift/commit/3d876089b2429389f0e16e4238cc11bd444a1254))

## [2.24.2](https://github.com/supabase/supabase-swift/compare/v2.24.1...v2.24.2) (2025-01-08)


### Bug Fixes

* **realtime:** auto reconnect after calling disconnect, and several refactors ([#627](https://github.com/supabase/supabase-swift/issues/627)) ([1887f4f](https://github.com/supabase/supabase-swift/commit/1887f4f376e172bb7fbcec84506fea6c4797fde7))

## [2.24.1](https://github.com/supabase/supabase-swift/compare/v2.24.0...v2.24.1) (2024-12-16)


### Bug Fixes

* **auth:** add missing channel param to signUp method ([#625](https://github.com/supabase/supabase-swift/issues/625)) ([3a36ab7](https://github.com/supabase/supabase-swift/commit/3a36ab74c4fbd9224c03dabd88046bba49b0de9c))

## [2.24.0](https://github.com/supabase/supabase-swift/compare/v2.23.0...v2.24.0) (2024-12-05)


### Features

* **realtime:** pull access token mechanism ([#615](https://github.com/supabase/supabase-swift/issues/615)) ([c88dd36](https://github.com/supabase/supabase-swift/commit/c88dd3675b8bc7da93c71847ff9ba9862323ff8d))


### Bug Fixes

* **realtime:** prevent sending expired tokens ([#618](https://github.com/supabase/supabase-swift/issues/618)) ([595277b](https://github.com/supabase/supabase-swift/commit/595277b5eb35b8b76bbb000d44fc221c4d3298f1))

## [2.23.0](https://github.com/supabase/supabase-swift/compare/v2.22.1...v2.23.0) (2024-11-22)


### Features

* **postgrest:** add read-only mode for RPC ([#600](https://github.com/supabase/supabase-swift/issues/600)) ([d81fc86](https://github.com/supabase/supabase-swift/commit/d81fc865409821dc0816c930d2d537a126b4fe06))

## [2.22.1](https://github.com/supabase/supabase-swift/compare/v2.22.0...v2.22.1) (2024-11-12)


### Bug Fixes

* **auth:** `URLError` coercion for `RetryableError` causing session to be deleted ([#597](https://github.com/supabase/supabase-swift/issues/597)) ([d67b7cf](https://github.com/supabase/supabase-swift/commit/d67b7cf850d43c2a8ecf39feedfc39528f55f139))

## [2.22.0](https://github.com/supabase/supabase-swift/compare/v2.21.0...v2.22.0) (2024-11-06)


### Features

* **auth:** add new error codes ([#586](https://github.com/supabase/supabase-swift/issues/586)) ([1721c08](https://github.com/supabase/supabase-swift/commit/1721c08c7710e0cba1390962441fe595b613072c))


### Bug Fixes

* **auth:** incorrect error when error occurs during PKCE flow ([#592](https://github.com/supabase/supabase-swift/issues/592)) ([84ce6f2](https://github.com/supabase/supabase-swift/commit/84ce6f29b2ee2192b57d8ff7c36af3378c696653))

## [2.21.0](https://github.com/supabase/supabase-swift/compare/v2.20.5...v2.21.0) (2024-11-05)


### Features

* **realtime:** add `system` event ([#589](https://github.com/supabase/supabase-swift/issues/589)) ([1176dea](https://github.com/supabase/supabase-swift/commit/1176dea4d90f353ae777a633fc079dedf98276ff))


### Bug Fixes

* **realtime:** lost `postgres_changes` on resubscribe ([#585](https://github.com/supabase/supabase-swift/issues/585)) ([fabc07d](https://github.com/supabase/supabase-swift/commit/fabc07dac833aa94e35bf932899dfb5d1a868cfb))

## [2.20.5](https://github.com/supabase/supabase-swift/compare/v2.20.4...v2.20.5) (2024-10-24)


### Bug Fixes

* issue with MainActor isolated property on Swift 5.9 ([#577](https://github.com/supabase/supabase-swift/issues/577)) ([7266b64](https://github.com/supabase/supabase-swift/commit/7266b64e1e0b58fc893693fa80872b6d77bf1555))
* revert AnyJSON codable ([#580](https://github.com/supabase/supabase-swift/issues/580)) ([bfb6ed7](https://github.com/supabase/supabase-swift/commit/bfb6ed7b9b69123dc5cc16458da62ee3546eaf98))

## [2.20.4](https://github.com/supabase/supabase-swift/compare/v2.20.3...v2.20.4) (2024-10-23)


### Bug Fixes

* **storage:** cache control ([#551](https://github.com/supabase/supabase-swift/issues/551)) ([8a2b196](https://github.com/supabase/supabase-swift/commit/8a2b19690cf165c80454ff6388cb9a202b04172c))

## [2.20.3](https://github.com/supabase/supabase-swift/compare/v2.20.2...v2.20.3) (2024-10-22)


### Bug Fixes

* remove kSecUseDataProtectionKeychain ([#574](https://github.com/supabase/supabase-swift/issues/574)) ([554f916](https://github.com/supabase/supabase-swift/commit/554f91689eb13c1a923a53bddb5d194e6b80328a))

## [2.20.2](https://github.com/supabase/supabase-swift/compare/v2.20.1...v2.20.2) (2024-10-17)


### Bug Fixes

* general auth improvements ([#561](https://github.com/supabase/supabase-swift/issues/561)) ([5f4c0f2](https://github.com/supabase/supabase-swift/commit/5f4c0f256c74beb47ce2a42951014504ba798dd6))
* replace to HTTPTypes Components from Helpers Components ([#564](https://github.com/supabase/supabase-swift/issues/564)) ([71dee2a](https://github.com/supabase/supabase-swift/commit/71dee2ac35204c40e11d7aa3c3c6f5def95520f9))
* Swift 6 now has URLSession async method ([#565](https://github.com/supabase/supabase-swift/issues/565)) ([5786dd6](https://github.com/supabase/supabase-swift/commit/5786dd6c06ceead5851fb6527a48d0cee48654af))

## [2.20.1](https://github.com/supabase/supabase-swift/compare/v2.20.0...v2.20.1) (2024-10-09)


### Bug Fixes

* **realtime:** add RealtimeSubscription and deprecate Subscription ([#542](https://github.com/supabase/supabase-swift/issues/542)) ([3a44f30](https://github.com/supabase/supabase-swift/commit/3a44f306f32aaf0a096c316f02995f0de649b991))
* **realtime:** allow to nullify access token ([45273e5](https://github.com/supabase/supabase-swift/commit/45273e5325f57c040030901cb269fff5c0a66974))
* **realtime:** deprecate `updateAuth` from channel ([45273e5](https://github.com/supabase/supabase-swift/commit/45273e5325f57c040030901cb269fff5c0a66974))
* Swift 6 warnings related to `@_unsafeInheritExecutor` attribute ([#549](https://github.com/supabase/supabase-swift/issues/549)) ([eab7a4a](https://github.com/supabase/supabase-swift/commit/eab7a4a7a494cfdf354ecd16373bbc05d4a0977f))

## [2.20.0](https://github.com/supabase/supabase-swift/compare/v2.19.0...v2.20.0) (2024-09-25)


### Features

* **storage:** add info, exists, custom metadata, and methods for uploading file URL ([#510](https://github.com/supabase/supabase-swift/issues/510)) ([d9ba673](https://github.com/supabase/supabase-swift/commit/d9ba673b882c84e5fae277510d147f52e22b861b))

## [2.19.0](https://github.com/supabase/supabase-swift/compare/v2.18.0...v2.19.0) (2024-09-24)


### Features

* **auth:** add listUsers admin method ([#539](https://github.com/supabase/supabase-swift/issues/539)) ([1851262](https://github.com/supabase/supabase-swift/commit/1851262b5c4eb8247c10e768be3f9110938db892))


### Bug Fixes

* **realtime:** add missing `onPostgresChange` overload ([#528](https://github.com/supabase/supabase-swift/issues/528)) ([95e249f](https://github.com/supabase/supabase-swift/commit/95e249f135702c502ac8c0edc7f437337458796b))

## [2.18.0](https://github.com/supabase/supabase-swift/compare/v2.17.1...v2.18.0) (2024-09-07)


### Features

* **auth:** add support for error codes and refactor `AuthError` ([#518](https://github.com/supabase/supabase-swift/issues/518)) ([7601e17](https://github.com/supabase/supabase-swift/commit/7601e17aa87cd832aee125095a89db2175364e35))


### Bug Fixes

* **functions:** fix streamed responses ([#525](https://github.com/supabase/supabase-swift/issues/525)) ([0631069](https://github.com/supabase/supabase-swift/commit/0631069ec71cfce0e1a56bb386a679c72e862c48))

## [2.17.1](https://github.com/supabase/supabase-swift/compare/v2.17.0...v2.17.1) (2024-09-02)


### Bug Fixes

* **auth:** expose KeychainLocalStorage with default init params ([#519](https://github.com/supabase/supabase-swift/issues/519)) ([c1095c9](https://github.com/supabase/supabase-swift/commit/c1095c95a2b01a3ad76a996e6c81ed8b25dab214))

## [2.17.0](https://github.com/supabase/supabase-swift/compare/v2.16.1...v2.17.0) (2024-08-28)


### Features

* **postgrest:** set header on a per call basis ([#508](https://github.com/supabase/supabase-swift/issues/508)) ([a15efb1](https://github.com/supabase/supabase-swift/commit/a15efb15a26c76d4bbc13e570c4841633ccd6177))
* **postgrest:** use `Date` when filtering columns ([#514](https://github.com/supabase/supabase-swift/issues/514)) ([1b0155c](https://github.com/supabase/supabase-swift/commit/1b0155c3d35c23ccefceffbb13eb36f2c5ec513f))


### Bug Fixes

* **auth:** store session directly without wrapping in StoredSession type ([#513](https://github.com/supabase/supabase-swift/issues/513)) ([5de2d8d](https://github.com/supabase/supabase-swift/commit/5de2d8da722183a3be80bfddd48637932e9cbc23))

## [2.16.1](https://github.com/supabase/supabase-swift/compare/v2.16.0...v2.16.1) (2024-08-14)


### Bug Fixes

* **auth:** auth event emitter being shared among clients ([#500](https://github.com/supabase/supabase-swift/issues/500)) ([83f3385](https://github.com/supabase/supabase-swift/commit/83f338502a242691bc6455819fc0599c5e2021c1))
* **auth:** store code verifier in keychain ([#502](https://github.com/supabase/supabase-swift/issues/502)) ([b86154a](https://github.com/supabase/supabase-swift/commit/b86154a9aa808f40f87de39e32cf48e40534662e))

## [2.16.0](https://github.com/supabase/supabase-swift/compare/v2.15.3...v2.16.0) (2024-08-12)


### Features

* **auth:** add MFA phone ([#496](https://github.com/supabase/supabase-swift/issues/496)) ([2e445f2](https://github.com/supabase/supabase-swift/commit/2e445f24ba1856dd7ebb57dfabbba45ec1e0f118))

## [2.15.3](https://github.com/supabase/supabase-swift/compare/v2.15.2...v2.15.3) (2024-08-06)


### Bug Fixes

* **auth:** add missing figma, kakao, linkedin_oidc, slack_oidc, zoom, and fly providers ([#493](https://github.com/supabase/supabase-swift/issues/493)) ([152f5ce](https://github.com/supabase/supabase-swift/commit/152f5ce8e14dd54ad70ab0184d9dcb9ead65d824))

## [2.15.2](https://github.com/supabase/supabase-swift/compare/v2.15.1...v2.15.2) (2024-07-30)


### Bug Fixes

* **auth:** mark identities last_sign_in_at field as optional ([#483](https://github.com/supabase/supabase-swift/issues/483)) ([c93cf90](https://github.com/supabase/supabase-swift/commit/c93cf90d60d7d6ed1ff04a6a51e72ab009f30795))

## [2.15.1](https://github.com/supabase/supabase-swift/compare/v2.15.0...v2.15.1) (2024-07-30)


### Bug Fixes

* **storage:** list folders ([#454](https://github.com/supabase/supabase-swift/issues/454)) ([4e9f52a](https://github.com/supabase/supabase-swift/commit/4e9f52a0257a8b6e747854a53553421322a947df))

## [2.15.0](https://github.com/supabase/supabase-swift/compare/v2.14.3...v2.15.0) (2024-07-29)


### Features

* add third-party auth support ([#423](https://github.com/supabase/supabase-swift/issues/423)) ([d760f2d](https://github.com/supabase/supabase-swift/commit/d760f2d28373e80c16e8e256bf2491780a820afc))
* **realtime:** send broadcast events through HTTP ([#476](https://github.com/supabase/supabase-swift/issues/476)) ([93f4ff5](https://github.com/supabase/supabase-swift/commit/93f4ff5d3504ec5cac7e51bff4923dab51adb04b))

## [2.14.3](https://github.com/supabase/supabase-swift/compare/v2.14.2...v2.14.3) (2024-07-19)


### Bug Fixes

* **realtime:** crash when connecting socket ([#470](https://github.com/supabase/supabase-swift/issues/470)) ([5cf4f56](https://github.com/supabase/supabase-swift/commit/5cf4f563c0cbc551d8e60f5e7f8a45034644580c))

## [2.14.2](https://github.com/supabase/supabase-swift/compare/v2.14.1...v2.14.2) (2024-07-13)


### Bug Fixes

* **postgrest:** avoid duplicated columns and prefer fields ([#463](https://github.com/supabase/supabase-swift/issues/463)) ([e4f85f3](https://github.com/supabase/supabase-swift/commit/e4f85f3512ce06e85d8ca2922f0a4ca011079c21))

## [2.14.1](https://github.com/supabase/supabase-swift/compare/v2.14.0...v2.14.1) (2024-07-11)


### Bug Fixes

* **auth:** add missing nonce param when updating user ([#457](https://github.com/supabase/supabase-swift/issues/457)) ([a087a6a](https://github.com/supabase/supabase-swift/commit/a087a6a872f0540f163e89bcab6839d0f1695fd8))
* **auth:** prevent from requesting login keychain password os macOS ([#455](https://github.com/supabase/supabase-swift/issues/455)) ([3e45b5a](https://github.com/supabase/supabase-swift/commit/3e45b5a79f7a33e7752102c31730b7604292cb89))

## [2.14.0](https://github.com/supabase/supabase-swift/compare/v2.13.9...v2.14.0) (2024-07-09)


### Features

* **auth:** add support for multiple auth instances ([#445](https://github.com/supabase/supabase-swift/issues/445)) ([6803ddd](https://github.com/supabase/supabase-swift/commit/6803ddd02aa02b34ee093725611710da4f7671c1))


### Bug Fixes

* **auth:** verify otp using token hash ([#451](https://github.com/supabase/supabase-swift/issues/451)) ([58ab9af](https://github.com/supabase/supabase-swift/commit/58ab9afb152d3701a63009cc83c392f97e5bdea1))

## [2.13.9](https://github.com/supabase/supabase-swift/compare/v2.13.8...v2.13.9) (2024-07-06)


### Bug Fixes

* expose SupabaseClient headers ([#447](https://github.com/supabase/supabase-swift/issues/447)) ([50fc325](https://github.com/supabase/supabase-swift/commit/50fc32501fe6fc229841f35511b672cd29364aaa))

## [2.13.8](https://github.com/supabase/supabase-swift/compare/v2.13.7...v2.13.8) (2024-07-04)


### Bug Fixes

* Add private topic to Realtime ([#442](https://github.com/supabase/supabase-swift/issues/442)) ([a491b29](https://github.com/supabase/supabase-swift/commit/a491b297ca4cf965e554632d0a9be4052844d6a8))

## [2.13.7](https://github.com/supabase/supabase-swift/compare/v2.13.6...v2.13.7) (2024-07-02)


### Bug Fixes

* **realtime:** send access token to realtime on initial session ([#439](https://github.com/supabase/supabase-swift/issues/439)) ([048e81b](https://github.com/supabase/supabase-swift/commit/048e81b9ca5a317ad4340c4bae60f556d9e31584))

## [2.13.6](https://github.com/supabase/supabase-swift/compare/v2.13.5...v2.13.6) (2024-07-01)


### Bug Fixes

* date formatter breaking change ([#435](https://github.com/supabase/supabase-swift/issues/435)) ([6b4cc2e](https://github.com/supabase/supabase-swift/commit/6b4cc2e7fc3b61960449a15d36ef732c8020f222))

## [2.13.5](https://github.com/supabase/supabase-swift/compare/v2.13.4...v2.13.5) (2024-06-28)


### Bug Fixes

* **auth:** use project ref as namespace for storing token ([#430](https://github.com/supabase/supabase-swift/issues/430)) ([82fa93d](https://github.com/supabase/supabase-swift/commit/82fa93d0c19de6baa6de4b02dd0cdf3a17a3f0cd))

## [2.13.4](https://github.com/supabase/supabase-swift/compare/v2.13.3...v2.13.4) (2024-06-28)


### Bug Fixes

* concurrency warnings pre swift 6 support ([#428](https://github.com/supabase/supabase-swift/issues/428)) ([bee6fa7](https://github.com/supabase/supabase-swift/commit/bee6fa70182cd750d4a9c2c107bc143470c4108b))
* **realtime:** revert realtime token to apikey on user sign out ([#429](https://github.com/supabase/supabase-swift/issues/429)) ([11c629f](https://github.com/supabase/supabase-swift/commit/11c629fce23ddc3ae82ba8f04814cb0841af0ae3))

## [2.13.3](https://github.com/supabase/supabase-swift/compare/v2.13.2...v2.13.3) (2024-06-17)


### Bug Fixes

* **realtime:** Adds missing `.unsubscribed` status change ([#420](https://github.com/supabase/supabase-swift/issues/420)) ([dc90fb6](https://github.com/supabase/supabase-swift/commit/dc90fb675e9b9ccf7733d28a4fcfc3e59416e119))

## [2.13.2](https://github.com/supabase/supabase-swift/compare/v2.13.1...v2.13.2) (2024-06-07)


### Bug Fixes

* **auth:** don't call removeSession prematurely ([#416](https://github.com/supabase/supabase-swift/issues/416)) ([00221a8](https://github.com/supabase/supabase-swift/commit/00221a84fbf026ab41911d23be01e8065a949989))

## [2.13.1](https://github.com/supabase/supabase-swift/compare/v2.13.0...v2.13.1) (2024-06-06)


### Bug Fixes

* **auth:** missing autoRefreshToken param in initializer ([#415](https://github.com/supabase/supabase-swift/issues/415)) ([32de22f](https://github.com/supabase/supabase-swift/commit/32de22ffa775bfc45f4077330de3dbe81b327f3e))
* invalid identifier for _Helpers target ([#414](https://github.com/supabase/supabase-swift/issues/414)) ([b2c8aee](https://github.com/supabase/supabase-swift/commit/b2c8aee894c7a9c729d66bd850f4ffa706a21ae3))

## [2.13.0](https://github.com/supabase/supabase-swift/compare/v2.12.0...v2.13.0) (2024-06-04)


### Features

* **auth:** add convenience deep link handling methods ([#397](https://github.com/supabase/supabase-swift/issues/397)) ([db7a094](https://github.com/supabase/supabase-swift/commit/db7a0949d2e2a7a16f0d684e11d569b7ad0bee8e))
* **auth:** add options for disabling auto refresh token ([#411](https://github.com/supabase/supabase-swift/issues/411)) ([24f6a76](https://github.com/supabase/supabase-swift/commit/24f6a7683f8154b6f7a0c80b6324717efdd95c76))
* improve logging on token refresh logic ([#410](https://github.com/supabase/supabase-swift/issues/410)) ([a8ed053](https://github.com/supabase/supabase-swift/commit/a8ed053c96eaf69146dc40bbec7702fe88077354))
* **storage:** fill content-type based on file extension ([#400](https://github.com/supabase/supabase-swift/issues/400)) ([569f445](https://github.com/supabase/supabase-swift/commit/569f4455bbde6e6ea1c6a7f630a1e1d66dc39bb0))


### Bug Fixes

* **realtime:** handle timeout when subscribing to channel ([#349](https://github.com/supabase/supabase-swift/issues/349)) ([a222dd4](https://github.com/supabase/supabase-swift/commit/a222dd4aad072917d44ba18232bb32c01b5e1c18))

## [2.12.0](https://github.com/supabase/supabase-swift/compare/v2.11.0...v2.12.0) (2024-05-26)


### Features

* **auth:** add isExpired variable to session type ([#399](https://github.com/supabase/supabase-swift/issues/399)) ([dcada1a](https://github.com/supabase/supabase-swift/commit/dcada1accae66793e0f4e046dd8620870b93b3dd))
* **auth:** retry auth requests, and schedule next refresh retry in background ([#395](https://github.com/supabase/supabase-swift/issues/395)) ([35ac278](https://github.com/supabase/supabase-swift/commit/35ac2784a71edbfcaf9bc3d9dab5f721c5ea2ba6))


### Bug Fixes

* manually percent encode query items to allow values with + sign ([#402](https://github.com/supabase/supabase-swift/issues/402)) ([a0ecb70](https://github.com/supabase/supabase-swift/commit/a0ecb70804f2a97aecb66499afad8ec3370815c6))
* **storage:** list method using wrong encoder ([#405](https://github.com/supabase/supabase-swift/issues/405)) ([f16989a](https://github.com/supabase/supabase-swift/commit/f16989a5b5bd5c6d769bfaff7e6ae076dc2d3ba5))

## [2.11.0](https://github.com/supabase/supabase-swift/compare/v2.10.1...v2.11.0) (2024-05-18)


### Features

* **auth:** add linkIdentity method ([#392](https://github.com/supabase/supabase-swift/issues/392)) ([7dfaa46](https://github.com/supabase/supabase-swift/commit/7dfaa466e305eb4e29fe7b8472c362bdeba6fa45))

## [2.10.1](https://github.com/supabase/supabase-swift/compare/v2.10.0...v2.10.1) (2024-05-15)


### Bug Fixes

* race condition when accessing SupabaseClient ([#386](https://github.com/supabase/supabase-swift/issues/386)) ([811e222](https://github.com/supabase/supabase-swift/commit/811e222dd486625eb9ba8937be139563bdc10d43))

## [2.10.0](https://github.com/supabase/supabase-swift/compare/v2.9.0...v2.10.0) (2024-05-14)


### Features

* expose Realtime options on SupabaseClient ([#377](https://github.com/supabase/supabase-swift/issues/377)) ([9cfafdb](https://github.com/supabase/supabase-swift/commit/9cfafdbb4a321dd523f33319bdd7e69e8d77a0ea))


### Bug Fixes

* **auth:** adds missing redirectTo query item to updateUser ([#380](https://github.com/supabase/supabase-swift/issues/380)) ([5d1a997](https://github.com/supabase/supabase-swift/commit/5d1a9970a2024a686a013873cb70eaae64ba4aa6))
* **auth:** header being overridden ([#379](https://github.com/supabase/supabase-swift/issues/379)) ([866a039](https://github.com/supabase/supabase-swift/commit/866a0395043030dd1574deb97360e2d47040efae))
* **postgrest:** update parameter of `is` filter to allow only `Bool` or `nil` ([#382](https://github.com/supabase/supabase-swift/issues/382)) ([4ba1c7a](https://github.com/supabase/supabase-swift/commit/4ba1c7a6c5a13c0a2b4b067aad5c747d7d621e93))
* **storage:** headers overridden ([#384](https://github.com/supabase/supabase-swift/issues/384)) ([b40c34a](https://github.com/supabase/supabase-swift/commit/b40c34a63fbbc0760d3f6e70ed7b69b08f9e70c8))

## [2.9.0](https://github.com/supabase/supabase-swift/compare/v2.8.5...v2.9.0) (2024-05-10)


### Features

* **auth:** Adds `currentSession` and `currentUser` properties ([#373](https://github.com/supabase/supabase-swift/issues/373)) ([4b01556](https://github.com/supabase/supabase-swift/commit/4b015565edbdb761ead8294ebb66d05da5a48b59))
* **functions:** invoke function with custom query params ([#376](https://github.com/supabase/supabase-swift/issues/376)) ([b4b9276](https://github.com/supabase/supabase-swift/commit/b4b9276512acccc673c36e35f06e69755e2a5dc7))
* improve HTTP Error ([#372](https://github.com/supabase/supabase-swift/issues/372)) ([ea25236](https://github.com/supabase/supabase-swift/commit/ea252365511773f93ef35bc2aa80c6098612de57))
* **storage:** copy objects between buckets ([69d05ef](https://github.com/supabase/supabase-swift/commit/69d05eff5dbb413b8b2a5ba565f7f5e19a6e0ab6))
* **storage:** move objects between buckets ([69d05ef](https://github.com/supabase/supabase-swift/commit/69d05eff5dbb413b8b2a5ba565f7f5e19a6e0ab6))


### Bug Fixes

* **auth:** sign out regardless of request success ([#375](https://github.com/supabase/supabase-swift/issues/375)) ([25178e2](https://github.com/supabase/supabase-swift/commit/25178e212dcc0dba4a712e9b7ec3ed93575efdf9))

## [2.8.5](https://github.com/supabase/supabase-swift/compare/v2.8.4...v2.8.5) (2024-05-08)


### Bug Fixes

* throw generic HTTPError ([#368](https://github.com/supabase/supabase-swift/issues/368)) ([782e940](https://github.com/supabase/supabase-swift/commit/782e940437a8a72d3243847c04fb37ef2f5fe7f0))

## [2.8.4](https://github.com/supabase/supabase-swift/compare/v2.8.3...v2.8.4) (2024-05-08)


### Bug Fixes

* **functions:** invoke with custom http method ([#367](https://github.com/supabase/supabase-swift/issues/367)) ([a283b68](https://github.com/supabase/supabase-swift/commit/a283b68cf49faa4c5bd2bb870e0840900fc7af35))

## [2.8.3](https://github.com/supabase/supabase-swift/compare/v2.8.2...v2.8.3) (2024-05-07)


### Bug Fixes

* **auth:** extract both query and fragment from URL ([#365](https://github.com/supabase/supabase-swift/issues/365)) ([e9c7c8c](https://github.com/supabase/supabase-swift/commit/e9c7c8c29002c9be1bf523deefc25e036d3c4a2a))

## [2.8.2](https://github.com/supabase/supabase-swift/compare/v2.8.1...v2.8.2) (2024-05-06)


### Bug Fixes

* **auth:** sign out should ignore 403s ([#359](https://github.com/supabase/supabase-swift/issues/359)) ([7c4e62b](https://github.com/supabase/supabase-swift/commit/7c4e62b3d0dcc6f307639abb3ef8ad792589fab1))

## [2.8.1](https://github.com/supabase/supabase-swift/compare/v2.8.0...v2.8.1) (2024-04-29)


### Bug Fixes

* **auth:** add missing is_anonymous field ([#355](https://github.com/supabase/supabase-swift/issues/355)) ([854dc42](https://github.com/supabase/supabase-swift/commit/854dc42659ed9c634271562b93169bb82e06890e))

## [2.8.0](https://github.com/supabase/supabase-swift/compare/v2.7.0...v2.8.0) (2024-04-22)


### Features

* **functions:** add experimental invoke with streamed responses ([#346](https://github.com/supabase/supabase-swift/issues/346)) ([2611b09](https://github.com/supabase/supabase-swift/commit/2611b091c871cf336de954f169240647efdf0339))
* **functions:** add support for specifying function region ([#347](https://github.com/supabase/supabase-swift/issues/347)) ([f470874](https://github.com/supabase/supabase-swift/commit/f470874f8dd8b0077a44e7243fc1d91993ae5fa9))
* **postgrest:** add geojson, explain, and new filters ([#343](https://github.com/supabase/supabase-swift/issues/343)) ([56c8117](https://github.com/supabase/supabase-swift/commit/56c81171d1e610e0286f7122522890d2b4001c2b))
* **realtime:** add closure based methods ([#345](https://github.com/supabase/supabase-swift/issues/345)) ([dfe09bc](https://github.com/supabase/supabase-swift/commit/dfe09bc804a06a06743884cbf56c5890409e9a87))


### Bug Fixes

* linux build ([#350](https://github.com/supabase/supabase-swift/issues/350)) ([e62ad89](https://github.com/supabase/supabase-swift/commit/e62ad891c80b037aada972f7c11e806f70c6aa50))
* **storage:** getSignedURLs method using wrong encoder ([#352](https://github.com/supabase/supabase-swift/issues/352)) ([d1b0672](https://github.com/supabase/supabase-swift/commit/d1b06728670ed2bb204693f69a81e584cd5c1a73))

## [2.7.0](https://github.com/supabase/supabase-swift/compare/v2.6.0...v2.7.0) (2024-04-16)


### Features

* **auth:** add `getLinkIdentityURL` ([#342](https://github.com/supabase/supabase-swift/issues/342)) ([202383d](https://github.com/supabase/supabase-swift/commit/202383d355dfaa9aab0e03680d9fedb9bdfc02d9))
* **auth:** add `signInWithOAuth` ([#299](https://github.com/supabase/supabase-swift/issues/299)) ([1290bcf](https://github.com/supabase/supabase-swift/commit/1290bcfb39fb156de0283888b47ba1532107f468))
* expose PostgrestClient methods directly in SupabaseClient ([#336](https://github.com/supabase/supabase-swift/issues/336)) ([aca50a5](https://github.com/supabase/supabase-swift/commit/aca50a557339f9872896b03988b737c56589fba7))


### Bug Fixes

* **postgrest:** race condition when executing request ([#327](https://github.com/supabase/supabase-swift/issues/327)) ([8063610](https://github.com/supabase/supabase-swift/commit/80636105e154a28f418f01f4af8b30987239b8f3))
* **postgrest:** race condition when setting fetchOptions and execute method call ([#325](https://github.com/supabase/supabase-swift/issues/325)) ([97d1900](https://github.com/supabase/supabase-swift/commit/97d1900d26272777f864803a0290573b39f47f00))

## [2.6.0](https://github.com/supabase-community/supabase-swift/compare/2.5.1...v2.6.0) (2024-04-03)


### Features

* **auth:** Add `signInAnonymously` ([#297](https://github.com/supabase-community/supabase-swift/issues/297)) ([4c25a3e](https://github.com/supabase-community/supabase-swift/commit/4c25a3eac392b319154ffb3d5d33a0686e3781a4))
