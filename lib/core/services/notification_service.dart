import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../features/chat/presentation/screens/whatsapp_conversation_screen.dart';
import '../network/api_client.dart';
import 'background_notification_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  io.Socket? _socket;
  String? _currentOutletId;
  int _unreadCount = 0;
  bool _initialized = false;

  static const String _channelId = 'mitracs_wa_channel';
  static const String _channelName = 'Chat & Pesanan WhatsApp';

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) {
        clearBadge();
        final raw = details.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final map = jsonDecode(raw);
          if (map is Map && map['conversationId'] != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => WhatsAppConversationScreen(
                  conversation: {
                    'id': map['conversationId'],
                    'customerName': map['customerName'] ?? 'Pelanggan WA',
                  },
                  onTakeover: (_) {},
                  onReturnToAi: (_) {},
                ),
              ),
            );
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Notifikasi pesan masuk & pesanan WhatsApp pelanggan',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }
  }

  void connectOutlet(String outletId) {
    if (kIsWeb || outletId.isEmpty || _currentOutletId == outletId) return;
    _currentOutletId = outletId;
    BackgroundNotificationService.configureAndStart(outletId);

    _socket?.dispose();
    final socketUrl = ApiClient.baseUrl.replaceFirst('/api/v1', '');
    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket?.onConnect((_) {
      _socket?.emit('join_outlet', outletId);
    });

    _socket?.on('whatsapp:message', (data) {
      if (data is Map) {
        final msg = data['message'];
        if (msg is Map &&
            (msg['senderType'] ?? '').toString().toUpperCase() == 'CUSTOMER') {
          final sender = (msg['senderName'] ?? 'Pelanggan WA').toString();
          final body = (msg['body'] ?? 'Pesan baru masuk').toString();
          final convoId = data['conversationId']?.toString();
          showCustomNotification(
            title: sender,
            body: body,
            payload: convoId != null
                ? jsonEncode({
                    'conversationId': convoId,
                    'customerName': sender,
                  })
                : null,
          );
        }
      }
    });
  }

  Future<void> showCustomNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    _unreadCount += 1;

    try {
      await AppBadgePlus.updateBadge(_unreadCount);
    } catch (_) {}

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      number: 1,
    );
    const iosDetails = DarwinNotificationDetails(badgeNumber: 1);

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  Future<void> clearBadge() async {
    _unreadCount = 0;
    if (kIsWeb) return;
    try {
      await AppBadgePlus.updateBadge(0);
    } catch (_) {}
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _currentOutletId = null;
  }
}
