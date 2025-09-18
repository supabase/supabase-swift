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
- [ ] Set up v3 development branch
- [ ] Integrate existing feature branches into v3 branch

### Phase 2: Infrastructure Integration
- [ ] **Branch Integration** (Dependencies: Phase 1 complete)
  - [ ] Merge `release-please` implementation from `restore-release-please` branch
  - [ ] Merge Alamofire networking layer from `alamofire` branch
  - [ ] Merge Swift 5.10 support drop from `drop-swift-5.10-support` branch
  - [ ] Resolve any merge conflicts between branches
  - [ ] Ensure all integrated changes work together
  - [ ] Update CI/CD for new infrastructure

### Phase 3: Cleanup & Breaking Changes
- [ ] **Remove Deprecated Code** (Dependencies: Phase 2 complete)
  - [ ] Remove all deprecated methods and classes
  - [ ] Clean up old authentication flows
  - [ ] Remove deprecated real-time implementations
  - [ ] Update documentation to remove deprecated references

- [ ] **Realtime Modernization** (Dependencies: Deprecated code removal)
  - [ ] Rename Realtime V2 to Realtime (breaking change)
  - [ ] Remove old Realtime implementation
  - [ ] Update imports and exports
  - [ ] Update documentation and examples

### Phase 4: Core API Redesign
- [ ] **SupabaseClient Redesign** (Dependencies: Alamofire integration, cleanup complete)
  - [ ] Simplify initialization options (leveraging Alamofire)
  - [ ] Improve configuration structure
  - [ ] Better dependency injection
  - [ ] Update networking to use Alamofire throughout

- [ ] **Authentication Improvements** (Dependencies: SupabaseClient redesign)
  - [ ] Streamline auth flow APIs
  - [ ] Improve session management
  - [ ] Better MFA support
  - [ ] Enhanced PKCE implementation
  - [ ] Update networking calls to use Alamofire

- [ ] **Database/PostgREST Enhancements** (Dependencies: SupabaseClient redesign)
  - [ ] Improve query builder API
  - [ ] Better type safety for queries
  - [ ] Enhanced filtering and ordering
  - [ ] Improved error handling
  - [ ] Migrate to Alamofire for all requests

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
**Phase**: 1 (Foundation & Planning)
**Progress**: 80% (4/5 foundation tasks completed)
**Next Steps**: Set up v3 development branch and integrate existing feature branches

## Notes
- This plan will be updated as development progresses
- Breaking changes will be clearly documented
- Migration guide will provide step-by-step instructions
- Community feedback will be incorporated throughout the process

---
*Last Updated*: 2025-09-18
*Status*: In Progress