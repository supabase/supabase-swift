//
//  TodoListRow.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import SwiftUI

struct TodoListRow: View {
  let todo: Todo
  let completeTapped: () -> Void

  var body: some View {
    HStack {
      Text(todo.description)
      Spacer()
      Button {
        completeTapped()
      } label: {
        Image(systemName: todo.isComplete ? "checkmark.circle.fill" : "circle")
      }
      .buttonStyle(.plain)
    }
  }
}

struct TodoListRow_Previews: PreviewProvider {
  static var previews: some View {
    TodoListRow(
      todo: .init(
        id: UUID(),
        description: "",
        isComplete: false,
        createdAt: .now
      )
    ) {}
  }
}
