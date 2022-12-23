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
  @EnvironmentObject var auth: AuthController

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
        HStack {
          Text(todo.description)
          Spacer()
          Button {
            Task { await toggleCompletion(of: todo) }
          } label: {
            Image(systemName: todo.isComplete ? "checkmark.circle.fill" : "circle")
          }
          .buttonStyle(.plain)
        }
      }
      .onDelete { indexSet in
        Task {
          await delete(at: indexSet)
        }
      }
    }
    .animation(.default, value: todos)
    .navigationTitle("Todos")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if createTodoRequest == nil {
          Button {
            withAnimation {
              createTodoRequest = .init(description: "", isComplete: false, ownerID: auth.currentUserID)
            }
          } label: {
            Label("Add", systemImage: "plus")
          }
        } else {
          Button("Cancel", role: .cancel) {
            withAnimation {
              createTodoRequest = nil
            }
          }
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

      let updateRequest = UpdateTodoRequest(isComplete: updatedTodo.isComplete, ownerID: auth.currentUserID)
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

  func delete(at offset: IndexSet) async {
    let oldTodos = todos

    do {
      error = nil
      let todosToDelete = offset.map { todos[$0] }

      self.todos.remove(atOffsets: offset)

      try await supabase.database.from("todos")
        .delete()
        .in(column: "id", value: todosToDelete.map(\.id))
        .execute()
    } catch {
      self.error = error

      // rollback todos on error.
      self.todos = oldTodos
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
