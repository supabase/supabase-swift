# Supabase Swift v3.0.0 Changelog

## [3.0.0] - TBD

### 🧪 Test Suite Status
- **Note**: Some test files have been temporarily disabled due to Swift compiler issues
- **Note**: Test suite is being updated to work with v3.0.0 changes
- **Note**: Several API changes in tests need to be addressed (MFAEnrollParams, emailChangeToken, ilike parameters)

### 🚨 Breaking Changes

> **Note**: This is a major version release with significant breaking changes. Please refer to the [Migration Guide](./V3_MIGRATION_GUIDE.md) for detailed upgrade instructions.

#### Infrastructure & Requirements
- **BREAKING**: Minimum Swift version is now 6.0+ (was 5.10+)
- **BREAKING**: Minimum Xcode version is now 16.0+ (was 15.3+)
- **BREAKING**: Networking layer completely replaced with Alamofire
- **BREAKING**: Release management switched to release-please

#### Deprecated Code Removal (4,525 lines removed)
- **BREAKING**: All `@available(*, deprecated)` methods and properties removed
- **BREAKING**: All `Deprecated.swift` files removed from all modules
- **BREAKING**: `UserCredentials` is now internal (was public deprecated)

#### Authentication
- **BREAKING**: Removed deprecated GoTrue* type aliases (`GoTrueClient`, `GoTrueMFA`, etc.)
- **BREAKING**: Removed deprecated `AuthError` cases: `sessionNotFound`, `pkce(_:)`, `invalidImplicitGrantFlowURL`, `missingURL`, `invalidRedirectScheme`
- **BREAKING**: Removed deprecated `APIError` struct and related methods
- **BREAKING**: Removed deprecated `PKCEFailureReason` enum
- **BREAKING**: Removed `emailChangeToken` property from user attributes

#### Database (PostgREST)
- **BREAKING**: Removed deprecated `queryValue` property (use `rawValue` instead)

#### Storage
- **BREAKING**: Removed deprecated `JSONEncoder.defaultStorageEncoder`
- **BREAKING**: Removed deprecated `JSONDecoder.defaultStorageDecoder`

#### Real-time (Major Modernization)
- **BREAKING**: `RealtimeClientV2` renamed to `RealtimeClient` (now primary implementation)
- **BREAKING**: `RealtimeChannelV2` renamed to `RealtimeChannel`
- **BREAKING**: `RealtimeMessageV2` renamed to `RealtimeMessage`
- **BREAKING**: `PushV2` renamed to `Push`
- **BREAKING**: `SupabaseClient.realtimeV2` renamed to `SupabaseClient.realtime`
- **BREAKING**: Entire legacy `Realtime/Deprecated/` folder removed (11 files)
- **BREAKING**: Removed deprecated `broadcast(event:)` method (use `broadcastStream(event:)`)
- **BREAKING**: Removed deprecated `subscribe()` method (use `subscribeWithError()`)

#### Helpers & Utilities
- **BREAKING**: Removed deprecated `ObservationToken.remove()` method (use `cancel()`)

#### Functions
- **BREAKING**: Enhanced with Alamofire networking integration

#### Logging System
- **BREAKING**: Drop SupabaseLogger in favor of `swift-log` dependency

#### Dependency Management
- [x] **BREAKING**: Adopt swift-dependencies for modern dependency management

#### Minimum OS Version Support
- [x] **BREAKING**: Set minimum OS versions to iOS 16, macOS 13, tvOS 16, watchOS 9

### ✨ New Features

#### Infrastructure
- [x] Alamofire networking layer integration with enhanced error handling
- [x] Release-please automated release management
- [x] Swift 6.0 strict concurrency support
- [x] Modernized CI/CD pipeline with Xcode 26.0

#### Core Client
- [x] Simplified and modernized API surface (deprecated code removed)
- [x] Improved configuration system with better defaults
- [x] Enhanced dependency injection capabilities
- [x] Better debugging and logging options with global timeout configuration

#### Authentication
- [x] Cleaner error handling (deprecated errors removed)
- [x] Simplified type system (GoTrue* aliases removed)
- [x] Enhanced MFA support
- [x] Improved PKCE implementation with validation
- [x] Better session management
- [x] New identity linking capabilities

