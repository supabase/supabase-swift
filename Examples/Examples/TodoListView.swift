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
  @Environment(AuthController.self) var auth

  @State var todos: IdentifiedArrayOf<Todo> = []
  @State var error: Error?

  @State var createTodoRequest: CreateTodoRequest?

  var body: some View {
    List {
      if let error {
        ErrorText(error)
      }

      IfLet($createTodoRequest) { $createTodoRequest in
        AddTodoListView(request: $createTodoRequest) { result in
          withAnimation {
            //            createTodoRequest = nil

            switch result {
            case .success(let todo):
              error = nil
              _ = todos.insert(todo, at: 0)
            case .failure(let error):
              self.error = error
            }
          }
        }
      }

      ForEach(todos) { todo in
        TodoListRow(todo: todo) {
          Task {
            await toggleCompletion(of: todo)
          }
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
              createTodoRequest = .init(
                description: "",
                isComplete: false,
                ownerID: auth.currentUserID
              )
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
        todos = try await IdentifiedArrayOf(
          uniqueElements: supabase.from("todos")
            .select()
            .execute()
            .value as [Todo]
        )
      } catch {
        self.error = error
      }
    }
  }

  @MainActor
  func toggleCompletion(of todo: Todo) async {
    var updatedTodo = todo
    updatedTodo.isComplete.toggle()
    todos[id: todo.id] = updatedTodo

    do {
      error = nil

      let updateRequest = UpdateTodoRequest(
        isComplete: updatedTodo.isComplete,
        ownerID: auth.currentUserID
      )
      updatedTodo = try await supabase.from("todos")
        .update(updateRequest, returning: .representation)
        .eq("id", value: updatedTodo.id)
        .single()
        .execute()
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

      todos.remove(atOffsets: offset)

      try await supabase.from("todos")
        .delete()
        .in("id", values: todosToDelete.map(\.id))
        .execute()
    } catch {
      self.error = error

      // rollback todos on error.
      todos = oldTodos
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
