//
//  File.swift
//  
//
//  Created by Guilherme Souza on 26/10/23.
//

import Foundation

extension Task where Success == Never, Failure == Never {
  @_spi(Internal)
  public static func megaYield(count: Int = 20) async {
    for _ in 0..<count {
      await Task<Void, Never>.detached(priority: .background) { await Task.yield() }.value
    }
  }
}
