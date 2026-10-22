//
//  FunctionRegion.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

/// A Supabase Edge Network region identifier.
///
/// Use the predefined static constants for known regions, or supply a custom value for regions
/// not listed here:
///
/// ```swift
/// // predefined
/// let options = FunctionInvokeOptions(region: .usEast1)
/// // custom region
/// let options2 = FunctionInvokeOptions(region: FunctionRegion(rawValue: "custom-region"))
/// let options3 = FunctionInvokeOptions(region: "custom-region")
/// ```
public struct FunctionRegion: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The raw region string sent in the request.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let apNortheast1 = FunctionRegion(rawValue: "ap-northeast-1")
  public static let apNortheast2 = FunctionRegion(rawValue: "ap-northeast-2")
  public static let apSouth1 = FunctionRegion(rawValue: "ap-south-1")
  public static let apSoutheast1 = FunctionRegion(rawValue: "ap-southeast-1")
  public static let apSoutheast2 = FunctionRegion(rawValue: "ap-southeast-2")
  public static let caCentral1 = FunctionRegion(rawValue: "ca-central-1")
  public static let euCentral1 = FunctionRegion(rawValue: "eu-central-1")
  public static let euCentral2 = FunctionRegion(rawValue: "eu-central-2")
  public static let euWest1 = FunctionRegion(rawValue: "eu-west-1")
  public static let euWest2 = FunctionRegion(rawValue: "eu-west-2")
  public static let euWest3 = FunctionRegion(rawValue: "eu-west-3")
  public static let saEast1 = FunctionRegion(rawValue: "sa-east-1")
  public static let usEast1 = FunctionRegion(rawValue: "us-east-1")
  public static let usWest1 = FunctionRegion(rawValue: "us-west-1")
  public static let usWest2 = FunctionRegion(rawValue: "us-west-2")
}
