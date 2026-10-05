import '../../../data/models/user_model.dart';

enum AuthStatus { initial, checkingSession, unauthenticated, authenticating, authenticated, failure }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;

  const AuthState({this.status = AuthStatus.initial, this.user, this.errorMessage});

  AuthState copyWith({AuthStatus? status, UserModel? user, String? errorMessage, bool clearError = false}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
