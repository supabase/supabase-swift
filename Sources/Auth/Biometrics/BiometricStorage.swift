//
//  BiometricStorage.swift
//  Auth
//
//

#if canImport(LocalAuthentication)
  import ConcurrencyExtras
  import Foundation

  /// Storage for biometric settings using the existing AuthLocalStorage.
  struct BiometricStorage: Sendable {
    var getIsEnabled: @Sendable () -> Bool
    var getPolicy: @Sendable () -> BiometricPolicy?
    var getEvaluationPolicy: @Sendable () -> BiometricEvaluationPolicy?
    var getPromptTitle: @Sendable () -> String?

    var enable:
      @Sendable (
        _ evaluationPolicy: BiometricEvaluationPolicy,
        _ policy: BiometricPolicy,
        _ promptTitle: String
      ) -> Void
    var disable: @Sendable () -> Void
  }

  extension BiometricStorage {
    var isEnabled: Bool { getIsEnabled() }
    var policy: BiometricPolicy? { getPolicy() }
    var evaluationPolicy: BiometricEvaluationPolicy? { getEvaluationPolicy() }
    var promptTitle: String? { getPromptTitle() }
  }

  extension BiometricStorage {
    static func live(clientID: AuthClientID) -> BiometricStorage {
      var storage: any AuthLocalStorage {
        Dependencies[clientID].configuration.localStorage
      }

      var settingsKey: String {
        let baseKey = Dependencies[clientID].configuration.storageKey ?? "supabase.auth.token"
        return "\(baseKey).biometrics"
      }

      func loadSettings() -> Settings? {
        guard let data = try? storage.retrieve(key: settingsKey) else {
          return nil
        }
        return try? JSONDecoder().decode(Settings.self, from: data)
      }

      func saveSettings(_ settings: Settings?) {
        if let settings {
          if let data = try? JSONEncoder().encode(settings) {
            try? storage.store(key: settingsKey, value: data)
          }
        } else {
          try? storage.remove(key: settingsKey)
        }
      }

      // Use LockIsolated for thread-safe caching
      // Use a flag to track if settings have been loaded (lazy loading to avoid
      // accessing Dependencies before they're fully set up)
      let settingsLoaded = LockIsolated(false)
      let cachedSettings = LockIsolated<Settings?>(nil)

      func ensureSettingsLoaded() {
        if !settingsLoaded.value {
          settingsLoaded.setValue(true)
          cachedSettings.setValue(loadSettings())
        }
      }

      return BiometricStorage(
        getIsEnabled: {
          ensureSettingsLoaded()
          return cachedSettings.value?.isEnabled ?? false
        },
        getPolicy: {
          ensureSettingsLoaded()
          return cachedSettings.value?.policy
        },
        getEvaluationPolicy: {
          ensureSettingsLoaded()
          return cachedSettings.value?.evaluationPolicy
        },
        getPromptTitle: {
          ensureSettingsLoaded()
          return cachedSettings.value?.promptTitle
        },
        enable: { evaluationPolicy, policy, promptTitle in
          let settings = Settings(
            isEnabled: true,
            policy: policy,
            evaluationPolicy: evaluationPolicy,
            promptTitle: promptTitle
          )
          saveSettings(settings)
          cachedSettings.setValue(settings)
        },
        disable: {
          saveSettings(nil)
          cachedSettings.setValue(nil)
        }
      )
    }
  }

  // MARK: - Settings

  private struct Settings: Codable, Sendable {
    var isEnabled: Bool
    var policyType: String
    var policyTimeout: TimeInterval?
    var evaluationPolicyRaw: Int
    var promptTitle: String

    var policy: BiometricPolicy {
      switch policyType {
      case "default": return .default
      case "always": return .always
      case "session": return .session(timeoutInSeconds: policyTimeout ?? 300)
      case "appLifecycle": return .appLifecycle
      default: return .default
      }
    }

    var evaluationPolicy: BiometricEvaluationPolicy {
      evaluationPolicyRaw == 1
        ? .deviceOwnerAuthentication
        : .deviceOwnerAuthenticationWithBiometrics
    }

    init(
      isEnabled: Bool,
      policy: BiometricPolicy,
      evaluationPolicy: BiometricEvaluationPolicy,
      promptTitle: String
    ) {
      self.isEnabled = isEnabled
      self.promptTitle = promptTitle

      switch policy {
      case .default:
        self.policyType = "default"
        self.policyTimeout = nil
      case .always:
        self.policyType = "always"
        self.policyTimeout = nil
      case .session(let timeout):
        self.policyType = "session"
        self.policyTimeout = timeout
      case .appLifecycle:
        self.policyType = "appLifecycle"
        self.policyTimeout = nil
      }

      switch evaluationPolicy {
      case .deviceOwnerAuthenticationWithBiometrics:
        self.evaluationPolicyRaw = 0
      case .deviceOwnerAuthentication:
        self.evaluationPolicyRaw = 1
      }
    }
  }
#endif
