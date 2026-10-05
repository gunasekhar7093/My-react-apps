import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.user);
    final initial = (user?.name.isNotEmpty == true) ? user!.name[0].toUpperCase() : '?';
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChatSpace'),
        actions: [
          CircleAvatar(child: Text(initial)),
          const SizedBox(width: 12),
          IconButton(tooltip: 'Log out', onPressed: () => context.read<AuthBloc>().add(const LogoutRequested()), icon: const Icon(Icons.logout)),
        ],
      ),
      body: Center(child: Text('Welcome, ${user?.name ?? ''}', style: Theme.of(context).textTheme.headlineSmall)),
    );
  }
}
