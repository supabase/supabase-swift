//
//  FunctionRegionTests.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

import Functions
import Testing

@Suite
struct FunctionRegionTests {
  @Test
  func euCentral2() {
    #expect(FunctionRegion.euCentral2.rawValue == "eu-central-2")
  }

  @Test
  func stringLiteral() {
    let region: FunctionRegion = "custom-region"
    #expect(region.rawValue == "custom-region")
  }
}
