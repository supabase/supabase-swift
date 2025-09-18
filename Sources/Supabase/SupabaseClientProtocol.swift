//
//  SupabaseClientProtocol.swift
//  Supabase
//
//  Created by Guilherme Souza on 18/09/25.
//

import Foundation
import Auth
import PostgREST
import Functions
import Storage
import Realtime

/// Protocol defining the core interface of a Supabase client.
/// This enables dependency injection and easier testing.
public protocol SupabaseClientProtocol: Sendable {
  /// Supabase Auth client for user authentication.
  var auth: AuthClient { get }

  /// Supabase Storage client for file operations.
  var storage: SupabaseStorageClient { get }

  /// Supabase Functions client for edge function invocations.
  var functions: FunctionsClient { get }

  /// Realtime client for real-time subscriptions.
  var realtime: RealtimeClient { get }

  /// Headers provided to the inner clients.
  var headers: [String: String] { get }

  /// All realtime channels.
  var channels: [RealtimeChannel] { get }

  /// Performs a query on a table or view.
  func from(_ table: String) -> PostgrestQueryBuilder

  /// Performs a function call with parameters.
  func rpc(
    _ fn: String,
    params: some Encodable & Sendable,
    count: CountOption?
  ) throws -> PostgrestFilterBuilder

  /// Performs a function call without parameters.
  func rpc(_ fn: String, count: CountOption?) throws -> PostgrestFilterBuilder

  /// Select a schema to query.
  func schema(_ schema: String) -> PostgrestClient

  /// Creates a Realtime channel.
  func channel(
    _ name: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void
  ) -> RealtimeChannel

  /// Removes a Realtime channel.
  func removeChannel(_ channel: RealtimeChannel) async

  /// Removes all Realtime channels.
  func removeAllChannels() async

  /// Handles an incoming URL for auth flows.
  func handle(_ url: URL)
}