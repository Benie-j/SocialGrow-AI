# SocialGrow AI — Architecture

## Application Flutter

- `app/lib/main.dart` : initialisation et thème.
- `app/lib/core/auth/` : contrôle de session.
- `app/lib/core/navigation/` : navigation principale.
- `app/lib/features/auth/` : inscription, connexion et récupération.
- `app/lib/features/dashboard/` : tableau de bord.
- `app/lib/features/placeholder/` : écrans en attente de développement.

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
