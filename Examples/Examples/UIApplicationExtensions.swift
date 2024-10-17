//
//  UIApplicationExtensions.swift
//  Examples
//
//  Created by Guilherme Souza on 05/03/24.
//

#if canImport(UIKit)
  import UIKit

  extension UIApplication {
    var firstKeyWindow: UIWindow? {
      UIApplication.shared
        .connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }
        .first?.keyWindow
    }
  }
#endif
