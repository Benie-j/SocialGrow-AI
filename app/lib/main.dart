import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_gate.dart';
import 'features/splash/presentation/splash_gate.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ismatpttxrsbqtravgkr.supabase.co',
    publishableKey: 'sb_publishable_Rdyho9ktQQDVFHiEZ3wwBQ_xFi1ST82',
  );

  runApp(const JunApp());
}

class JunApp extends StatelessWidget {
  const JunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JUN AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Identité « Sève » : clair ou sombre selon le réglage du téléphone.
      themeMode: ThemeMode.system,
      home: const SplashGate(child: AuthGate()),
    );
  }
}
