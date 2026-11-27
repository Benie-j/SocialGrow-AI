import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État des alertes instantanées sur ce téléphone.
enum PushStatus {
  /// Cette version n'a pas de configuration Firebase (ou autre plateforme).
  unavailable,

  /// L'autorisation n'a pas encore été demandée.
  notDetermined,

  /// Notifications refusées dans Android.
  denied,

  /// Autorisées : le téléphone est enregistré auprès du serveur.
  enabled,
}

/// Alertes instantanées (push) : permissions, enregistrement du téléphone
/// auprès du serveur et réception.
abstract class PushService {
  Future<PushStatus> status();

  /// Demande l'autorisation Android puis enregistre le téléphone.
  Future<PushStatus> enable();

  /// Au démarrage : si déjà autorisé, (ré)enregistre le téléphone en silence.
  Future<void> syncIfEnabled();

  /// Faut-il proposer d'activer les alertes (jamais demandé, pas repoussé) ?
  Future<bool> shouldPrompt();

  /// L'utilisateur repousse la proposition (elle revient dans 7 jours).
  Future<void> dismissPrompt();

  /// Retire ce téléphone du compte (avant la déconnexion).
  Future<void> unregister();

  /// Émet quand l'utilisateur ouvre une notification.
  Stream<void> get opens;

  /// Vrai (une seule fois) si l'appli a été lancée en touchant une
  /// notification alors qu'elle était fermée.
  bool takePendingOpen();
}

/// Implémentation Firebase Cloud Messaging.
///
/// Firebase est initialisé par code avec des valeurs fournies au build
/// (`--dart-define`), tirées du secret GitHub `GOOGLE_SERVICES_JSON` : aucun
/// fichier de configuration dans le dépôt. Sans ces valeurs, le service reste
/// « indisponible » et l'appli fonctionne normalement.
class FirebasePushService implements PushService {
  FirebasePushService(this._client);

  final SupabaseClient _client;

  /// Même identifiant que celui envoyé par la fonction serveur `send-push`.
  static const channelId = 'jun_alerts';
  static const _smallIcon = 'ic_stat_jun';
  static const _askedKey = 'push_permission_asked';
  static const _dismissedKey = 'push_prompt_dismissed_at';
  static const _promptDelay = Duration(days: 7);

  final StreamController<void> _opens = StreamController<void>.broadcast();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Future<bool>? _ready;
  bool _pendingOpen = false;

  @override
  Stream<void> get opens => _opens.stream;

  @override
  bool takePendingOpen() {
    final pending = _pendingOpen;
    _pendingOpen = false;
    return pending;
  }

  static FirebaseOptions? _optionsFromEnvironment() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        projectId.isEmpty ||
        senderId.isEmpty) {
      return null;
    }
    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }

  Future<bool> _ensureReady() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final options = _optionsFromEnvironment();
    if (options == null) return false;

    try {
      await Firebase.initializeApp(options: options);

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
        ),
        onDidReceiveNotificationResponse: (_) => _opens.add(null),
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              'Alertes JUN AI',
              description:
                  'Publications, brouillons IA et problèmes de connexion.',
              importance: Importance.high,
            ),
          );

      FirebaseMessaging.onMessage.listen(_showInForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((_) => _opens.add(null));
      // firebase_messaging 17 déprécie les jetons FCM au profit des
      // identifiants d'installation (register/onRegistered). `send-push`
      // envoie encore à un jeton FCM : on garde cette API, qui fonctionne,
      // jusqu'à la migration conjointe du serveur.
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingOpen = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// En premier plan, Android n'affiche pas seul les notifications Firebase.
  Future<void> _showInForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Alertes JUN AI',
          channelDescription:
              'Publications, brouillons IA et problèmes de connexion.',
          importance: Importance.high,
          priority: Priority.high,
          icon: _smallIcon,
          color: Color(0xFF0F6B45),
        ),
      ),
      payload: message.data['notification_id'] as String?,
    );
  }

  @override
  Future<PushStatus> status() async {
    if (!await _ensureReady()) return PushStatus.unavailable;

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return PushStatus.enabled;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
      case AuthorizationStatus.notDetermined:
        // Android ne distingue pas « jamais demandé » de « refusé » : on
        // retient nous-mêmes si la demande a déjà été faite.
        final prefs = await SharedPreferences.getInstance();
        return (prefs.getBool(_askedKey) ?? false)
            ? PushStatus.denied
            : PushStatus.notDetermined;
    }
  }

  @override
  Future<PushStatus> enable() async {
    if (!await _ensureReady()) return PushStatus.unavailable;

    final settings = await FirebaseMessaging.instance.requestPermission();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return PushStatus.denied;

    await _registerCurrentToken();
    return PushStatus.enabled;
  }

  @override
  Future<void> syncIfEnabled() async {
    try {
      if (await status() == PushStatus.enabled) {
        await _registerCurrentToken();
      }
    } catch (_) {
      // Au mieux : un échec réseau sera rattrapé au prochain démarrage.
    }
  }

  @override
  Future<bool> shouldPrompt() async {
    try {
      if (await status() != PushStatus.notDetermined) return false;
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_dismissedKey);
      if (millis == null) return true;
      final dismissed = DateTime.fromMillisecondsSinceEpoch(millis);
      return DateTime.now().difference(dismissed) >= _promptDelay;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dismissPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _registerCurrentToken() async {
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    if (_client.auth.currentSession == null) return;
    try {
      await _client.functions.invoke(
        'register-push-token',
        body: {'action': 'register', 'token': token},
      );
    } catch (_) {
      // Rejoué au prochain démarrage ou au prochain changement de jeton.
    }
  }

  @override
  Future<void> unregister() async {
    try {
      if (!await _ensureReady()) return;
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && _client.auth.currentSession != null) {
        await _client.functions.invoke(
          'register-push-token',
          body: {'action': 'unregister', 'token': token},
        );
      }
      // Un nouveau jeton sera créé pour le prochain compte de ce téléphone.
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // La déconnexion ne doit jamais être bloquée par les alertes.
    }
  }
}
