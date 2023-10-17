extension AuthResponse {
  public var user: User? {
    if case let .user(user) = self { return user }
    return nil
  }

  public var session: Session? {
    if case let .session(session) = self { return session }
    return nil
  }
}
