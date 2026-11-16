import 'package:material_ui/material_ui.dart';

import 'router.dart';

/// Bootstrap only. The frontend developer owns the product UI and theme.
class SmartSpendApp extends StatelessWidget {
  const SmartSpendApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SmartSpend',
    routerConfig: appRouter,
    debugShowCheckedModeBanner: false,
  );
}
