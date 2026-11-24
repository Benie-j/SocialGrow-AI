import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ismatpttxrsbqtravgkr.supabase.co',
    publishableKey: 'sb_publishable_Rdyho9ktQQDVFHiEZ3wwBQ_xFi1ST82',
  );

  runApp(const SocialGrowApp());
}

class SocialGrowApp extends StatelessWidget {
  const SocialGrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SocialGrow AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}
