/// Vue d'ensemble réelle de l'espace de travail de l'utilisateur connecté.
class WorkspaceOverview {
  const WorkspaceOverview({
    required this.workspaceId,
    required this.workspaceName,
    required this.role,
    required this.activePageCount,
    this.hasEditorialStrategy = false,
    this.hasAiActivity = false,
    this.pageName,
    this.displayName,
    this.avatarUrl,
  });

  final String workspaceId;
  final String workspaceName;

  /// owner, admin, editor ou viewer.
  final String role;

  /// Nombre de Pages Facebook actives connectées à l'espace.
  final int activePageCount;

  /// Vrai quand la stratégie éditoriale de l'espace est renseignée
  /// (ligne enregistrée avec une description de l'activité).
  final bool hasEditorialStrategy;

  /// Vrai quand au moins une génération Groq a réussi pour l'espace
  /// (journal `ai_generation_logs`) : preuve que l'assistant IA fonctionne.
  final bool hasAiActivity;

  /// Nom de la Page connectée la plus ancienne, s'il y en a une.
  final String? pageName;

  /// Nom et photo du profil, s'ils sont renseignés.
  final String? displayName;
  final String? avatarUrl;

  bool get hasConnectedPage => activePageCount > 0;

  String get roleLabel {
    switch (role) {
      case 'owner':
        return 'Propriétaire';
      case 'admin':
        return 'Administrateur';
      case 'editor':
        return 'Éditeur';
      case 'viewer':
        return 'Lecteur';
      default:
        return role;
    }
  }
}

enum WorkspaceStatus { idle, loading, ready, failed }

/// État de chargement de l'espace de travail, tel qu'affiché dans l'interface.
class WorkspaceState {
  const WorkspaceState._(this.status, {this.overview, this.message});

  /// Aucun dépôt de données fourni : rien n'est chargé ni affiché.
  const WorkspaceState.idle() : this._(WorkspaceStatus.idle);

  const WorkspaceState.loading() : this._(WorkspaceStatus.loading);

  const WorkspaceState.ready(WorkspaceOverview overview)
      : this._(WorkspaceStatus.ready, overview: overview);

  const WorkspaceState.failed(String message)
      : this._(WorkspaceStatus.failed, message: message);

  final WorkspaceStatus status;
  final WorkspaceOverview? overview;
  final String? message;
}
