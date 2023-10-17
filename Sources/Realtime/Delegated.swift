// Copyright (c) 2021 David Stump <david@davidstump.net>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// Provides a memory-safe way of passing callbacks around while not creating
/// retain cycles. This file was copied from https://github.com/dreymonde/Delegated
/// instead of added as a dependency to reduce the number of packages that
/// ship with SwiftPhoenixClient
public struct Delegated<Input, Output> {
  private(set) var callback: ((Input) -> Output?)?

  public init() {}

  public mutating func delegate<Target: AnyObject>(
    to target: Target,
    with callback: @escaping (Target, Input) -> Output
  ) {
    self.callback = { [weak target] input in
      guard let target = target else {
        return nil
      }
      return callback(target, input)
    }
  }

  public func call(_ input: Input) -> Output? {
    return callback?(input)
  }

  public var isDelegateSet: Bool {
    return callback != nil
  }
}

extension Delegated {
  public mutating func stronglyDelegate<Target: AnyObject>(
    to target: Target,
    with callback: @escaping (Target, Input) -> Output
  ) {
    self.callback = { input in
      callback(target, input)
    }
  }

  public mutating func manuallyDelegate(with callback: @escaping (Input) -> Output) {
    self.callback = callback
  }

  public mutating func removeDelegate() {
    callback = nil
  }
}

extension Delegated where Input == Void {
  public mutating func delegate<Target: AnyObject>(
    to target: Target,
    with callback: @escaping (Target) -> Output
  ) {
    delegate(to: target, with: { target, _ in callback(target) })
  }

  public mutating func stronglyDelegate<Target: AnyObject>(
    to target: Target,
    with callback: @escaping (Target) -> Output
  ) {
    stronglyDelegate(to: target, with: { target, _ in callback(target) })
  }
}

extension Delegated where Input == Void {
  public func call() -> Output? {
    return call(())
  }
}

extension Delegated where Output == Void {
  public func call(_ input: Input) {
    callback?(input)
  }
}

extension Delegated where Input == Void, Output == Void {
  public func call() {
    call(())
  }
}
