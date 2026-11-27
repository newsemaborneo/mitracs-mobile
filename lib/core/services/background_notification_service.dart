import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../network/api_client.dart';
import 'notification_service.dart';

class BackgroundNotificationService {
  static const String _outletKey = 'bg_notif_outlet_id';

  static Future<void> configureAndStart(String outletId) async {
    if (kIsWeb || outletId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outletKey, outletId);

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'mitracs_wa_channel',
        initialNotificationTitle: 'mitraCS.ai Aktif',
        initialNotificationContent: 'Memantau pesan WhatsApp pelanggan...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );
    await service.startService();
  }
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.instance.init();

  final prefs = await SharedPreferences.getInstance();
  final outletId = prefs.getString('bg_notif_outlet_id') ?? '';
  if (outletId.isEmpty) return;

  final socketUrl = ApiClient.baseUrl.replaceFirst('/api/v1', '');
  final socket = io.io(
    socketUrl,
    io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .enableReconnection()
        .build(),
  );

  socket.onConnect((_) {
    socket.emit('join_outlet', outletId);
  });

  socket.on('whatsapp:message', (data) {
    if (data is Map) {
      final msg = data['message'];
      if (msg is Map &&
          (msg['senderType'] ?? '').toString().toUpperCase() == 'CUSTOMER') {
        final sender = (msg['senderName'] ?? 'Pelanggan WA').toString();
        final body = (msg['body'] ?? 'Pesan baru masuk').toString();
        NotificationService.instance.showCustomNotification(
          title: sender,
          body: body,
        );
      }
    }
  });

  service.on('stopService').listen((_) {
    socket.dispose();
    service.stopSelf();
  });
}
