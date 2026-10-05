import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback onLogin;
  const RegisterPage({super.key, required this.onLogin});
  @override State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override void dispose() { _name.dispose(); _username.dispose(); _phone.dispose(); _password.dispose(); super.dispose(); }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(RegisterSubmitted(name: _name.text.trim(), username: _username.text.trim(), password: _password.text, phone: _phone.text.trim()));
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
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
                      Text('Join ChatSpace', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      if (state.status == AuthStatus.failure)
                        Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(state.errorMessage ?? 'Registration failed', style: TextStyle(color: Theme.of(context).colorScheme.error))),
                      TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.badge_outlined), border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name' : null),
                      const SizedBox(height: 14),
                      TextFormField(controller: _username, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username / Email', prefixIcon: Icon(Icons.alternate_email), border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'Enter your username or email' : null),
                      const SizedBox(height: 14),
                      TextFormField(controller: _phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder())),
                      const SizedBox(height: 14),
                      TextFormField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure))), validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 characters' : null),
                      const SizedBox(height: 24),
                      SizedBox(height: 52, child: FilledButton(onPressed: loading ? null : _submit, child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Account'))),
                      const SizedBox(height: 14),
                      TextButton(onPressed: loading ? null : widget.onLogin, child: const Text('Already have an account? Sign in')),
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
