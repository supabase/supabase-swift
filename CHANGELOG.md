# Changelog

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
