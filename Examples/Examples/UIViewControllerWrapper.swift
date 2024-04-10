//
//  UIViewControllerWrapper.swift
//  Examples
//
//  Created by Guilherme Souza on 10/04/24.
//

import SwiftUI

struct UIViewControllerWrapper<T: UIViewController>: UIViewControllerRepresentable {
  typealias UIViewControllerType = T

  let viewController: T

  init(_ viewController: T) {
    self.viewController = viewController
  }

  func makeUIViewController(context _: Context) -> T {
    viewController
  }

  func updateUIViewController(_: T, context _: Context) {
    // Update the view controller if needed
  }
}
