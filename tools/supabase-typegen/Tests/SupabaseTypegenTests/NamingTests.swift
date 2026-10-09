//
//  NamingTests.swift
//  SupabaseTypegenTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Testing

@testable import SupabaseTypegen

@Suite
struct NamingTests {
  @Test(arguments: [
    ("user_id", "userId"),
    ("user-id", "userId"),
    ("userId", "userId"),
    ("ID", "id"),
    ("Draft", "draft"),
    ("class", "`class`"),
    ("default", "`default`"),
    ("1st_place", "_1stPlace"),
    ("__", "unnamed"),
    ("café_au_lait", "caféAuLait"),
    ("IN_PROGRESS", "inProgress"),
    ("ORDER_STATUS_PENDING", "orderStatusPending"),
    ("USER_ID", "userId"),
  ])
  func propertyName(postgres: String, swift: String) {
    #expect(Naming.propertyName(postgres) == swift)
  }

  @Test(arguments: [
    ("user_profiles", "UserProfiles"),
    ("inventory_books", "InventoryBooks"),
    (#"we"ird\name"#, "WeIrdName"),
    ("events_2024", "Events2024"),
    ("2024_events", "_2024Events"),
    ("ORDER_STATUS", "OrderStatus"),
    ("order_STATUS", "OrderStatus"),
  ])
  func typeName(postgres: String, swift: String) {
    #expect(Naming.typeName(postgres) == swift)
  }
}
