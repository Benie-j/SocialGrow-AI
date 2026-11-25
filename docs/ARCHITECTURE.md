# SocialGrow AI — Architecture

## Application Flutter

- `app/lib/main.dart` : initialisation et thèmes (sombre par défaut).
- `app/lib/core/auth/` : contrôle de session.
- `app/lib/core/navigation/` : navigation principale (barre flottante à 5 rubriques).
- `app/lib/core/theme/` : identité visuelle « Aurore » (`SgPalette`, `AppTheme`).
- `app/lib/core/widgets/` : composants partagés (fond animé, panneau verre, anneau de progression, pastille, bouton dégradé, apparition échelonnée, en-tête de page).
- `app/lib/features/auth/` : connexion Facebook (OAuth Supabase).
- `app/lib/features/dashboard/` : tableau de bord (parcours de lancement, Studio IA, espace de travail).
- `app/lib/features/preview/` : rubriques pas encore ouvertes (Studio, Agenda, Statistiques), avec aperçu de ce qui arrive.
- `app/lib/features/settings/` : paramètres et déconnexion.

### Conventions d'interface
- Les couleurs viennent de `SgPalette.of(context)` ; ne pas coder de couleurs en dur dans les écrans.
- Le dégradé signature est `SgPalette.brand` ; il est conçu pour du texte blanc.
- Le fond animé (`AuroraBackground`) respecte la préférence système « réduire les animations ».
- Le tableau de bord n'affiche aucune donnée fictive : seul l'état réel (compte connecté) est marqué comme terminé.

## Backend Supabase

Le projet Supabase est initialisé dans Flutter avec une clé publishable.

Le déclencheur `on_auth_user_created_socialgrow` crée automatiquement :
- le profil ;
- l'espace initial ;
- l'appartenance owner ;
- les paramètres de publication.

Ne pas appeler `create_workspace()` après l'inscription : cela créerait un espace supplémentaire.

Les données privées des identifiants Facebook doivent rester accessibles uniquement au backend.

## Prochaines intégrations

1. Lecture réelle du profil et de l'espace de travail.
2. Connexion OAuth Meta et sélection de Page Facebook.
3. Génération de contenus avec Groq via une Edge Function.
4. Gestion des publications et du calendrier.
5. Statistiques et notifications.

## Réglages de publication (état)
- Écran : Paramètres > Paramètres de publication (`features/settings`), sections A à G.
- Données : `lib/data/publication_settings*.dart` lit et écrit uniquement `public.publication_settings` (upsert sur `workspace_id`).
- Multi-utilisateurs : les réglages appartiennent à un espace de travail. Seuls les rôles propriétaire, admin et éditeur peuvent écrire (RLS) ; un lecteur voit les réglages en lecture seule. Si un utilisateur appartient à plusieurs espaces, le plus ancien est utilisé (sélecteur d’espace à prévoir).
- `frequency_per_week` n’est pas un réglage : elle est recalculée (publications par jour × jours) à l’enregistrement.
- Jours de publication : 1 = lundi … 7 = dimanche.
- Sections de Paramètres pas encore implémentées (affichées « Bientôt ») : Compte et profil, Connexion Facebook, Stratégie éditoriale (réglée dans Paramètres de publication), Groq, Notifications, Sécurité.

