import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/sg_gradient_button.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/facebook_connection.dart';

/// Écran « Connexion Facebook » : Pages connectées à l'espace, choix d'une
/// nouvelle Page parmi celles que l'utilisateur gère chez Meta, déconnexion.
class FacebookConnectionPage extends StatefulWidget {
  const FacebookConnectionPage({
    super.key,
    required this.repository,
    required this.workspaceId,
    required this.role,
    this.onChanged,
  });

  final FacebookConnectionRepository repository;
  final String workspaceId;

  /// owner, admin, editor ou viewer : seuls owner et admin peuvent connecter.
  final String role;

  /// Appelé après une connexion ou une déconnexion (pour actualiser l'accueil).
  final Future<void> Function()? onChanged;

  @override
  State<FacebookConnectionPage> createState() => _FacebookConnectionPageState();
}

class _FacebookConnectionPageState extends State<FacebookConnectionPage>
    with WidgetsBindingObserver {
  bool _loadingConnected = true;
  String? _connectedError;
  List<ConnectedFacebookPage> _connected = const [];

  bool _loadingAvailable = false;
  String? _availableError;
  List<FacebookPage>? _available;

  /// Identifiant Meta de la Page en cours de connexion, ou id de la Page en
  /// cours de déconnexion.
  String? _busyId;

  StreamSubscription<void>? _sessionSub;

  bool get _canManage => widget.role == 'owner' || widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionSub = widget.repository.sessionChanges.listen(
      (_) => _afterAuthorizationMayHaveChanged(),
      onError: (Object error, StackTrace stackTrace) {},
    );
    _loadConnected();
    if (_canManage && widget.repository.hasFacebookAuthorization) {
      _loadAvailable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _afterAuthorizationMayHaveChanged();
    }
  }

  void _afterAuthorizationMayHaveChanged() {
    if (!mounted) return;
    if (_canManage &&
        widget.repository.hasFacebookAuthorization &&
        _available == null &&
        !_loadingAvailable) {
      _loadAvailable();
    } else {
      setState(() {});
    }
  }

  String _message(Object error) {
    if (error is FacebookConnectionException) return error.message;
    return 'Une erreur est survenue. Vérifie ta connexion et réessaie.';
  }

  Future<void> _loadConnected() async {
    setState(() {
      _loadingConnected = true;
      _connectedError = null;
    });
    try {
      final pages = await widget.repository.loadConnected(widget.workspaceId);
      if (!mounted) return;
      setState(() {
        _connected = pages;
        _loadingConnected = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectedError = _message(error);
        _loadingConnected = false;
      });
    }
  }

  Future<void> _loadAvailable() async {
    setState(() {
      _loadingAvailable = true;
      _availableError = null;
    });
    try {
      final pages = await widget.repository.listAvailablePages();
      if (!mounted) return;
      setState(() {
        _available = pages;
        _loadingAvailable = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _availableError = _message(error);
        _loadingAvailable = false;
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _reauthorize() async {
    try {
      await widget.repository.reauthorize();
    } catch (error) {
      if (!mounted) return;
      _toast(_message(error));
    }
  }

  Future<void> _connect(FacebookPage page) async {
    if (_busyId != null) return;
    setState(() => _busyId = page.metaPageId);
    try {
      await widget.repository.connectPage(
        workspaceId: widget.workspaceId,
        page: page,
      );
      if (!mounted) return;
      _toast('« ${page.name} » est connectée.');
      await _loadConnected();
      await widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      _toast(_message(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _disconnect(ConnectedFacebookPage page) async {
    if (_busyId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Déconnecter cette Page ?'),
        content: Text(
          '« ${page.name} » ne sera plus gérée par SocialGrow AI. Ses '
          'publications déjà créées restent dans ton historique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = page.id);
    try {
      await widget.repository.disconnect(page.id);
      if (!mounted) return;
      _toast('« ${page.name} » est déconnectée.');
      await _loadConnected();
      await widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      _toast(_message(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Connexion Facebook')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 32),
        children: [
          Text('Page connectée', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _buildConnected(p, theme),
          const SizedBox(height: 28),
          Text('Ajouter une Page', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _buildAvailable(p, theme),
        ],
      ),
    );
  }

  Widget _buildConnected(SgPalette p, ThemeData theme) {
    if (_loadingConnected) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final error = _connectedError;
    if (error != null) {
      return _Notice(
        text: error,
        actionLabel: 'Réessayer',
        onAction: _loadConnected,
      );
    }
    if (_connected.isEmpty) {
      return const _Notice(
        text: 'Aucune Page n’est connectée pour le moment.',
      );
    }
    return Column(
      children: [
        for (final page in _connected) ...[
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _Avatar(url: page.pictureUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(page.name, style: theme.textTheme.titleMedium),
                      if (page.category != null)
                        Text(
                          page.category!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: p.textSecondary),
                        ),
                      const SizedBox(height: 6),
                      SgPill(label: 'Connectée', color: p.success),
                    ],
                  ),
                ),
                if (_canManage)
                  _busyId == page.id
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _disconnect(page),
                          child: const Text('Déconnecter'),
                        ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildAvailable(SgPalette p, ThemeData theme) {
    if (!_canManage) {
      return const _Notice(
        text: 'Seuls les propriétaires et les administrateurs de l’espace '
            'peuvent connecter ou déconnecter une Page.',
      );
    }

    if (!widget.repository.hasFacebookAuthorization) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Notice(
            text: 'Pour choisir une Page, autorise de nouveau l’accès à tes '
                'Pages Facebook. Tu seras renvoyé vers Facebook, puis ici.',
          ),
          const SizedBox(height: 12),
          SgGradientButton(
            onPressed: _reauthorize,
            icon: Icons.facebook,
            label: 'Autoriser l’accès à mes Pages',
          ),
        ],
      );
    }

    if (_loadingAvailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final error = _availableError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Notice(
            text: error,
            actionLabel: 'Réessayer',
            onAction: _loadAvailable,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _reauthorize,
            child: const Text('Autoriser de nouveau l’accès à mes Pages'),
          ),
        ],
      );
    }

    final connectedIds = {for (final c in _connected) c.metaPageId};
    final pages = [
      for (final page in _available ?? const <FacebookPage>[])
        if (!connectedIds.contains(page.metaPageId)) page,
    ];

    if (pages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Notice(
            text: (_available ?? const []).isEmpty
                ? 'Facebook ne renvoie aucune Page que tu peux gérer. '
                    'Vérifie que tu as accepté l’accès à tes Pages.'
                : 'Toutes tes Pages sont déjà connectées.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _loadAvailable,
            child: const Text('Actualiser la liste'),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (final page in pages) ...[
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _Avatar(url: page.pictureUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(page.name, style: theme.textTheme.titleMedium),
                      if (page.category != null)
                        Text(
                          page.category!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: p.textSecondary),
                        ),
                    ],
                  ),
                ),
                _busyId == page.metaPageId
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed: _busyId == null ? () => _connect(page) : null,
                        child: const Text('Connecter'),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final image = url;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: p.accentCool.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? Icon(Icons.facebook, color: p.accentCool)
          : Image.network(
              image,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.facebook, color: p.accentCool),
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final label = actionLabel;

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: p.textSecondary, height: 1.4),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    );
  }
}
