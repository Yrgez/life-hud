import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'life_hud_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LifeHudApp()));
}

class LifeHudApp extends StatelessWidget {
  const LifeHudApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Life HUD',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.tealAccent,
        ),
        home: const LifeHudScreen(),
      );
}
