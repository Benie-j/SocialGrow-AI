import 'package:material_ui/material_ui.dart';

import '../../../core/theme/sg_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/sg_pill.dart';
import '../../../data/facebook_connection.dart';

enum _Phase { loading, ready, failed, needsReauth }

/// Réglages > Connexion Facebook : voir la Page connectée, en choisir une
/// autre parmi celles que l'on gère, ou la déconnecter.
class FacebookConnectionPage extends StatefulWidget {
  const FacebookConnectionPage({
    super.key,
    required this.repository,
    required this.workspaceId,
    required this.canEdit,
    this.connectedPage,
    this.onChanged,
  });

  final FacebookConnectionRepository repository;
  final String workspaceId;

  /// Propriétaire, administrateur ou éditeur : seuls rôles autorisés à écrire.
  final bool canEdit;
  final ConnectedFacebookPage? connectedPage;

  /// Appelé après une connexion ou une déconnexion réussie (actualise l'accueil).
  final Future<void> Function()? onChanged;

  @override
  State<FacebookConnectionPage> createState() => _FacebookConnectionPageState();
}

class _FacebookConnectionPageState extends State<FacebookConnectionPage>
    with WidgetsBindingObserver {
  static const _reauthMessage =
      'Reconnecte-toi avec Facebook pour afficher tes Pages.';

  _Phase _phase = _Phase.loading;
  String? _message;
  List<FacebookPageChoice> _pages = const [];
  ConnectedFacebookPage? _connected;
  String? _selectedId;
  bool _busy = false;
  bool _awaitingReauth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connected = widget.connectedPage;

    if (!widget.canEdit) {
      _phase = _Phase.ready;
    } else if (!widget.repository.hasFacebookSession) {
      _phase = _Phase.needsReauth;
      _message = _reauthMessage;
    } else {
      _fetchPages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Au retour du navigateur après une reconnexion, on recharge les Pages.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReauth) {
      _awaitingReauth = false;
      _reload();
    }
  }

  Future<void> _fetchPages() async {
    try {
      final pages = await widget.repository.listPages(widget.workspaceId);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _phase = _Phase.ready;
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      final failure = facebookErrorFrom(error);
      setState(() {
        _phase = failure.needsReauth ? _Phase.needsReauth : _Phase.failed;
        _message = failure.message;
      });
    }
  }

  Future<void> _reload() async {
    if (!widget.canEdit) return;
    setState(() {
      _phase = _Phase.loading;
      _selectedId = null;
    });
    if (!widget.repository.hasFacebookSession) {
      setState(() {
        _phase = _Phase.needsReauth;
        _message = _reauthMessage;
      });
      return;
    }
    await _fetchPages();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reauthenticate() async {
    _awaitingReauth = true;
    try {
      await widget.repository.reauthenticate();
    } catch (error) {
      _awaitingReauth = false;
      if (!mounted) return;
      _snack(facebookErrorFrom(error).message);
    }
  }

  Future<void> _connect() async {
    final id = _selectedId;
    if (id == null || _busy) return;

    setState(() => _busy = true);
    try {
      final result = await widget.repository.connect(widget.workspaceId, id);
      if (!mounted) return;
      setState(() {
        _connected = result.page;
        _selectedId = null;
        _busy = false;
      });
      _snack(
        result.longLived
            ? 'Page connectée : ${result.page.name}.'
            : 'Page connectée : ${result.page.name}. '
                'La connexion est temporaire et durera quelques heures.',
      );
      await widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      final failure = facebookErrorFrom(error);
      setState(() {
        _busy = false;
        if (failure.needsReauth) {
          _phase = _Phase.needsReauth;
          _message = failure.message;
        }
      });
      _snack(failure.message);
    }
  }

  Future<void> _disconnect() async {
    final connected = _connected;
    if (connected == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Déconnecter la Page ?'),
        content: Text(
          'SocialGrow AI ne pourra plus publier sur « ${connected.name} ». '
          'Tu pourras la reconnecter à tout moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.disconnect(widget.workspaceId);
      if (!mounted) return;
      setState(() {
        _connected = null;
        _busy = false;
      });
      _snack('Page déconnectée.');
      await widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(facebookErrorFrom(error).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Connexion Facebook')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 32),
        children: [
          _CurrentPageCard(
            page: _connected,
            canEdit: widget.canEdit,
            busy: _busy,
            onDisconnect: _disconnect,
          ),
          const SizedBox(height: 24),
          if (!widget.canEdit)
            const _InfoCard(
              icon: Icons.lock_outline,
              text: 'Lecture seule : seuls les propriétaires, administrateurs '
                  'et éditeurs peuvent gérer la connexion Facebook.',
            )
          else
            ..._pagesSection(context),
        ],
      ),
    );
  }

  List<Widget> _pagesSection(BuildContext context) {
    final theme = Theme.of(context);
    final p = SgPalette.of(context);
    final connected = _connected;

    final title = Text(
      connected == null ? 'Choisis ta Page' : 'Changer de Page',
      style: theme.textTheme.titleLarge,
    );

    switch (_phase) {
      case _Phase.loading:
        return [
          title,
          const SizedBox(height: 24),
          Center(child: CircularProgressIndicator(color: p.accent)),
        ];

      case _Phase.failed:
        return [
          title,
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.cloud_off_outlined,
            text: _message ?? 'Impossible de charger tes Pages.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _reload,
            child: const Text('Réessayer'),
          ),
        ];

      case _Phase.needsReauth:
        return [
          title,
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.refresh_rounded,
            text: _message ?? _reauthMessage,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _reauthenticate,
            icon: const Icon(Icons.facebook),
            label: const Text('Se reconnecter avec Facebook'),
          ),
        ];

      case _Phase.ready:
        final choices = [
          for (final page in _pages)
            if (page.metaPageId != connected?.metaPageId) page,
        ];

        if (choices.isEmpty) {
          return [
            title,
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.info_outline,
              text: connected == null
                  ? 'Facebook ne renvoie aucune Page que tu gères. Vérifie '
                      'que ton compte administre une Page, puis actualise.'
                  : 'Tu n’as pas d’autre Page à connecter.',
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Actualiser'),
            ),
          ];
        }

        return [
          title,
          const SizedBox(height: 12),
          for (final page in choices) ...[
            _PageTile(
              page: page,
              selected: page.metaPageId == _selectedId,
              enabled: !_busy,
              onTap: () => setState(() {
                _selectedId =
                    page.metaPageId == _selectedId ? null : page.metaPageId;
              }),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _selectedId == null || _busy ? null : _connect,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text(
                    connected == null
                        ? 'Connecter cette Page'
                        : 'Utiliser cette Page',
                  ),
          ),
        ];
    }
  }
}

