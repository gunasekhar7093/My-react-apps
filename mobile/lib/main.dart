import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/repositories/auth_repository.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/auth/bloc/auth_event.dart';
import 'presentation/auth/bloc/auth_state.dart';
import 'presentation/auth/pages/login_page.dart';
import 'presentation/auth/pages/register_page.dart';
import 'presentation/dashboard/pages/dashboard_page.dart';

void main() {
  runApp(const ChatSpaceApp());
}

class ChatSpaceApp extends StatelessWidget {
  const ChatSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(repository: AuthRepository())..add(const AuthStarted()),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ChatSpace',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool showRegister = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        switch (state.status) {
          case AuthStatus.initial:
          case AuthStatus.checkingSession:
          case AuthStatus.authenticating:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AuthStatus.authenticated:
            return const DashboardPage();
          case AuthStatus.unauthenticated:
          case AuthStatus.failure:
            return showRegister
                ? RegisterPage(onLogin: () => setState(() => showRegister = false))
                : LoginPage(onRegister: () => setState(() => showRegister = true));
        }
      },
    );
  }
}
