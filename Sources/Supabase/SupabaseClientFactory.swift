//
//  SupabaseClientFactory.swift
//  Supabase
//
//  Created by Guilherme Souza on 18/09/25.
//

import Foundation
import Alamofire
import Auth
import PostgREST
import Functions
import Storage
import Realtime

/// Protocol for creating and configuring Supabase sub-clients.
/// This allows for custom implementations and better testability.
public protocol SupabaseClientFactory: Sendable {
  /// Creates an Auth client.
  func createAuthClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.AuthOptions
  ) -> AuthClient

  /// Creates a PostgreST client.
  func createPostgrestClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.DatabaseOptions,
    session: Alamofire.Session,
    logger: (any SupabaseLogger)?
  ) -> PostgrestClient

  /// Creates a Storage client.
  func createStorageClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.StorageOptions,
    session: Alamofire.Session,
    logger: (any SupabaseLogger)?
  ) -> SupabaseStorageClient

  /// Creates a Functions client.
  func createFunctionsClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.FunctionsOptions,
    session: Alamofire.Session,
    logger: (any SupabaseLogger)?
  ) -> FunctionsClient

  /// Creates a Realtime client.
  func createRealtimeClient(
    url: URL,
    options: RealtimeClientOptions
  ) -> RealtimeClient
}

/// Default implementation of SupabaseClientFactory.
public struct DefaultSupabaseClientFactory: SupabaseClientFactory {
  public init() {}

  public func createAuthClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.AuthOptions
  ) -> AuthClient {
    AuthClient(
      url: url,
      headers: headers,
      flowType: options.flowType,
      redirectToURL: options.redirectToURL,
      storageKey: options.storageKey,
      localStorage: options.storage,
      logger: nil, // Will be set by SupabaseClient
      encoder: options.encoder,
      decoder: options.decoder,
      session: nil, // Will be set by SupabaseClient
      autoRefreshToken: options.autoRefreshToken
    )
  }

  public func createPostgrestClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.DatabaseOptions,
    session: Alamofire.Session,
    logger: (any SupabaseLogger)?
  ) -> PostgrestClient {
    PostgrestClient(
      url: url,
      schema: options.schema,
      headers: headers,
      logger: logger,
      session: session,
      encoder: options.encoder,
      decoder: options.decoder
    )
  }

  public func createStorageClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.StorageOptions,
    session: Alamofire.Session,
    logger: (any SupabaseLogger)?
  ) -> SupabaseStorageClient {
    SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: headers,
        session: session,
        logger: logger,
        useNewHostname: options.useNewHostname
      )
    )
  }

  public func createFunctionsClient(
    url: URL,
    headers: [String: String],
    options: SupabaseClientOptions.FunctionsOptions,
    session: Alamofire.Session,
    logger: (any SupabaseLogger)?
  ) -> FunctionsClient {
    FunctionsClient(
      url: url,
      headers: headers,
      region: options.region,
      logger: logger,
      session: session
    )
  }

  public func createRealtimeClient(
    url: URL,
    options: RealtimeClientOptions
  ) -> RealtimeClient {
    RealtimeClient(url: url, options: options)
  }
}