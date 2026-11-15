#if canImport(Security)
  import Foundation
  import Security

  /// The `SecItem` functions ``Keychain`` calls, so tests can run without a real Keychain.
  struct SecItemClient: Sendable {
    var add: @Sendable (_ query: [String: Any]) -> OSStatus
    var update: @Sendable (_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    var copyMatching: @Sendable (_ query: [String: Any]) -> (OSStatus, AnyObject?)
    var delete: @Sendable (_ query: [String: Any]) -> OSStatus

    static let live = SecItemClient(
      add: { SecItemAdd($0 as CFDictionary, nil) },
      update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
      copyMatching: { query in
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
      },
      delete: { SecItemDelete($0 as CFDictionary) }
    )
  }

  struct Keychain {
    let service: String?
    let accessGroup: String?
    let accessibility: KeychainStorage.Accessibility
    let synchronizable: Bool
    let useDataProtectionKeychain: Bool
    let secItem: SecItemClient

    init(
      service: String?,
      accessGroup: String? = nil,
      accessibility: KeychainStorage.Accessibility = .afterFirstUnlock,
      synchronizable: Bool = false,
      useDataProtectionKeychain: Bool = false,
      secItem: SecItemClient = .live
    ) {
      self.service = service
      self.accessGroup = accessGroup
      self.accessibility = accessibility
      self.synchronizable = synchronizable
      self.useDataProtectionKeychain = useDataProtectionKeychain
      self.secItem = secItem
    }

    private func assertSuccess(forStatus status: OSStatus) throws {
      if status != errSecSuccess {
        throw KeychainError(code: KeychainError.Code(rawValue: status))
      }
    }

    /// Maps a `SecItemCopyMatching` status and its result into a value.
    ///
    /// - Returns: The stored bytes, or `nil` when the item does not exist.
    /// - Throws: ``KeychainError`` for any status other than success or not-found.
    static func mapReadStatus(_ status: OSStatus, result: AnyObject?) throws -> Data? {
      if status == errSecItemNotFound {
        return nil
      }

      if status != errSecSuccess {
        throw KeychainError(code: KeychainError.Code(rawValue: status))
      }

      guard let data = result as? Data else {
        let message = "Unable to cast the retrieved item to a Data value"
        throw KeychainError(code: KeychainError.Code.unknown(message: message))
      }

      return data
    }

    /// Maps a `SecItemDelete` status, treating a missing item as success.
    ///
    /// - Throws: ``KeychainError`` for any status other than success or not-found.
    static func mapDeleteStatus(_ status: OSStatus) throws {
      if status == errSecItemNotFound || status == errSecSuccess {
        return
      }

      throw KeychainError(code: KeychainError.Code(rawValue: status))
    }

    func data(forKey key: String) throws -> Data? {
      let (status, result) = secItem.copyMatching(getOneQuery(byKey: key))
      return try Self.mapReadStatus(status, result: result)
    }

    /// Adds the item, or updates the existing one in place.
    ///
    /// The update also rewrites `kSecAttrAccessible`, so an item an earlier SDK version wrote
    /// with another accessibility moves to the current one on the first write. The item is never
    /// deleted and added again, so no reader sees it missing.
    func set(_ data: Data, forKey key: String) throws {
      let addStatus = secItem.add(setQuery(forKey: key, data: data))

      if addStatus == KeychainError.duplicateItem.status {
        let updateStatus = secItem.update(baseQuery(withKey: key), updateAttributes(data: data))
        try assertSuccess(forStatus: updateStatus)
      } else {
        try assertSuccess(forStatus: addStatus)
      }
    }

    func deleteItem(forKey key: String) throws {
      try Self.mapDeleteStatus(secItem.delete(baseQuery(withKey: key)))
    }

    func baseQuery(withKey key: String? = nil) -> [String: Any] {
      var query: [String: Any] = [:]
      query[kSecClass as String] = kSecClassGenericPassword

      if let service {
        query[kSecAttrService as String] = service
      }
      if let key {
        query[kSecAttrAccount as String] = key
      }
      if let accessGroup {
        query[kSecAttrAccessGroup as String] = accessGroup
      }
      if synchronizable {
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
      }
      if useDataProtectionKeychain {
        query[kSecUseDataProtectionKeychain as String] = true
      }

      return query
    }

    func getOneQuery(byKey key: String) -> [String: Any] {
      var query = baseQuery(withKey: key)
      query[kSecReturnData as String] = kCFBooleanTrue
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      return query
    }

    func setQuery(forKey key: String, data: Data) -> [String: Any] {
      baseQuery(withKey: key).merging(updateAttributes(data: data)) { $1 }
    }

    func updateAttributes(data: Data) -> [String: Any] {
      var attributes: [String: Any] = [kSecValueData as String: data]
      if appliesAccessibility {
        attributes[kSecAttrAccessible as String] = accessibility.secAttrValue
      }
      return attributes
    }

    private var appliesAccessibility: Bool {
      #if os(macOS)
        // kSecAttrAccessible does not apply to the legacy file-based Keychain, which is what
        // SecItem targets on macOS by default. Only send it once the data-protection Keychain
        // or iCloud sync is in use.
        // https://developer.apple.com/documentation/security/ksecattraccessible
        useDataProtectionKeychain || synchronizable
      #else
        true
      #endif
    }
  }

  struct KeychainError: LocalizedError, CustomDebugStringConvertible {
    enum Code: RawRepresentable, Equatable {
      case operationNotImplemented
      case invalidParameters
      case userCanceled
      case itemNotAvailable
      case authFailed
      case duplicateItem
      case itemNotFound
      case interactionNotAllowed
      case decodeFailed
      case other(status: OSStatus)
      case unknown(message: String)

      init(rawValue: OSStatus) {
        switch rawValue {
        case errSecUnimplemented: self = .operationNotImplemented
        case errSecParam: self = .invalidParameters
        case errSecUserCanceled: self = .userCanceled
        case errSecNotAvailable: self = .itemNotAvailable
        case errSecAuthFailed: self = .authFailed
        case errSecDuplicateItem: self = .duplicateItem
        case errSecItemNotFound: self = .itemNotFound
        case errSecInteractionNotAllowed: self = .interactionNotAllowed
        case errSecDecode: self = .decodeFailed
        default: self = .other(status: rawValue)
        }
      }

      var rawValue: OSStatus {
        switch self {
        case .operationNotImplemented: errSecUnimplemented
        case .invalidParameters: errSecParam
        case .userCanceled: errSecUserCanceled
        case .itemNotAvailable: errSecNotAvailable
        case .authFailed: errSecAuthFailed
        case .duplicateItem: errSecDuplicateItem
        case .itemNotFound: errSecItemNotFound
        case .interactionNotAllowed: errSecInteractionNotAllowed
        case .decodeFailed: errSecDecode
        case .other(let status): status
        case .unknown: errSecSuccess
        }
      }
    }

    let code: Code

    init(code: Code) {
      self.code = code
    }

    var status: OSStatus {
      code.rawValue
    }

    var localizedDescription: String { debugDescription }

    var errorDescription: String? { debugDescription }

    var debugDescription: String {
      switch code {
      case .operationNotImplemented:
        "errSecUnimplemented: A function or operation is not implemented."
      case .invalidParameters:
        "errSecParam: One or more parameters passed to the function are not valid."
      case .userCanceled:
        "errSecUserCanceled: User canceled the operation."
      case .itemNotAvailable:
        "errSecNotAvailable: No trust results are available."
      case .authFailed:
        "errSecAuthFailed: Authorization and/or authentication failed."
      case .duplicateItem:
        "errSecDuplicateItem: The item already exists."
      case .itemNotFound:
        "errSecItemNotFound: The item cannot be found."
      case .interactionNotAllowed:
        "errSecInteractionNotAllowed: Interaction with the Security Server is not allowed."
      case .decodeFailed:
        "errSecDecode: Unable to decode the provided data."
      case .other:
        "Unspecified Keychain error: \(status)."
      case .unknown(let message):
        "Unknown error: \(message)."
      }
    }

    /// A function or operation is not implemented.
    /// See [errSecUnimplemented](https://developer.apple.com/documentation/security/errsecunimplemented).
    static let operationNotImplemented: KeychainError = .init(code: .operationNotImplemented)

    /// One or more parameters passed to the function are not valid.
    /// See [errSecParam](https://developer.apple.com/documentation/security/errsecparam).
    static let invalidParameters: KeychainError = .init(code: .invalidParameters)

    /// User canceled the operation.
    /// See [errSecUserCanceled](https://developer.apple.com/documentation/security/errsecusercanceled).
    static let userCanceled: KeychainError = .init(code: .userCanceled)

    /// No trust results are available.
    /// See [errSecNotAvailable](https://developer.apple.com/documentation/security/errsecnotavailable).
    static let itemNotAvailable: KeychainError = .init(code: .itemNotAvailable)

    /// Authorization and/or authentication failed.
    /// See [errSecAuthFailed](https://developer.apple.com/documentation/security/errsecauthfailed).
    static let authFailed: KeychainError = .init(code: .authFailed)

    /// The item already exists.
    /// See [errSecDuplicateItem](https://developer.apple.com/documentation/security/errsecduplicateitem).
    static let duplicateItem: KeychainError = .init(code: .duplicateItem)

    /// The item cannot be found.
    /// See [errSecItemNotFound](https://developer.apple.com/documentation/security/errsecitemnotfound).
    static let itemNotFound: KeychainError = .init(code: .itemNotFound)

    /// Interaction with the Security Server is not allowed.
    /// See [errSecInteractionNotAllowed](https://developer.apple.com/documentation/security/errsecinteractionnotallowed).
    static let interactionNotAllowed: KeychainError = .init(code: .interactionNotAllowed)

    /// Unable to decode the provided data.
    /// See [errSecDecode](https://developer.apple.com/documentation/security/errsecdecode).
    static let decodeFailed: KeychainError = .init(code: .decodeFailed)

    /// Other Keychain error.
    /// The `OSStatus` of the Keychain operation can be accessed via the ``status`` property.
    static let other: KeychainError = .init(code: .other(status: 0))

    /// Unknown error. This is not a Keychain error but a Keychain failure. For example, being unable to cast the
    /// retrieved item.
    static let unknown: KeychainError = .init(code: .unknown(message: ""))
  }

  extension KeychainError: Equatable {
    static func == (lhs: KeychainError, rhs: KeychainError) -> Bool {
      lhs.code == rhs.code && lhs.localizedDescription == rhs.localizedDescription
    }
  }

  /// The Keychain operations ``KeychainStorage`` depends on.
  ///
  /// Exists so the migration logic can be tested without reaching the real Keychain, which is
  /// not available to an SPM test bundle.
  protocol KeychainProtocol: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func deleteItem(forKey key: String) throws
  }

  extension Keychain: KeychainProtocol {}

  func mappingKeychainErrors<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as KeychainError {
      switch error.status {
      case errSecMissingEntitlement:
        throw AuthError(
          kind: .storageMisconfigured,
          message:
            "The app is missing the Keychain entitlement (errSecMissingEntitlement). Sign it with "
            + "the keychain-access-groups entitlement, or pass useDataProtectionKeychain: false.",
          underlyingError: error
        )
      case errSecInteractionNotAllowed:
        throw AuthError(
          kind: .storageUnavailable,
          message:
            "The Keychain item is not accessible yet (errSecInteractionNotAllowed), for example "
            + "before the first unlock.",
          underlyingError: error
        )
      default:
        throw error
      }
    }
  }
#endif
