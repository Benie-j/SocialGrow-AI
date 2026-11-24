# Architecture (plan)

- `app/` : projet Flutter (`lib/core`, `lib/features/*`, `lib/data`).
- `supabase/` : migrations SQL, Edge Functions, configuration.
- Source unique de vérité des réglages : table `publication_settings` (une ligne par utilisateur, RLS).
- Seul l'écran Paramètres écrit ces réglages ; les autres écrans et les Edge Functions les lisent.

## Étapes
1. Socle Flutter + CI APK (en cours)
2. Navigation et thèmes
3. Paramètres (8 sections, publication A à G)
4. Base Supabase (migrations + RLS)
5. Edge Functions (Groq, doublons, Meta, Cron)
6. Écrans Création IA, Calendrier, Tableau de bord, Statistiques

## Intégrations non encore configurées
Supabase, Groq et Meta ne sont pas encore connectés.
