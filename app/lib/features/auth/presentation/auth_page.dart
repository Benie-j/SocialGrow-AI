import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/growth_plant.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sg_background.dart';
import '../../../core/widgets/sg_gradient_button.dart';
import '../../../core/widgets/sg_pill.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLoading = false;

  SupabaseClient get _client => Supabase.instance.client;

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signInWithFacebook() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: 'socialgrowai://login-callback',
        queryParams: {
          'config_id': '1678260010520297',
        },
      );
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage(
        'Impossible de lancer la connexion Facebook. '
        'Vérifie ta connexion Internet et réessaie.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);

    return SgBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: GrowthPlant(
                        size: 270,
                        growth: 1,
                        duration: Duration(milliseconds: 2800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SgReveal(
                      order: 1,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'SocialGrow',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontSize: 44,
                                  letterSpacing: -2.4,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Transform.rotate(
                                angle: -0.07,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: SgPalette.lime,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: p.isDark
                                          ? SgPalette.lime
                                          : SgPalette.inkDark,
                                      width: 1.6,
                                    ),
                                  ),
                                  child: Text(
                                    'AI',
                                    style:
                                        theme.textTheme.headlineMedium?.copyWith(
                                      fontSize: 40,
                                      letterSpacing: -1.5,
                                      color: SgPalette.inkDark,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SgReveal(
                      order: 2,
                      child: Text(
                        'Développe ta présence sur Facebook grâce à '
                        'l’intelligence artificielle.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: p.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SgReveal(
                      order: 3,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SgPill(
                            label: 'Idées IA',
                            icon: Icons.lightbulb_outline,
                            color: p.accentWarm,
                          ),
                          SgPill(
                            label: 'Planning',
                            icon: Icons.edit_calendar_outlined,
                            color: p.accentCool,
                          ),
                          SgPill(
                            label: 'Stats réelles',
                            icon: Icons.query_stats,
                            color: p.accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SgReveal(
                      order: 4,
                      child: SgGradientButton(
                        onPressed: _isLoading ? null : _signInWithFacebook,
                        loading: _isLoading,
                        icon: Icons.facebook,
                        label: _isLoading
                            ? 'Connexion en cours...'
                            : 'Continuer avec Facebook',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'En continuant, tu autorises SocialGrow AI à accéder '
                      'aux Pages Facebook que tu choisis, selon les '
                      'permissions accordées.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
