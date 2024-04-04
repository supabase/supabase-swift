//
//  AsyncSequence.swift
//
//
//  Created by Guilherme Souza on 04/04/24.
//

import Foundation

extension AsyncSequence {
  package func collect() async rethrows -> [Element] {
    try await reduce(into: [Element]()) { $0.append($1) }
  }
}
