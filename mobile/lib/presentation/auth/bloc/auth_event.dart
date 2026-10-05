sealed class AuthEvent {
  const AuthEvent();
}

final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

final class LoginSubmitted extends AuthEvent {
  final String username;
  final String password;
  const LoginSubmitted({required this.username, required this.password});
}

final class RegisterSubmitted extends AuthEvent {
  final String name;
  final String username;
  final String password;
  final String phone;
  const RegisterSubmitted({required this.name, required this.username, required this.password, required this.phone});
}

final class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}
