//
//  TodoListView.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import IdentifiedCollections
import SwiftUI
import SwiftUINavigation

struct TodoListView: View {
  @State var todos: IdentifiedArrayOf<Todo> = []
  @State var error: Error?

  @State var createTodoRequest: CreateTodoRequest?

  var body: some View {
    List {
      if let error {
        ErrorText(error)
      }

      IfLet($createTodoRequest) { $createTodoRequest in
        Section {
          TextField("Description", text: $createTodoRequest.description)
          Button("Save") {
            Task { await saveNewTodoButtonTapped() }
          }
        }
      }

      ForEach(todos) { todo in
        Button {
          Task { await toggleCompletion(of: todo) }
        } label: {
          HStack {
            Text(todo.description)
            Spacer()
            Image(systemName: todo.isComplete ? "checkmark.circle.fill" : "circle")
          }
        }
      }
    }
    .animation(.default, value: todos)
    .navigationTitle("Todos")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          withAnimation {
            createTodoRequest = .init(description: "", isComplete: false)
          }
        } label: {
          Label("Add", systemImage: "plus")
        }
      }
    }
    .task {
      do {
        error = nil
        todos = IdentifiedArrayOf(
          uniqueElements: try await supabase.database.from("todos")
            .select()
            .execute(returning: [Todo].self)
            .value
        )
      } catch {
        self.error = error
      }
    }
  }

  func saveNewTodoButtonTapped() async {
    guard let createTodoRequest else {
      return
    }

    do {
      error = nil

      let createdTodo = try await supabase.database.from("todos")
        .insert(values: createTodoRequest, returning: .representation)
        .single()
        .execute(returning: Todo.self)
        .value

      withAnimation {
        todos.insert(createdTodo, at: 0)
        self.createTodoRequest = nil
      }

    } catch {
      self.error = error
    }
  }

  func toggleCompletion(of todo: Todo) async {
    var updatedTodo = todo
    updatedTodo.isComplete.toggle()
    todos[id: todo.id] = updatedTodo

    do {
      error = nil

      let updateRequest = UpdateTodoRequest(isComplete: updatedTodo.isComplete)
      updatedTodo = try await supabase.database.from("todos")
        .update(values: updateRequest, returning: .representation)
        .eq(column: "id", value: updatedTodo.id)
        .single()
        .execute(returning: Todo.self)
        .value
      todos[id: updatedTodo.id] = updatedTodo
    } catch {
      // rollback old todo.
      todos[id: todo.id] = todo

      self.error = error
    }
  }
}

struct TodoListView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      TodoListView()
    }
  }
}
