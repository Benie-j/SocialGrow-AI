# SocialGrow AI — Architecture

## Application Flutter

- `app/lib/main.dart` : initialisation et thèmes (sombre par défaut).
- `app/lib/core/auth/` : contrôle de session.
- `app/lib/core/navigation/` : navigation principale (dock d'encre à 5 rubriques, pastille citron glissante).
- `app/lib/core/theme/` : identité visuelle « Sève » (`SgPalette`, `AppTheme`) : papier chaud et encre en clair, nuit de serre en sombre, vert citron comme signal.
- `app/lib/core/widgets/` : composants partagés (fond à trame de points, carte à trait d'encre, plante vivante `GrowthPlant`, pastille, bouton encre/citron, apparition échelonnée, en-tête de page).
- `app/lib/features/auth/` : connexion Facebook (OAuth Supabase).
- `app/lib/features/dashboard/` : tableau de bord (parcours de lancement, Studio IA, espace de travail).
- `app/lib/features/preview/` : rubriques pas encore ouvertes (Studio, Agenda, Statistiques), avec aperçu de ce qui arrive.
- `app/lib/features/settings/` : paramètres et déconnexion.

### Conventions d'interface
- Les couleurs viennent de `SgPalette.of(context)` ; ne pas coder de couleurs en dur dans les écrans.
- Le citron `SgPalette.lime` est toujours associé à de l'encre foncée (`SgPalette.inkDark`) pour le texte.
- `GrowthPlant` pousse avec l'avancement du parcours et respecte la préférence système « réduire les animations ».
- Le thème suit le réglage clair/sombre du téléphone.
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


## Convention Supabase : droits explicites (depuis 20261125090317)

Le schéma `public` n'accorde plus aucun droit par défaut à `anon` ni `authenticated`.
Toute migration qui crée une table ou une fonction doit, dans le même fichier :
1. activer la RLS et créer ses politiques ;
2. accorder explicitement les opérations nécessaires (`grant select, insert, ... to authenticated`) ;
3. pour une fonction, accorder `execute` uniquement aux rôles concernés.

`TRUNCATE`, `REFERENCES` et `TRIGGER` ne sont jamais accordés aux rôles clients.
La création d'espaces de travail est limitée à 5 par utilisateur (constante `max_workspaces`
dans `public.create_workspace`).

## Connexion Facebook (état)

**Principe : le client ne fait que lire `facebook_pages`.** Il n'a plus aucun
droit `INSERT`/`UPDATE`/`DELETE` dessus (migration `20261125120000`). Sinon un
éditeur aurait pu y insérer une fausse Page.

- `supabase/functions/facebook-list-pages` : liste les Pages que l'utilisateur
  gère chez Meta (`GET /me/accounts`). Ne renvoie jamais de jeton de Page.
- `supabase/functions/facebook-connect-page` : retrouve la Page chez Meta parmi
  celles que l'utilisateur gère, chiffre son jeton (AES-256-GCM) et appelle
  `public.connect_facebook_page` (réservée à `service_role`) qui écrit la Page
  et le jeton (`private.facebook_credentials`) en une seule transaction.
  Seuls les rôles `owner` et `admin` peuvent connecter une Page.
- `public.disconnect_facebook_page(uuid)` : `owner` et `admin`. Désactive la
  Page (historique conservé) et supprime son jeton.
- Flutter : `data/facebook_connection.dart` (dépôt), écran
  `features/settings/presentation/facebook_connection_page.dart`
  (Réglages → Connexion Facebook). L'accueil affiche le nom de la Page connectée.

Le jeton Facebook de l'utilisateur (`session.providerToken`) n'existe qu'après
une connexion Facebook : l'écran propose « Autoriser l'accès à mes Pages » s'il
est absent. Il est envoyé aux Edge Functions, jamais stocké.

### Déploiement (à faire une fois, hors Git)

1. Appliquer la migration `20261125120000_facebook_pages_server_only_writes.sql`.
2. Générer une clé de chiffrement : `openssl rand -base64 32`.
3. La déposer dans les secrets Supabase (jamais dans Git) :
   `supabase secrets set TOKEN_ENCRYPTION_KEY=<clé>`
   (facultatif : `META_GRAPH_VERSION`, par défaut `v23.0`).
4. Déployer : `supabase functions deploy facebook-list-pages facebook-connect-page`.
   `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont
   fournis automatiquement par Supabase aux fonctions.
