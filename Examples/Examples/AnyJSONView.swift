//
//  AnyJSONView.swift
//  Examples
//
//  Created by Guilherme Souza on 21/03/24.
//

import Supabase
import SwiftUI

struct AnyJSONView: View {
  let value: AnyJSON

  var body: some View {
    switch value {
    case .null: Text("<nil>")
    case let .bool(value): Text(value.description)
    case let .double(value): Text(value.description)
    case let .integer(value): Text(value.description)
    case let .string(value): Text(value)
    case let .array(value):
      ForEach(0 ..< value.count, id: \.self) { index in
        if value[index].isPrimitive {
          LabeledContent("\(index)") {
            AnyJSONView(value: value[index])
          }
        } else {
          NavigationLink("\(index)") {
            List {
              AnyJSONView(value: value[index])
            }
            .navigationTitle("\(index)")
          }
        }
      }
    case let .object(object):
      let elements = Array(object).sorted(by: { $0.key < $1.key })
      ForEach(elements, id: \.key) { element in
        if element.value.isPrimitive {
          LabeledContent(element.key) {
            AnyJSONView(value: element.value)
          }
        } else {
          NavigationLink(element.key) {
            List {
              AnyJSONView(value: element.value)
            }
            .navigationTitle(element.key)
          }
        }
      }
    }
  }
}

extension AnyJSON {
  var isPrimitive: Bool {
    switch self {
    case .null, .bool, .integer, .double, .string:
      true
    case .object, .array:
      false
    }
  }
}

extension AnyJSONView {
  init(rendering value: some Codable) {
    self.init(value: try! AnyJSON(value))
  }
}

#Preview {
  NavigationStack {
    AnyJSONView(
      value: [
        "app_metadata": [
          "provider": "email",
          "providers": [
            "email",
          ],
        ],
        "aud": "authenticated",
        "confirmed_at": "2024-03-21T03:19:10.147869Z",
        "created_at": "2024-03-21T03:19:10.142559Z",
        "email": "test@mail.com",
        "email_confirmed_at": "2024-03-21T03:19:10.147869Z",
        "id": "06f83324-e553-4d39-a609-fd30682ee127",
        "identities": [
          [
            "created_at": "2024-03-21T03:19:10.146262Z",
            "email": "test@mail.com",
            "id": "06f83324-e553-4d39-a609-fd30682ee127",
            "identity_data": [
              "email": "test@mail.com",
              "email_verified": false,
              "phone_verified": false,
              "sub": "06f83324-e553-4d39-a609-fd30682ee127",
            ],
            "identity_id": "35aafcdf-f12e-4e3d-8302-63ff587c041c",
            "last_sign_in_at": "2024-03-21T03:19:10.146245Z",
            "provider": "email",
            "updated_at": "2024-03-21T03:19:10.146262Z",
            "user_id": "06f83324-e553-4d39-a609-fd30682ee127",
          ],
        ],
        "last_sign_in_at": "2024-03-21T03:19:10.149557Z",
        "phone": "",
        "role": "authenticated",
        "updated_at": "2024-03-21T05:37:40.596682Z",
      ]
    )
  }
}
