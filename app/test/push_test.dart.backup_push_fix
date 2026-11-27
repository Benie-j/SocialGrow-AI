import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:socialgrow_ai/core/navigation/app_shell.dart';
import 'package:socialgrow_ai/core/push/push_service.dart';
import 'package:socialgrow_ai/data/notifications.dart';
import 'package:socialgrow_ai/data/notifications_repository.dart';
import 'package:socialgrow_ai/features/settings/presentation/notifications_page.dart';

class FakePushService implements PushService {
  FakePushService({
    this.current = PushStatus.notDetermined,
    this.prompt = false,
    this.pendingOpen = false,
    this.enableResult = PushStatus.enabled,
  });

  PushStatus current;
  bool prompt;
  bool pendingOpen;
  PushStatus enableResult;

  int enableCalls = 0;
  int dismissCalls = 0;
  int syncCalls = 0;
  final StreamController<void> _opens = StreamController<void>.broadcast();

  void emitOpen() => _opens.add(null);

  @override
  Stream<void> get opens => _opens.stream;

  @override
  Future<PushStatus> status() async => current;

  @override
  Future<PushStatus> enable() async {
    enableCalls++;
    current = enableResult;
    return enableResult;
  }

  @override
  Future<void> syncIfEnabled() async => syncCalls++;

  @override
  Future<bool> shouldPrompt() async => prompt;

  @override
  Future<void> dismissPrompt() async => dismissCalls++;

  @override
  Future<void> unregister() async {}

  @override
  bool takePendingOpen() {
    final value = pendingOpen;
    pendingOpen = false;
    return value;
  }
}

class _EmptyNotificationsRepository implements NotificationsRepository {
  @override
  Future<NotificationsOverview> load() async => const NotificationsOverview(
        workspaceId: 'ws-1',
        preferences: NotificationPreferences(),
        items: [],
      );

  @override
  Future<void> savePreferences(
    String workspaceId,
    NotificationPreferences preferences,
  ) async {}

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<void> markAllRead(String workspaceId) async {}
}

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpPage(WidgetTester tester, PushService? push) async {
  _bigScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: NotificationsPage(
        repository: _EmptyNotificationsRepository(),
        pushService: push,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpShell(WidgetTester tester, FakePushService push) async {
  _bigScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        onSignOut: () async {},
        pushService: push,
        notificationsRepository: _EmptyNotificationsRepository(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('carte « Alertes instantanées »', () {
    testWidgets('propose d’activer, puis confirme', (tester) async {
      final push = FakePushService();
      await _pumpPage(tester, push);

      expect(find.text('Alertes instantanées'), findsOneWidget);
      expect(find.text('Activer les alertes instantanées'), findsOneWidget);

      await tester.tap(find.text('Activer les alertes instantanées'));
      await tester.pump();
      await tester.pump();

      expect(push.enableCalls, 1);
      expect(find.text('Activées'), findsOneWidget);
      expect(find.text('Activer les alertes instantanées'), findsNothing);
    });

    testWidgets('refus Android : explique où réactiver', (tester) async {
      await _pumpPage(tester, FakePushService(current: PushStatus.denied));

      expect(find.textContaining('désactivées pour JUN AI'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('activées : conseils pour les téléphones restrictifs',
        (tester) async {
      await _pumpPage(tester, FakePushService(current: PushStatus.enabled));

      expect(find.text('Activées'), findsOneWidget);
      await tester.tap(find.text('Rien ne s’affiche ?'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Xiaomi, Tecno, Infinix'), findsOneWidget);
    });

    testWidgets('indisponible ou sans service : carte masquée',
        (tester) async {
      await _pumpPage(tester, FakePushService(current: PushStatus.unavailable));
      expect(find.text('Alertes instantanées'), findsNothing);

      await _pumpPage(tester, null);
      expect(find.text('Alertes instantanées'), findsNothing);
    });
  });

  group('AppShell', () {
    testWidgets('propose les alertes au démarrage et active sur « Activer »',
        (tester) async {
      final push = FakePushService(prompt: true);
      await _pumpShell(tester, push);

      expect(push.syncCalls, 1);
      expect(find.text('Reste informé instantanément'), findsOneWidget);

      await tester.tap(find.text('Activer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(push.enableCalls, 1);
      expect(push.dismissCalls, 0);
      expect(find.text('Reste informé instantanément'), findsNothing);
    });

    testWidgets('« Plus tard » repousse la proposition', (tester) async {
      final push = FakePushService(prompt: true);
      await _pumpShell(tester, push);

      await tester.tap(find.text('Plus tard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(push.dismissCalls, 1);
      expect(push.enableCalls, 0);
    });

    testWidgets('rien à proposer : pas de fenêtre', (tester) async {
      await _pumpShell(tester, FakePushService());

      expect(find.text('Reste informé instantanément'), findsNothing);
    });

    testWidgets('lancée par un tap sur une notification : ouvre l’écran',
        (tester) async {
      final push = FakePushService(prompt: true, pendingOpen: true);
      await _pumpShell(tester, push);

      expect(find.widgetWithText(AppBar, 'Notifications'), findsOneWidget);
      expect(find.text('Reste informé instantanément'), findsNothing);
    });

    testWidgets('un tap sur une notification pendant l’usage ouvre l’écran',
        (tester) async {
      final push = FakePushService();
      await _pumpShell(tester, push);
      expect(find.widgetWithText(AppBar, 'Notifications'), findsNothing);

      push.emitOpen();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.widgetWithText(AppBar, 'Notifications'), findsOneWidget);
    });
  });
}
