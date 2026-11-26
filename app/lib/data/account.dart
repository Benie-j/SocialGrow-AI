/// Informations réelles du compte connecté, de son profil et de son espace de
/// travail. Tout vient de la session Supabase et de la base : aucune donnée
/// n'est fixée dans l'application.
class AccountDetails {
  const AccountDetails({
    required this.email,
    required this.providers,
    required this.createdAt,
    required this.lastSignInAt,
    required this.emailConfirmed,
    required this.displayName,
    required this.avatarUrl,
    required this.workspaceId,
    required this.workspaceName,
    required this.role,
    required this.workspaceCreatedAt,
    required this.memberCount,
    required this.activePageCount,
    required this.pageName,
  });

  final String? email;

  /// Méthodes de connexion (identifiants Supabase : google, email…).
  final List<String> providers;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final bool emailConfirmed;

  final String? displayName;
  final String? avatarUrl;

  final String workspaceId;
  final String workspaceName;

  /// owner, admin, editor ou viewer.
  final String role;
  final DateTime? workspaceCreatedAt;

  /// Nombre de membres ; seulement connu des propriétaires et administrateurs
  /// (les autres ne voient que leur propre appartenance).
  final int? memberCount;
  final int activePageCount;
  final String? pageName;

  /// Seuls le propriétaire et les administrateurs peuvent renommer l'espace.
  bool get canRenameWorkspace => role == 'owner' || role == 'admin';

  AccountDetails withDisplayName(String? value) => AccountDetails(
        email: email,
        providers: providers,
        createdAt: createdAt,
        lastSignInAt: lastSignInAt,
        emailConfirmed: emailConfirmed,
        displayName: value,
        avatarUrl: avatarUrl,
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        role: role,
        workspaceCreatedAt: workspaceCreatedAt,
        memberCount: memberCount,
        activePageCount: activePageCount,
        pageName: pageName,
      );

  AccountDetails withWorkspaceName(String value) => AccountDetails(
        email: email,
        providers: providers,
        createdAt: createdAt,
        lastSignInAt: lastSignInAt,
        emailConfirmed: emailConfirmed,
        displayName: displayName,
        avatarUrl: avatarUrl,
        workspaceId: workspaceId,
        workspaceName: value,
        role: role,
        workspaceCreatedAt: workspaceCreatedAt,
        memberCount: memberCount,
        activePageCount: activePageCount,
        pageName: pageName,
      );
}

/// Longueurs maximales (alignées sur la base pour l'espace : 120).
const int kMaxDisplayName = 80;
const int kMaxWorkspaceName = 120;

/// Libellé du rôle dans l'espace de travail.
String accountRoleLabel(String role) {
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

/// Libellé d'une méthode de connexion Supabase.
String providerLabel(String provider) {
  switch (provider) {
    case 'email':
      return 'E-mail et mot de passe';
    case 'google':
      return 'Google';
    case 'facebook':
      return 'Facebook';
    case 'apple':
      return 'Apple';
    case 'github':
      return 'GitHub';
    default:
      if (provider.isEmpty) return provider;
      return provider[0].toUpperCase() + provider.substring(1);
  }
}

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// « 26 novembre 2026 ».
String formatFrenchDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// « 26 novembre 2026 à 10:53 ».
String formatFrenchDateTime(DateTime date) {
  final hours = date.hour.toString().padLeft(2, '0');
  final minutes = date.minute.toString().padLeft(2, '0');
  return '${formatFrenchDate(date)} à $hours:$minutes';
}

/// Initiales (deux lettres au plus) pour l'avatar : d'abord le nom, sinon
/// l'adresse e-mail.
String initialsOf(String? name, String? email) {
  final words = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isNotEmpty) {
    final letters = words.take(2).map((w) => w.substring(0, 1)).join();
    return letters.toUpperCase();
  }
  final mail = (email ?? '').trim();
  if (mail.isNotEmpty) return mail.substring(0, 1).toUpperCase();
  return '?';
}

/// Levée quand une modification est refusée (droits insuffisants, etc.).
class AccountUpdateException implements Exception {
  const AccountUpdateException(this.message);

  final String message;
}
