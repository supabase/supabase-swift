//
//  SessionStorage.swift
//
//
//  Created by Guilherme Souza on 24/10/23.
//

import Foundation
import Helpers

extension AuthClient {

  /// Key used to store session on ``AuthLocalStorage``.
  ///
  /// It uses value from ``AuthClient/Configuration/storageKey`` or defaults to `supabase.auth.token` if not provided.
  private var sessionStorageKey: String {
    configuration.storageKey ?? defaultStorageKey
  }

  /// Migrates session data from legacy storage formats to the current format.
  func migrateLocalStorage() {
    do {
      try migrateSessionNewKey()
      try migrateStoreSessionDirectly()
    } catch {
      logger?.error("Storage migration failed: \(error.localizedDescription)")
    }
  }

  /// Retrieves the stored session from local storage.
  func getStoredSession() -> Session? {
    do {
      let storedData = try localStorage.retrieve(key: sessionStorageKey)
      return try storedData.flatMap {
        try AuthClient.Configuration.jsonDecoder.decode(Session.self, from: $0)
      }
    } catch {
      logger?.error("Failed to retrieve session: \(error.localizedDescription)")
      return nil
    }
  }

  /// Stores a session in local storage.
  func storeSession(_ session: Session) {
    do {
      try localStorage.store(
        key: sessionStorageKey,
        value: AuthClient.Configuration.jsonEncoder.encode(session)
      )
    } catch {
      logger?.error("Failed to store session: \(error.localizedDescription)")
    }
  }

  /// Deletes the stored session from local storage.
  func deleteSession() {
    do {
      try localStorage.remove(key: sessionStorageKey)
    } catch {
      logger?.error("Failed to delete session: \(error.localizedDescription)")
    }
  }

  /// Migrates stored session from `supabase.session` key to the custom provided storage key
  /// or the default `supabase.auth.token` key.
  ///
  /// This migration handles the transition from the legacy storage key to the new configurable key system.
  private func migrateSessionNewKey() throws {
    let newKey = sessionStorageKey

    if let storedData = try? localStorage.retrieve(key: "supabase.session") {
      try localStorage.store(key: newKey, value: storedData)
      try? localStorage.remove(key: "supabase.session")
    }
  }

  /// Migrates the stored session format.
  ///
  /// Previously, sessions were stored in a wrapped format:
  /// ```json
  /// {
  ///   "session": <Session>,
  ///   "expiration_date": <Date>
  /// }
  /// ```
  /// This migration converts that format to directly store the `Session` object.
  private func migrateStoreSessionDirectly() throws {
    struct StoredSession: Codable {
      var session: Session
      var expirationDate: Date
    }

    if let data = try? localStorage.retrieve(key: sessionStorageKey),
      let storedSession = try? AuthClient.Configuration.jsonDecoder.decode(
        StoredSession.self, from: data)
    {
      let session = try AuthClient.Configuration.jsonEncoder.encode(storedSession.session)
      try localStorage.store(key: sessionStorageKey, value: session)
    }
  }
}
