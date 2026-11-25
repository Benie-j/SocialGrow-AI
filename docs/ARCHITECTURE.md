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
- Sections de Paramètres pas encore implémentées (affichées « Bientôt ») : Compte et profil, Notifications, Sécurité.


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

**Principe : le client ne fait que lire `facebook_pages`.** Il n'a aucun droit
`INSERT`/`UPDATE`/`DELETE` dessus (migrations `20261125094759` et
`20261125102617`). Sinon un éditeur aurait pu y insérer une fausse Page.

- `supabase/functions/facebook-list-pages` : liste les Pages que l'utilisateur
  gère chez Meta (`GET /me/accounts`). Ne renvoie jamais de jeton de Page.
- `supabase/functions/facebook-connect-page` : retrouve la Page chez Meta parmi
  celles que l'utilisateur gère, fait chiffrer son jeton par la base
  (`public.encrypt_facebook_token`, clé dans le Vault Supabase, jamais dans Git)
  puis appelle `public.connect_facebook_page`.
- `supabase/functions/facebook-disconnect-page` : appelle
  `public.disconnect_facebook_page` (Page désactivée, jeton supprimé).
- Les fonctions SQL ne sont appelables que par `service_role` et revérifient le
  rôle (`owner`, `admin` ou `editor`). **Une seule Page est active par espace** :
  connecter une autre Page remplace la précédente.
- Flutter : `data/facebook_connection.dart` (dépôt), écran
  `features/settings/presentation/facebook_connection_page.dart`
  (Réglages → Connexion Facebook). L'accueil affiche le nom de la Page connectée.

Le jeton Facebook de l'utilisateur (`session.providerToken`) n'existe qu'après
une connexion Facebook : l'écran propose « Autoriser l'accès à mes Pages » s'il
est absent. Il est envoyé aux Edge Functions, jamais stocké.

### Déploiement des fonctions

`supabase functions deploy facebook-list-pages facebook-connect-page facebook-disconnect-page`.
`SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont fournis
automatiquement par Supabase. Facultatif : secret `META_GRAPH_VERSION` (défaut `v23.0`).

## Stratégie éditoriale (état)
- Écran : Paramètres > Stratégie éditoriale (`features/settings/presentation/editorial_strategy_page.dart`).
- Données : table `public.editorial_strategy` (une ligne par espace, migration `20261125122820`), lue et écrite par `lib/data/editorial_strategy_repository.dart`. Mêmes règles RLS que `publication_settings` (lecture : membres ; écriture : owner, admin, editor).
- Contenu : description de l'activité, phrase de marque, 5 piliers pondérés de 0 à 10 (éduquer, inspirer, vendre, engager, coulisses), voix de marque (formel et chaleureux, de 0 à 10), formules à bannir (20 max).
- L'objectif, le public cible et la fréquence restent dans `publication_settings` (sections A et F) : l'écran les lit sans les dupliquer.
- « Semaine type » : `planWeek` répartit les publications de la semaine (publications par jour × jours choisis) entre les piliers (quotas au plus fort reste, ordre alterné). Calcul pur, testé dans `test/editorial_strategy_test.dart`.
- « Boussole » : 4 étapes réellement vérifiées (activité, phrase de marque, public cible, 3 piliers actifs).
- À brancher : le générateur Groq doit relire cette ligne (piliers, voix, formules à bannir) pour construire ses consignes.

## Paramètres Groq (état)
- Écran : Paramètres > Paramètres Groq (`features/settings/presentation/groq_settings_page.dart`).
- Données : table `public.groq_settings` (une ligne par espace, migration `20261125124158`), mêmes règles RLS que `publication_settings`. Champs : modèle final, modèle de brouillon, créativité (0 à 15, température = valeur / 10), longueur maximale en tokens, garde-fou mensuel de générations.
- Les identifiants de modèles sont libres (validés par motif) : la liste de Groq évolue, les exemples proposés ne sont que des suggestions.
- « Consommation du mois » : calculée depuis `ai_generation_logs` (générations, tokens, taux de réussite, durée moyenne). Le compteur reste à zéro tant qu'aucune Edge Function de génération n'écrit dans cette table.
- La clé Groq n'est jamais saisie ni stockée dans l'app ou dans la base : secret Supabase lu uniquement par l'Edge Function de génération.
- À brancher : l'Edge Function de génération doit lire `groq_settings` (modèles, température, tokens), refuser au-delà du garde-fou mensuel et journaliser chaque appel dans `ai_generation_logs`.