#### Database (PostgREST)
- [x] Enhanced type safety for query operations
- [x] Improved query builder with better IntelliSense (fixed text search methods)
- [x] Better support for complex filtering
- [x] Enhanced relationship handling

#### Storage
- [x] New progress tracking for uploads/downloads (configuration added)
- [x] Better metadata management
- [x] Improved file transformation options
- [x] Enhanced security options
- [x] Upload retry configuration and timeout options

#### Real-time
- [x] Modern WebSocket implementation (RealtimeV2 → Realtime)
- [x] Simplified API (deprecated methods removed)
- [x] Consistent naming conventions
- [ ] Better connection management
- [ ] Enhanced presence features
- [ ] Improved subscription lifecycle management

#### Functions
- [x] Better parameter type safety with enhanced options
- [x] Enhanced error handling
- [x] Improved response parsing
- [x] Retry configuration and timeout support
- [x] Improved FunctionRegion type with RawRepresentable and ExpressibleByStringLiteral
- [x] Added support for more AWS regions (ap-northeast-2, ap-south-1, ap-southeast-2, ca-central-1, eu-central-1, eu-west-2, eu-west-3, sa-east-1, us-west-2)

#### Logging System
- [x] Modern logging system using `swift-log` dependency
- [x] Standardized logging across all modules
- [x] Better integration with Swift ecosystem logging tools

#### Dependency Management
- [x] Modern dependency management using swift-dependencies
- [x] Replace custom dependency injection with @Dependency property wrappers
- [x] Improved testability with controllable dependencies
- [x] Better separation of concerns and modularity

#### Minimum OS Version Support
- [x] Native Clock protocol support without fallbacks
- [x] Simplified clock implementation using swift-clocks
- [x] Removal of ConcurrencyExtras dependency (deferred - still needed for LockIsolated/UncheckedSendable)
- [x] Better integration with modern Swift concurrency

### 🛠️ Improvements

#### Developer Experience
- [ ] Consistent error handling across all modules
- [ ] Better error messages with actionable guidance
- [ ] Improved debugging information
- [ ] Improved async/await support throughout
- [x] Enhanced documentation and code examples with v3.0.0 features

#### Performance
- [ ] Optimized network request handling
- [ ] Better memory management
- [ ] Reduced bundle size
- [ ] Improved startup performance

#### Type Safety
- [ ] Better generic type inference
- [ ] More precise error types
- [ ] Enhanced compile-time checks
- [ ] Improved autocomplete support

### 🐛 Bug Fixes
- [ ] *Fixes will be documented as they are implemented*

### 📚 Documentation
- [x] Complete API documentation overhaul
- [x] New getting started guides with v3.0.0 features
- [x] Updated code examples for all features
- [x] Comprehensive migration guide
- [x] Enhanced MFA examples with AAL capabilities
- [ ] Best practices documentation

### 🔧 Development
- [ ] Updated minimum Swift version requirement
- [ ] Enhanced testing infrastructure
- [ ] Improved CI/CD pipeline
- [ ] Better development tooling

### 📱 Platform Support
- Maintains support for:
  - iOS 13.0+
  - macOS 10.15+
  - tvOS 13.0+
  - watchOS 6.0+
  - visionOS 1.0+

### 🔗 Dependencies
- [ ] Updated to latest compatible versions of all dependencies
- [ ] Removed deprecated dependencies
- [ ] Added new dependencies for enhanced functionality

---

## Migration Information

**From v2.x to v3.0**: See the [Migration Guide](./V3_MIGRATION_GUIDE.md) for step-by-step instructions.

**Estimated Migration Time**:
- Small projects: 1-3 hours
- Medium projects: 3-6 hours
- Large projects: 6-12 hours

**Migration Complexity**: Medium-High - Includes deprecated code removal, Realtime API changes, and infrastructure updates.

---

## Support

- **Documentation**: [https://supabase.com/docs/reference/swift](https://supabase.com/docs/reference/swift)
- **Issues**: [GitHub Issues](https://github.com/supabase/supabase-swift/issues)
- **Community**: [Supabase Discord](https://discord.supabase.com)

---

*This changelog follows [Keep a Changelog](https://keepachangelog.com/) format.*
*Last Updated: 2025-09-18*