class _PageAvatar extends StatelessWidget {
  const _PageAvatar({required this.url, this.size = 48});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final picture = url;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.accentCool.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Icon(Icons.facebook, color: p.accentCool),
            if (picture != null)
              Image.network(
                picture,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrentPageCard extends StatelessWidget {
  const _CurrentPageCard({
    required this.page,
    required this.canEdit,
    required this.busy,
    required this.onDisconnect,
  });

  final ConnectedFacebookPage? page;
  final bool canEdit;
  final bool busy;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final current = page;

    if (current == null) {
      return GlassPanel(
        radius: 22,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.link_off, color: p.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aucune Page connectée',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Connecte une Page pour publier et suivre ses résultats.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GlassPanel(
      radius: 22,
      highlight: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PageAvatar(url: current.pictureUrl, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (current.category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        current.category!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SgPill(label: 'Connectée', color: p.success),
            ],
          ),
          if (canEdit) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: busy ? null : onDisconnect,
              icon: const Icon(Icons.link_off),
              label: const Text('Déconnecter la Page'),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accentWarm,
                side: BorderSide(color: p.accentWarm.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FacebookPageChoice page;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);
    final category = page.category;

    return GlassPanel(
      radius: 20,
      highlight: selected,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          _PageAvatar(url: page.pictureUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (category != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    category,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? p.accent : p.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = SgPalette.of(context);
    final theme = Theme.of(context);

    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: p.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
