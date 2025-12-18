import Testing

import Functions

@Suite
struct FunctionRegionTests {
  @Test
  func stringLiteralInit_setsRawValue() {
    let region: FunctionRegion = "custom-region"
    #expect(region.rawValue == "custom-region")
  }

  @Test
  func knownRegions_haveExpectedRawValues() {
    #expect(FunctionRegion.usEast1.rawValue == "us-east-1")
    #expect(FunctionRegion.euWest1.rawValue == "eu-west-1")
    #expect(FunctionRegion.apSoutheast2.rawValue == "ap-southeast-2")
  }
}

