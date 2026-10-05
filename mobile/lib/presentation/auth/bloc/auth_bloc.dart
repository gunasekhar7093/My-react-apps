import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository repository;

  AuthBloc({AuthRepository? repository})
      : repository = repository ?? AuthRepository(),
        super(const AuthState()) {
    on<AuthStarted>(_onAuthStarted);
    on<LoginSubmitted>(_onLoginSubmitted);
    on<RegisterSubmitted>(_onRegisterSubmitted);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onAuthStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.checkingSession, clearError: true));
    final user = await repository.restoreSession();
    if (user == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } else {
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    }
  }

  Future<void> _onLoginSubmitted(LoginSubmitted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.authenticating, clearError: true));
    try {
      final result = await repository.login(username: event.username, password: event.password);
      emit(AuthState(status: AuthStatus.authenticated, user: result.user));
    } on ApiException catch (error) {
      emit(state.copyWith(status: AuthStatus.failure, errorMessage: error.message));
    } catch (_) {
      emit(state.copyWith(status: AuthStatus.failure, errorMessage: 'Unable to connect to the server.'));
    }
  }

  Future<void> _onRegisterSubmitted(RegisterSubmitted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.authenticating, clearError: true));
    try {
      final result = await repository.register(name: event.name, username: event.username, password: event.password, phone: event.phone);
      emit(AuthState(status: AuthStatus.authenticated, user: result.user));
    } on ApiException catch (error) {
      emit(state.copyWith(status: AuthStatus.failure, errorMessage: error.message));
    } catch (_) {
      emit(state.copyWith(status: AuthStatus.failure, errorMessage: 'Unable to connect to the server.'));
    }
  }

  Future<void> _onLogoutRequested(LogoutRequested event, Emitter<AuthState> emit) async {
    await repository.logout();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
