import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

// Replace the placeholder with frontend routes once shared contracts are reviewed.
final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('SmartSpend — backend foundation')),
      ),
    ),
  ],
);
