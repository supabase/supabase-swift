# Changelog

## 1.0.0 (2024-04-01)


### Features

* add AdminAPI and deleteUser method ([#224](https://github.com/supabase-community/supabase-swift/issues/224)) ([042acc0](https://github.com/supabase-community/supabase-swift/commit/042acc0e669f7d3ecae770ce779c07336652c2e8))
* add AuthStateChangeListenerRegistration type ([#248](https://github.com/supabase-community/supabase-swift/issues/248)) ([27a173e](https://github.com/supabase-community/supabase-swift/commit/27a173eda7f7f5c7ca03b96776c9672a9e6799bd))
* add filter to RPC call ([#150](https://github.com/supabase-community/supabase-swift/issues/150)) ([8463fad](https://github.com/supabase-community/supabase-swift/commit/8463fad52e746e9acc6891809070a14a580c126a))
* Add optional "referencedTable" parameter to OR PostGREST filter ([#250](https://github.com/supabase-community/supabase-swift/issues/250)) ([c06aa18](https://github.com/supabase-community/supabase-swift/commit/c06aa18d53a1fd81edfb1dbc97f9a5969c7f96fc))
* add reauthenticate method ([#271](https://github.com/supabase-community/supabase-swift/issues/271)) ([fca6721](https://github.com/supabase-community/supabase-swift/commit/fca67219938919440a3c4fff073b55d1132f073d))
* add Sendable conformances and fix warnings ([#260](https://github.com/supabase-community/supabase-swift/issues/260)) ([0c9f32c](https://github.com/supabase-community/supabase-swift/commit/0c9f32c1bbb73e00ea7025294233b0b5d1969065))
* Add SupabaseLogger ([#219](https://github.com/supabase-community/supabase-swift/issues/219)) ([42ca887](https://github.com/supabase-community/supabase-swift/commit/42ca887e693278614b359320bc35870a59eeaf2b))
* **auth:** Add `signInAnonymously` ([#297](https://github.com/supabase-community/supabase-swift/issues/297)) ([4c25a3e](https://github.com/supabase-community/supabase-swift/commit/4c25a3eac392b319154ffb3d5d33a0686e3781a4))
* **auth:** add `signInWithSSO` method ([#289](https://github.com/supabase-community/supabase-swift/issues/289)) ([5847800](https://github.com/supabase-community/supabase-swift/commit/5847800e8bc0fa206c036e1e151b6a004ed650f1))
* **auth:** add captcha token to sign-in with password methods ([#276](https://github.com/supabase-community/supabase-swift/issues/276)) ([363aa00](https://github.com/supabase-community/supabase-swift/commit/363aa00d33699ce5b60686049cabff8508389ab9))
* **auth:** add resend method ([#190](https://github.com/supabase-community/supabase-swift/issues/190)) ([ec07c95](https://github.com/supabase-community/supabase-swift/commit/ec07c9580bd4659bb9b1f5096245ef23175fe819))
* **auth:** add whatsapp channel option to signInWithOTP ([#287](https://github.com/supabase-community/supabase-swift/issues/287)) ([600c400](https://github.com/supabase-community/supabase-swift/commit/600c400c38883bb29ab236e8a1954fe8ab6ff17f))
* **auth:** link identity ([#274](https://github.com/supabase-community/supabase-swift/issues/274)) ([b805cdc](https://github.com/supabase-community/supabase-swift/commit/b805cdc628764a5bc97a38b093767de717f76f4e))
* auto-connect socket on channel subscription ([#208](https://github.com/supabase-community/supabase-swift/issues/208)) ([edeb20e](https://github.com/supabase-community/supabase-swift/commit/edeb20e3d86112bdc4e10114e38404db701705aa))
* **database:** add select on query result ([#275](https://github.com/supabase-community/supabase-swift/issues/275)) ([cac2433](https://github.com/supabase-community/supabase-swift/commit/cac24338987e8fdffd52dd0b0d7a53637a1808d4))
* edge functions support for custom domains and vanity domains ([#90](https://github.com/supabase-community/supabase-swift/issues/90)) ([00b9e7d](https://github.com/supabase-community/supabase-swift/commit/00b9e7da5cf7cd29a8ca394f52ab7f66396185c3))
* **gotrue:** add scope to signOut ([#175](https://github.com/supabase-community/supabase-swift/issues/175)) ([8c7c257](https://github.com/supabase-community/supabase-swift/commit/8c7c257bb89d3837f504f3415b3a0026042b47d6))
* mark `getURLForLinkIdentity` as experimental ([c149e7c](https://github.com/supabase-community/supabase-swift/commit/c149e7c50a63e66cdf8bfeaeb142aba01adc3a03))
* **postgrest:** allow switching schema ([#199](https://github.com/supabase-community/supabase-swift/issues/199)) ([bb92866](https://github.com/supabase-community/supabase-swift/commit/bb928668b345cc9d7d0d530badf84f3115054d59))
* **postgrest:** rename foreignTable to referencedTable ([#166](https://github.com/supabase-community/supabase-swift/issues/166)) ([c17f6d9](https://github.com/supabase-community/supabase-swift/commit/c17f6d9ff364072a2dba2eb85e2ed9b807c80ffa))
* **postgrest:** set coder in SupabaseClientOptions ([#185](https://github.com/supabase-community/supabase-swift/issues/185)) ([6376107](https://github.com/supabase-community/supabase-swift/commit/63761073cf55b7ae81190cf214d3090deb2c059f))
* prepare for v2 release ([#187](https://github.com/supabase-community/supabase-swift/issues/187)) ([036c03d](https://github.com/supabase-community/supabase-swift/commit/036c03d4862bd93f4d93c88f9a365dc292abb74f))
* re-add supabase init with a URL type ([0c15316](https://github.com/supabase-community/supabase-swift/commit/0c15316270763c94ca0ad39cac64a6f2902d9291))
* rename onAuthStateChange to authStateChanges and add event key to posted notification ([#163](https://github.com/supabase-community/supabase-swift/issues/163)) ([6cd6dda](https://github.com/supabase-community/supabase-swift/commit/6cd6ddaa6ffa58ef2ca8214e140656c3999289dd))
* **storage:** add `createSignedUploadURL` and `uploadToSignedURL` methods ([#290](https://github.com/supabase-community/supabase-swift/issues/290)) ([576693e](https://github.com/supabase-community/supabase-swift/commit/576693eb374cbd00d590f24f58c4e68124dcfebf))
* **storage:** add `createSignedURLs` method ([#273](https://github.com/supabase-community/supabase-swift/issues/273)) ([77e5c3d](https://github.com/supabase-community/supabase-swift/commit/77e5c3db13f05c0b5575e1b2fd7c3ee3375f351e))


### Bug Fixes

* add `columns` query param to insert and upsert methods ([#205](https://github.com/supabase-community/supabase-swift/issues/205)) ([5382411](https://github.com/supabase-community/supabase-swift/commit/53824117ed1a8acdbb7e33c27ff85e37a8fd6b70))
* add init with default options param ([#225](https://github.com/supabase-community/supabase-swift/issues/225)) ([d148faa](https://github.com/supabase-community/supabase-swift/commit/d148faa0704c3fcdb838f4573ca608b96b70b331))
* **Auth:** emit initial session events ([#241](https://github.com/supabase-community/supabase-swift/issues/241)) ([765b401](https://github.com/supabase-community/supabase-swift/commit/765b4011fa119fbea4adfd5a0068ee6399bc56f8))
* **auth:** stored session backwards compatibility ([#294](https://github.com/supabase-community/supabase-swift/issues/294)) ([847fe97](https://github.com/supabase-community/supabase-swift/commit/847fe97b5436cfb2e1720fa559a4068b70077104))
* examples build error ([66cc1dd](https://github.com/supabase-community/supabase-swift/commit/66cc1ddee287b407e8236924c3c13e9d301884a5))
* fix release-please ([a469396](https://github.com/supabase-community/supabase-swift/commit/a46939687a44d447737049f9506414be1d99aacb))
* **functions:** functions overrides headers ([#160](https://github.com/supabase-community/supabase-swift/issues/160)) ([e8ba6d1](https://github.com/supabase-community/supabase-swift/commit/e8ba6d1a4a32c93fec58428de0b93fd880db8106))
* **gotrue:** AuthResponse return non-optional user ([#174](https://github.com/supabase-community/supabase-swift/issues/174)) ([84aaa1d](https://github.com/supabase-community/supabase-swift/commit/84aaa1dd4111a30853b35753655a8c154af29335))
* **gotrue:** decoding of error types ([#169](https://github.com/supabase-community/supabase-swift/issues/169)) ([3adc23c](https://github.com/supabase-community/supabase-swift/commit/3adc23c5ae7a2c74f0115a6d3c65a872d9c5acfe))
* **gotrue:** ignore 401 and 404 errors on sign out ([#179](https://github.com/supabase-community/supabase-swift/issues/179)) ([2ebf6e2](https://github.com/supabase-community/supabase-swift/commit/2ebf6e2078c5f2178a374d15d2b6bc42d13278f2))
* realtime reconnection ([#261](https://github.com/supabase-community/supabase-swift/issues/261)) ([b6a1b0b](https://github.com/supabase-community/supabase-swift/commit/b6a1b0bc47d3d4571aba6b1b3a8d822373be6014))
* **realtime:** web socket message listener doesn't stop ([#284](https://github.com/supabase-community/supabase-swift/issues/284)) ([0b19580](https://github.com/supabase-community/supabase-swift/commit/0b19580d936395a1b6177ec0b57682cab010f14a))
* update Realtime auth when initialSession is emitted ([ed638d5](https://github.com/supabase-community/supabase-swift/commit/ed638d599e098b748b9cf0fbb5117feab7aa0c9e))
* use LockIsolated on EventEmitter ([33598b8](https://github.com/supabase-community/supabase-swift/commit/33598b8d826bf6289ba3a189111c0a14e64b9153))
