import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/account.dart';
import '../../../data/account_repository.dart';
import '../../../data/publication_settings_repository.dart';

/// Écran « Compte et profil » : identité, connexion, espace de travail et
/// déconnexion. Toutes les valeurs affichées viennent de la session Supabase
/// et de la base ; le nom affiché et le nom de l'espace sont modifiables
/// selon les droits.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    this.repository,
    this.onSignOut,
    this.onChanged,
  });

  /// Injectable pour les tests ; par défaut, Supabase.
  final AccountRepository? repository;

  /// Déconnexion ; le bouton n'apparaît que si elle est fournie.
  final Future<void> Function()? onSignOut;

  /// Appelé après une modification (pour rafraîchir l'accueil).
  final Future<void> Function()? onChanged;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final AccountRepository _repo;
  final _nameController = TextEditingController();
  final _workspaceController = TextEditingController();

  AccountDetails? _details;
  Object? _loadError;
  bool _loading = true;
  bool _savingName = false;
  bool _savingWorkspace = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ??
        SupabaseAccountRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _workspaceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final details = await _repo.load();
      if (!mounted) return;
      setState(() {
        _details = details;
        _nameController.text = details.displayName ?? '';
        _workspaceController.text = details.workspaceName;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  String _messageFor(Object error) =>
      error is AccountUpdateException ? error.message : describeError(error);

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _nameChanged {
    final details = _details;
    if (details == null) return false;
    return _nameController.text.trim() != (details.displayName ?? '');
  }

  bool get _workspaceChanged {
    final details = _details;
    if (details == null) return false;
    final value = _workspaceController.text.trim();
    return value.isNotEmpty && value != details.workspaceName;
  }

  Future<void> _saveName() async {
    final details = _details;
    if (details == null) return;
    final value = _nameController.text.trim();
    setState(() => _savingName = true);
    try {
      await _repo.saveDisplayName(value);
      if (!mounted) return;
      setState(() {
        _details = details.withDisplayName(value.isEmpty ? null : value);
        _savingName = false;
      });
      _toast('Nom enregistré.');
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingName = false);
      _toast(_messageFor(error));
    }
  }

  Future<void> _renameWorkspace() async {
    final details = _details;
    if (details == null) return;
    final value = _workspaceController.text.trim();
    setState(() => _savingWorkspace = true);
    try {
      await _repo.renameWorkspace(details.workspaceId, value);
      if (!mounted) return;
      setState(() {
        _details = details.withWorkspaceName(value);
        _savingWorkspace = false;
      });
      _toast('Espace renommé.');
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingWorkspace = false);
      _toast(_messageFor(error));
    }
  }

  Future<void> _confirmSignOut() async {
    final signOut = widget.onSignOut;
    if (signOut == null) return;
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Tu devras te reconnecter pour retrouver ton espace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // On quitte cet écran avant la déconnexion : il ne doit pas rester
    // affiché par-dessus l'écran de connexion.
    navigator.pop();
    signOut();
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (details == null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                describeError(_loadError ?? 'inconnue'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: _buildContent(context, details),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Compte et profil')),
      body: content,
    );
  }

  Widget _buildContent(BuildContext context, AccountDetails d) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 28),
      children: [
        _identityCard(d, p, theme),
        const SizedBox(height: 14),
        _section(
          'Profil',
          theme,
          children: [
            TextField(
              key: const ValueKey('display_name'),
              controller: _nameController,
              maxLength: kMaxDisplayName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom affiché',
                helperText: 'Apparaît sur ton accueil.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('save_name'),
                onPressed: (_nameChanged && !_savingName) ? _saveName : null,
                child: _savingName
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer le nom'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _section(
          'Connexion',
          theme,
          children: [
            _info('Adresse e-mail', d.email ?? 'Non renseignée', p, theme),
            _info(
              'Méthode de connexion',
              d.providers.isEmpty
                  ? 'Non renseignée'
                  : d.providers.map(providerLabel).join(', '),
              p,
              theme,
            ),
            _info(
              'E-mail confirmé',
              d.emailConfirmed ? 'Oui' : 'Non',
              p,
              theme,
            ),
            _info(
              'Compte créé le',
              d.createdAt == null
                  ? 'Inconnu'
                  : formatFrenchDate(d.createdAt!),
              p,
              theme,
            ),
            _info(
              'Dernière connexion',
              d.lastSignInAt == null
                  ? 'Inconnue'
                  : formatFrenchDateTime(d.lastSignInAt!),
              p,
              theme,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _section(
          'Espace de travail',
          theme,
          children: [
            if (d.canRenameWorkspace) ...[
              TextField(
                key: const ValueKey('workspace_name'),
                controller: _workspaceController,
                maxLength: kMaxWorkspaceName,
                decoration: const InputDecoration(
                  labelText: 'Nom de l’espace',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const ValueKey('rename_workspace'),
                  onPressed: (_workspaceChanged && !_savingWorkspace)
                      ? _renameWorkspace
                      : null,
                  child: _savingWorkspace
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Renommer'),
                ),
              ),
              const SizedBox(height: 8),
            ] else
              _info('Nom de l’espace', d.workspaceName, p, theme),
            _info('Ton rôle', accountRoleLabel(d.role), p, theme),
            if (d.workspaceCreatedAt != null)
              _info(
                'Espace créé le',
                formatFrenchDate(d.workspaceCreatedAt!),
                p,
                theme,
              ),
            if (d.memberCount != null)
              _info('Membres', '${d.memberCount}', p, theme),
            _info(
              'Pages Facebook connectées',
              d.activePageCount == 0
                  ? 'Aucune'
                  : (d.pageName == null
                      ? '${d.activePageCount}'
                      : '${d.activePageCount} (${d.pageName})'),
              p,
              theme,
            ),
          ],
        ),
        if (widget.onSignOut != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _confirmSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Se déconnecter'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.glassBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _identityCard(AccountDetails d, SgPalette p, ThemeData theme) {
    final url = d.avatarUrl;
    final name = d.displayName;

    return GlassPanel(
      highlight: true,
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: p.accent.withValues(alpha: 0.18),
            foregroundImage: url == null ? null : NetworkImage(url),
            onForegroundImageError: url == null ? null : (_, __) {},
            child: Text(
              initialsOf(name, d.email),
              style: theme.textTheme.titleLarge?.copyWith(color: p.accent),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Nom non renseigné',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                if (d.email != null)
                  Text(
                    d.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SgPill(
                      label: accountRoleLabel(d.role),
                      color: p.accent,
                    ),
                    if (d.emailConfirmed)
                      SgPill(
                        label: 'E-mail confirmé',
                        color: p.success,
                        icon: Icons.check_circle_outline,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title,
    ThemeData theme, {
    required List<Widget> children,
  }) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _info(String label, String value, SgPalette p, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
