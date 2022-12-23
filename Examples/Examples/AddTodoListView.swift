//
//  AddTodoListView.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import SwiftUI

struct AddTodoListView: View {
  @Binding var request: CreateTodoRequest
  let completion: (Result<Todo, Error>) -> Void

  var body: some View {
    Section {
      TextField("Description", text: $request.description)
      Button("Save") {
        Task { await saveButtonTapped() }
      }
    }
  }

  func saveButtonTapped() async {
    do {
      let createdTodo: Todo = try await supabase.database.from("todos")
        .insert(values: request, returning: .representation)
        .single()
        .execute()
        .value
      completion(.success(createdTodo))
    } catch {
      completion(.failure(error))
    }
  }
}

struct AddTodoListView_Previews: PreviewProvider {
  static var previews: some View {
    AddTodoListView(request: .constant(.init(
      description: "",
      isComplete: false,
      ownerID: UUID()
    ))) { _ in
    }
  }
}
