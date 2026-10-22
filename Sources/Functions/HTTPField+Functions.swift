//
//  HTTPField+Functions.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

public import HTTPTypes

extension HTTPField.Name {
  /// `x-region`: the region an invocation asks for.
  public static let xRegion = HTTPField.Name("x-region")!
  /// `x-relay-error`: `true` when the relay could not run the function.
  public static let xRelayError = HTTPField.Name("x-relay-error")!
  /// `x-sb-edge-region`: the region that served the call.
  public static let xSbEdgeRegion = HTTPField.Name("x-sb-edge-region")!
  /// `x-deno-execution-id`: the worker execution id. Quote it to Supabase support.
  public static let xDenoExecutionID = HTTPField.Name("x-deno-execution-id")!
  /// `sb-error-code`: the platform's error code on a failure it produced.
  public static let sbErrorCode = HTTPField.Name("sb-error-code")!
}
