import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/reveal.dart';
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

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SgReveal(
                      child: Center(
                        child: Container(
                          width: 128,
                          height: 128,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(44),
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Container(
                            width: 94,
                            height: 94,
                            decoration: BoxDecoration(
                              gradient: SgPalette.brand,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: p.accent.withValues(alpha: 0.6),
                                  blurRadius: 44,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              size: 46,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SgReveal(
                      order: 1,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SocialGrow',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontSize: 38,
                                  letterSpacing: -1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    SgPalette.brand.createShader(bounds),
                                child: Text(
                                  'AI',
                                  style:
                                      theme.textTheme.headlineMedium?.copyWith(
                                    fontSize: 38,
                                    letterSpacing: -1.2,
                                    color: Colors.white,
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
                    const SizedBox(height: 22),
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
                    const SizedBox(height: 40),
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
