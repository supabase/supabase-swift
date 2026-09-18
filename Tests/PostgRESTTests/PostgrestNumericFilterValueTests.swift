import Foundation
import PostgREST
import Testing

@Suite
struct PostgrestNumericFilterValueTests {
  struct Product: PostgrestRelation {
    static let relationName = "products"
    static let selectString = "*"

    var id: Int64
    var price: Decimal
    var weight: Float
    var stock: Int32

    struct Columns: Sendable {
      let id = PostgrestColumn<Product, Int64>("id")
      let price = PostgrestColumn<Product, Decimal>("price")
      let weight = PostgrestColumn<Product, Float>("weight")
      let stock = PostgrestColumn<Product, Int32>("stock")
    }

    static let columns = Columns()
  }

  @Test
  func decimalKeepsPrecisionADoubleWouldLose() {
    #expect(Decimal(string: "9.99")!.rawValue == "9.99")
    #expect(
      Decimal(string: "12345678901234567890.123456789")!.rawValue
        == "12345678901234567890.123456789")
    #expect(Decimal(string: "-0.0000000001")!.rawValue == "-0.0000000001")
    #expect(Decimal.zero.rawValue == "0")
  }

  @Test
  func decimalDropsTrailingZeros() {
    #expect(Decimal(string: "19.90")!.rawValue == "19.9")
    #expect(Decimal(string: "1.0")!.rawValue == "1")
  }

  @Test
  func int64KeepsPrecisionADoubleWouldLose() {
    #expect(Int64(9_007_199_254_740_993).rawValue == "9007199254740993")
    #expect(Int64.max.rawValue == "9223372036854775807")
    #expect(Int64.min.rawValue == "-9223372036854775808")
  }

  @Test
  func sizedIntegersRenderTheirBounds() {
    #expect(Int16.max.rawValue == "32767")
    #expect(Int16.min.rawValue == "-32768")
    #expect(Int32.max.rawValue == "2147483647")
    #expect(Int32.min.rawValue == "-2147483648")
  }

  @Test
  func floatRendersItsShortestRoundTrip() {
    #expect(Float(1.5).rawValue == "1.5")
    #expect(Float(-0.25).rawValue == "-0.25")
    #expect(Float(0.1).rawValue == "0.1")
  }

  @Test
  func numericArraysEncodeAsArrayLiterals() {
    #expect([Int64.max, 1].rawValue == "{9223372036854775807,1}")
    #expect([Decimal(string: "9.99")!, Decimal(string: "0.01")!].rawValue == "{9.99,0.01}")
    #expect([Float(1.5), Float(2.5)].rawValue == "{1.5,2.5}")
    #expect([Int32(7), nil].rawValue == "{7,NULL}")
  }

  @Test
  func numericValuesFilterInTheStringBuilder() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("products")
      .select()
      .gte("price", value: Decimal(string: "19.99")!)
      .eq("id", value: Int64(9_007_199_254_740_993))
      .execute()

    #expect(capture.query?.contains("price=gte.19.99") == true)
    #expect(capture.query?.contains("id=eq.9007199254740993") == true)
  }

  @Test
  func numericColumnsFilterInATypedQuery() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Product.self)
      .select()
      .where {
        $0.price.gte(Decimal(string: "19.99")!)
          && $0.id.eq(Int64(9_007_199_254_740_993))
          && $0.weight.lt(Float(2.5))
          && $0.stock.gt(Int32(0))
      }
      .execute()

    #expect(capture.query?.contains("price=gte.19.99") == true)
    #expect(capture.query?.contains("id=eq.9007199254740993") == true)
    #expect(capture.query?.contains("weight=lt.2.5") == true)
    #expect(capture.query?.contains("stock=gt.0") == true)
  }
}
