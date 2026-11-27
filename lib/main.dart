import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'core/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multibiz_mobile/core/theme/app_theme.dart';
import 'package:multibiz_mobile/features/auth/providers/auth_provider.dart';
import 'package:multibiz_mobile/features/auth/presentation/screens/sso_login_screen.dart';
import 'package:multibiz_mobile/features/dashboard/presentation/screens/home_nav_screen.dart';
import 'package:multibiz_mobile/features/subscription/presentation/screens/owner_onboarding_plan_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      OneSignal.initialize('881501b2-80ad-48b5-af4d-ddff0249199f');
      OneSignal.Notifications.requestPermission(true);
    } catch (e) {
      debugPrint('[OneSignal] Init skipped: $e');
    }
  }
  runApp(
    const ProviderScope(
      child: MultiBizApp(),
    ),
  );
}

class MultiBizApp extends ConsumerWidget {
  const MultiBizApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'mitraCS.ai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: authState.isAuthenticated
          ? (authState.needsOnboarding && authState.user != null
              ? OwnerOnboardingPlanScreen(
                  ownerEmail: authState.user!.email,
                  defaultBusinessName: authState.activeBusiness?.name,
                )
              : const HomeNavScreen())
          : const SsoLoginScreen(),
    );
  }
}
