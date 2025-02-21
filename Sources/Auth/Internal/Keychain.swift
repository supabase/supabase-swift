#if !os(Windows) && !os(Linux) && !os(Android)
  import Foundation
  import Security

  struct Keychain {
    let service: String
    let accessGroup: String?

    init(
      service: String,
      accessGroup: String? = nil
    ) {
      self.service = service
      self.accessGroup = accessGroup
    }

    private func assertSuccess(forStatus status: OSStatus) throws {
      if status != errSecSuccess {
        throw KeychainError(code: KeychainError.Code(rawValue: status))
      }
    }

    func data(forKey key: String) throws -> Data {
      let query = getOneQuery(byKey: key)
      var result: AnyObject?
      try assertSuccess(forStatus: SecItemCopyMatching(query as CFDictionary, &result))

      guard let data = result as? Data else {
        let message = "Unable to cast the retrieved item to a Data value"
        throw KeychainError(code: KeychainError.Code.unknown(message: message))
      }

      return data
    }

    func set(_ data: Data, forKey key: String) throws {
      let addItemQuery = setQuery(forKey: key, data: data)
      let addStatus = SecItemAdd(addItemQuery as CFDictionary, nil)

      if addStatus == KeychainError.duplicateItem.status {
        let updateQuery = baseQuery(withKey: key)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        try assertSuccess(forStatus: updateStatus)
      } else {
        try assertSuccess(forStatus: addStatus)
      }
    }

    func deleteItem(forKey key: String) throws {
      let query = baseQuery(withKey: key)
      try assertSuccess(forStatus: SecItemDelete(query as CFDictionary))
    }

    private func baseQuery(withKey key: String? = nil, data: Data? = nil) -> [String: Any] {
      var query: [String: Any] = [:]
      query[kSecClass as String] = kSecClassGenericPassword
      query[kSecAttrService as String] = service

      if let key {
        query[kSecAttrAccount as String] = key
      }
      if let data {
        query[kSecValueData as String] = data
      }
      if let accessGroup {
        query[kSecAttrAccessGroup as String] = accessGroup
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
      var query = baseQuery(withKey: key, data: data)

      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

      return query
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
        case let .other(status): status
        case .unknown: errSecSuccess // This is not a Keychain error
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
      case let .unknown(message):
        "Unknown error: \(message)."
      }
    }

    // MARK: - Error Cases

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
#endif
