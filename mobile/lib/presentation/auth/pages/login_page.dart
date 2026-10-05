import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onRegister;
  const LoginPage({super.key, required this.onRegister});
  @override State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override void dispose() { _username.dispose(); _password.dispose(); super.dispose(); }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(LoginSubmitted(username: _username.text.trim(), password: _password.text));
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final loading = state.status == AuthStatus.authenticating;
                  return Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Icon(Icons.chat_bubble_rounded, size: 58),
                      const SizedBox(height: 18),
                      Text('ChatSpace', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Sign in to continue', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 36),
                      if (state.status == AuthStatus.failure)
                        Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(state.errorMessage ?? 'Login failed', style: TextStyle(color: Theme.of(context).colorScheme.error))),
                      TextFormField(controller: _username, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username / Email', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'Enter your username or email' : null),
                      const SizedBox(height: 16),
                      TextFormField(controller: _password, obscureText: _obscure, onFieldSubmitted: (_) => _submit(), decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))), validator: (v) => v == null || v.isEmpty ? 'Enter your password' : null),
                      const SizedBox(height: 24),
                      SizedBox(height: 52, child: FilledButton(onPressed: loading ? null : _submit, child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign In'))),
                      const SizedBox(height: 18),
                      TextButton(onPressed: loading ? null : widget.onRegister, child: const Text("Don't have an account? Create one")),
                    ]),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
