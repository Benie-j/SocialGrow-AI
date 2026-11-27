# Alertes instantanées (push) — JUN AI

Les notifications arrivent **instantanément, écran verrouillé ou application fermée**, grâce à Firebase Cloud Messaging (FCM) en priorité haute.

## Chaîne complète

1. Une ligne est insérée dans `public.notifications` (publication réussie ou échouée, brouillon IA prêt, problème Facebook).
2. Le déclencheur SQL `notifications_push` appelle l'Edge Function `send-push` (pg_net).
3. `send-push` réclame la notification de façon atomique (jamais envoyée deux fois), respecte les préférences de l'utilisateur, retrouve ses téléphones dans `public.device_tokens` et envoie via l'API FCM HTTP v1 (priorité `HIGH`, canal `jun_alerts`). Les jetons périmés sont supprimés.
4. Android affiche la notification, même si l'application est fermée. Un tap ouvre l'écran Notifications.

Côté application : `FirebasePushService` (`app/lib/core/push/push_service.dart`) crée le canal `jun_alerts`, demande l'autorisation Android 13+, enregistre le jeton via l'Edge Function `register-push-token` et le retire à la déconnexion. Les préférences (4 types d'alertes) se règlent dans Réglages › Notifications.

## Ce que tu dois fournir (une seule fois, sans rien coller dans une conversation)

1. **Projet Firebase** (gratuit) : console.firebase.google.com › Ajouter un projet › ajouter une application **Android** avec le nom de package **exact** de l'application (`com.socialgrow.socialgrow_ai` aujourd'hui — voir la remarque ci-dessous) › télécharger `google-services.json`.
2. **Secret GitHub `GOOGLE_SERVICES_JSON`** : dépôt › Settings › Secrets and variables › Actions › New repository secret › coller **tout le contenu** de `google-services.json`. Le build vérifie le nom de package et active alors les alertes dans l'APK. Sans ce secret, l'APK se construit normalement, sans alertes instantanées.
3. **Secret Supabase `FIREBASE_SERVICE_ACCOUNT`** : console Firebase › Paramètres du projet › Comptes de service › *Générer une nouvelle clé privée* › Supabase › Edge Functions › Secrets › coller le contenu JSON du fichier téléchargé. Tant qu'il est absent, `send-push` répond `not_configured` et n'envoie rien.

Ne jamais committer `google-services.json` ni la clé de compte de service (déjà exclus par `.gitignore`).

## Choix du nom de package (à décider avant la publication)

Le nom de package Android est **définitif une fois l'application publiée sur Google Play**, et le projet Firebase y est lié. Si tu veux un identifiant à la marque (par exemple `com.junai.app`), change-le **avant** de créer l'application Android dans Firebase.

## Limites à connaître

- Une application **arrêtée de force** par l'utilisateur ne reçoit plus rien tant qu'elle n'est pas rouverte (règle d'Android).
- Certains constructeurs (Xiaomi, Tecno, Infinix, Oppo, Huawei…) tuent les applications en arrière-plan : autoriser le démarrage automatique et mettre la batterie sur « Sans restriction » pour JUN AI. L'écran Notifications l'explique à l'utilisateur.
- L'autorisation de notifications Android 13+ est demandée à l'utilisateur : refusée, elle se réactive dans les réglages du téléphone.
