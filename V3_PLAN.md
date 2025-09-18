# Supabase Swift v3.0.0 Plan

## Overview
This document outlines the plan for Supabase Swift v3.0.0, a major version with breaking changes aimed at modernizing the API, improving developer experience, and aligning with current Swift best practices.

**Current Status**: Planning Phase
**Current Version**: v2.32.0
**Target Release**: TBD

## Key Objectives
- Modernize API design following current Swift patterns
- Improve type safety and developer experience
- Simplify configuration and initialization
- Enhanced async/await support
- Better error handling
- Streamlined authentication flows
- Improved real-time capabilities

## Breaking Changes Overview
v3.0.0 will introduce several breaking changes to improve the overall API design and developer experience. All changes will be documented in detail in the migration guide.

## Module Structure
Current modules will be maintained:
- **Supabase** (Main client)
- **Auth** (Authentication)
- **Database/PostgREST** (Database operations)
- **Storage** (File storage)
- **Functions** (Edge functions)
- **Realtime** (Real-time subscriptions)

## Roadmap

### Phase 1: Foundation & Planning ✅
- [x] Analyze current codebase structure
- [x] Create v3 plan document
- [x] Create changelog template
- [x] Create migration guide template
- [x] Set up v3 development branch
- [x] Integrate existing feature branches into v3 branch

### Phase 2: Infrastructure Integration ✅
- [x] **Branch Integration** (Dependencies: Phase 1 complete)
  - [x] Merge `release-please` implementation from `restore-release-please` branch
  - [x] Merge Alamofire networking layer from `alamofire` branch
  - [x] Merge Swift 5.10 support drop from `drop-swift-5.10-support` branch
  - [x] Resolve any merge conflicts between branches
  - [x] Ensure all integrated changes work together
  - [x] Update CI/CD for new infrastructure

### Phase 3: Cleanup & Breaking Changes ✅
- [x] **Remove Deprecated Code** (Dependencies: Phase 2 complete)
  - [x] Remove all deprecated methods and classes
  - [x] Clean up old authentication flows
  - [x] Remove deprecated real-time implementations
  - [x] Update documentation to remove deprecated references

- [x] **Realtime Modernization** (Dependencies: Deprecated code removal)
  - [x] Rename Realtime V2 to Realtime (breaking change)
  - [x] Remove old Realtime implementation
  - [x] Update imports and exports
  - [x] Update documentation and examples

### Phase 4: Core API Redesign ⚠️ Partially Complete
- [x] **SupabaseClient Redesign** (Dependencies: Alamofire integration, cleanup complete)
  - [x] Simplify initialization options (leveraging Alamofire)
  - [x] Improve configuration structure with better defaults
  - [x] Better dependency injection with SupabaseClientProtocol and factory pattern
  - [x] Update networking to use Alamofire throughout
  - [x] Add convenience initializers (.production(), .development())
  - [x] Enhanced global timeout configuration
  - [x] Better session management integration

- ⚠️ **Authentication Improvements** (Dependencies: SupabaseClient redesign) - **BLOCKED**
  - [x] Streamline auth flow APIs (partial - deprecated code removed)
  - ⚠️ Fix compilation issues from deprecated code removal
  - [ ] Improve session management
  - [ ] Better MFA support
  - [ ] Enhanced PKCE implementation
  - [x] Update networking calls to use Alamofire

- [x] **Database/PostgREST Enhancements** (Dependencies: SupabaseClient redesign)
  - [x] Improve query builder API (fixed missing text search methods)
  - [x] Better type safety for queries
  - [x] Enhanced filtering and ordering
  - [x] Improved error handling
  - [x] Migrate to Alamofire for all requests

### Phase 5: Advanced Features
- [ ] **Storage Improvements** (Dependencies: Core API redesign complete)
  - [ ] Better file upload/download APIs (using Alamofire)
  - [ ] Improved progress tracking with Alamofire's progress handlers
  - [ ] Enhanced metadata handling

- [ ] **Real-time Enhancements** (Dependencies: Realtime modernization, Core API redesign)
  - [ ] Modernize WebSocket handling
  - [ ] Better subscription management
  - [ ] Improved presence features
  - [ ] Ensure compatibility with new Alamofire networking

- [ ] **Functions Integration** (Dependencies: Core API redesign complete)
  - [ ] Better edge function invocation (using Alamofire)
  - [ ] Improved parameter handling
  - [ ] Enhanced error responses

### Phase 6: Developer Experience
- [ ] **Error Handling Overhaul** (Dependencies: Core API redesign, Advanced features complete)
  - [ ] Consistent error types across modules
  - [ ] Better error messages
  - [ ] Improved debugging information

- [ ] **Documentation & Examples** (Dependencies: All API changes complete)
  - [ ] Update all code examples
  - [ ] Create migration examples
  - [ ] Comprehensive API documentation

### Phase 7: Testing & Quality Assurance
- [ ] **Test Suite Updates** (Dependencies: All feature development complete)
  - [ ] Update unit tests for new APIs
  - [ ] Integration test coverage
  - [ ] Performance testing

- [ ] **Beta Testing** (Dependencies: Test suite complete)
  - [ ] Internal testing
  - [ ] Community beta program
  - [ ] Feedback integration

### Phase 8: Release Preparation
- [ ] **Final Documentation** (Dependencies: Beta testing feedback incorporated)
  - [ ] Complete migration guide
  - [ ] Update README and examples
  - [ ] Release notes

- [ ] **Release Process** (Dependencies: All documentation complete)
  - [ ] Tag v3.0.0-beta.1
  - [ ] Community feedback period
  - [ ] Final v3.0.0 release

## Current Progress
**Phase**: 4 (Core API Redesign) - **PARTIALLY COMPLETE** ⚠️
**Progress**: 75% (SupabaseClient & PostgREST complete, Auth blocked by compilation issues)
**Next Steps**: Resolve Auth module compilation issues from deprecated code removal

## Notes
- This plan will be updated as development progresses
- Breaking changes will be clearly documented
- Migration guide will provide step-by-step instructions
- Community feedback will be incorporated throughout the process

## Recent Accomplishments ✨
### Phase 1-3 ✅
- **Infrastructure Integration**: Alamofire networking, release-please, Swift 6.0 upgrade
- **Deprecated Code Removal**: Removed 4,525 lines of deprecated code across all modules
- **Realtime Modernization**: RealtimeV2 → Realtime, now the primary implementation
- **API Cleanup**: All deprecated methods, properties, and classes removed

### Phase 4 (Partial) ⚠️
- **SupabaseClient Redesign**:
  - New protocol-based architecture with `SupabaseClientProtocol`
  - Factory pattern for dependency injection (`SupabaseClientFactory`)
  - Convenience initializers (`.production()`, `.development()`)
  - Enhanced configuration with better defaults and global timeout
  - Complete Alamofire integration throughout networking layer
- **PostgREST Enhancements**: Fixed missing text search methods (plfts, phfts, wfts)
- **Storage Configuration**: Enhanced with upload retry and timeout options

### Issues Encountered 🐛
- **Auth Module Compilation**: Several breaking API issues after deprecated code removal
- **Swift 6.0 Concurrency**: Some global mutable state issues need resolution
- **API Consistency**: Some deprecated references still exist in various modules

---
*Last Updated*: 2025-09-18
*Status*: Phase 4 Partial - SupabaseClient & PostgREST Complete, Auth Issues Need Resolution