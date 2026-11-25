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
2. ~~Connexion OAuth Meta et sélection de Page Facebook.~~ Fait : voir « Connexion d'une Page Facebook ».
3. Génération de contenus avec Groq via une Edge Function.
4. Gestion des publications et du calendrier.
5. Statistiques et notifications.

## Réglages de publication (état)
- Écran : Paramètres > Paramètres de publication (`features/settings`), sections A à G.
- Données : `lib/data/publication_settings*.dart` lit et écrit uniquement `public.publication_settings` (upsert sur `workspace_id`).
- Multi-utilisateurs : les réglages appartiennent à un espace de travail. Seuls les rôles propriétaire, admin et éditeur peuvent écrire (RLS) ; un lecteur voit les réglages en lecture seule. Si un utilisateur appartient à plusieurs espaces, le plus ancien est utilisé (sélecteur d’espace à prévoir).
- `frequency_per_week` n’est pas un réglage : elle est recalculée (publications par jour × jours) à l’enregistrement.
- Jours de publication : 1 = lundi … 7 = dimanche.
- Sections de Paramètres pas encore implémentées (affichées « Bientôt ») : Compte et profil, Stratégie éditoriale (réglée dans Paramètres de publication), Groq, Notifications, Sécurité.


## Convention Supabase : droits explicites (depuis 20261125090317)

Le schéma `public` n'accorde plus aucun droit par défaut à `anon` ni `authenticated`.
Toute migration qui crée une table ou une fonction doit, dans le même fichier :
1. activer la RLS et créer ses politiques ;
2. accorder explicitement les opérations nécessaires (`grant select, insert, ... to authenticated`) ;
3. pour une fonction, accorder `execute` uniquement aux rôles concernés.

`TRUNCATE`, `REFERENCES` et `TRIGGER` ne sont jamais accordés aux rôles clients.
La création d'espaces de travail est limitée à 5 par utilisateur (constante `max_workspaces`
dans `public.create_workspace`).


## Connexion d'une Page Facebook

### Règle de sécurité
Le client (l'application) **ne peut que lire** `public.facebook_pages`. Il n'a ni `INSERT`, ni `UPDATE`,
ni `DELETE` (migration `20261125102617_facebook_pages_backend_only_writes`). Toute connexion ou
déconnexion passe par les Edge Functions ci-dessous, qui appellent deux fonctions SQL
(`connect_facebook_page`, `disconnect_facebook_page`) exécutables **uniquement par `service_role`**.
Elles revérifient le rôle (propriétaire, admin ou éditeur) et gardent une seule Page active par espace.

### Edge Functions (`supabase/functions/`)
| Fonction | Entrée | Sortie |
| --- | --- | --- |
| `facebook-list-pages` | `{ workspace_id, provider_token }` | `{ pages: [{ id, name, category, picture_url }] }` |
| `facebook-connect-page` | `{ action: "connect", workspace_id, provider_token, meta_page_id }` | `{ page, long_lived }` |
| `facebook-connect-page` | `{ action: "disconnect", workspace_id }` | `{ disconnected }` |

- `provider_token` est le jeton Facebook de la session Supabase (`session.providerToken`). Il n'est jamais stocké.
- La Page choisie est **revérifiée auprès de Facebook** (`/me/accounts`) : une Page qui n'appartient pas à l'utilisateur est refusée.
- Le jeton de Page est chiffré en AES-256-GCM puis stocké dans `private.facebook_credentials` ; il n'est jamais renvoyé à l'application.
- Clé de chiffrement : secret `TOKEN_ENCRYPTION_KEY` s'il existe, sinon dérivée de la clé service_role.
  Changer l'une ou l'autre rend les jetons déjà stockés illisibles (il faudra reconnecter la Page).
- Version Graph API : `v25.0` par défaut, secret `GRAPH_API_VERSION` pour la changer.
- **Connexion durable** : définir les secrets Supabase `FACEBOOK_APP_ID` et `FACEBOOK_APP_SECRET`. Les fonctions
  échangent alors le jeton utilisateur contre un jeton longue durée, et les jetons de Page n'expirent pas.
  Sans ces secrets, la connexion fonctionne mais expire au bout de quelques heures (`long_lived: false`, signalé dans l'application).
- Codes d'erreur : `unauthenticated`, `forbidden`, `facebook_token_missing`, `facebook_token_invalid`,
  `facebook_permission_missing`, `page_not_found`, `facebook_unavailable`, `invalid_body`.
  Les quatre premiers côté Facebook demandent à l'utilisateur de se reconnecter.

### Application
- Écran : Réglages > Connexion Facebook (`features/settings/presentation/facebook_connection_page.dart`).
- Données : `lib/data/facebook_connection.dart` (appelle les Edge Functions) et `facebook_oauth.dart` (connexion/reconnexion Facebook).
- `WorkspaceOverview.connectedPage` alimente le tableau de bord (étape du parcours, tuile « Page Facebook »).
- La session Facebook (`providerToken`) n'est pas renouvelable : si elle manque ou a expiré, l'écran propose « Se reconnecter avec Facebook ».

### Tests
- Edge Functions : `deno test -A supabase/functions/tests` (Facebook et Supabase simulés, sans réseau). Exécutés par la CI.
- Application : `app/test/facebook_connection_test.dart`.
