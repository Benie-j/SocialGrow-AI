# JUN AI

> Anciennement « SocialGrow AI ». Le dépôt, le package Dart (`socialgrow_ai`), l'identifiant Android et le schéma de retour `socialgrowai://` gardent l'ancien nom : ce sont des identifiants techniques, liés aux réglages Supabase et Meta.

Application Android (Flutter) qui aide à gérer et à faire croître une Page Facebook : stratégie éditoriale, génération de publications avec Groq, calendrier, publication via Meta Graph API et analyse des performances réelles.

## Stack
- **Flutter** : interface Android (`app/`)
- **Supabase** : authentification, base de données (RLS), Edge Functions, Cron (`supabase/`)
- **Groq** : génération de contenu (appelé uniquement depuis le backend)
- **Meta Graph API** : publication et statistiques de la Page Facebook
- **GitHub Actions** : compilation de l'APK (`.github/workflows/`)

## Principe d'architecture
Tous les réglages de publication sont centralisés dans **Paramètres > Paramètres de publication** et stockés dans Supabase. Générateur IA, calendrier et moteur de publication lisent cette même source de vérité.

## Sécurité
Ce dépôt est public. Aucune clé Groq, aucun secret Meta, aucun jeton Facebook ni clé Supabase `service_role` ne doit y figurer. Ces secrets vivent dans les secrets Supabase ou GitHub Actions.

## Compilation
L'APK est compilé par GitHub Actions (onglet *Actions* > dernier run > artefacts `jun-ai-arm64-v8a`, `jun-ai-armeabi-v7a` et `jun-ai-x86_64`). Aucun SDK n'est requis en local.

## État
Socle en cours : voir `docs/ARCHITECTURE.md`.
