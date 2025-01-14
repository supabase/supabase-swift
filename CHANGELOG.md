# Changelog

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
