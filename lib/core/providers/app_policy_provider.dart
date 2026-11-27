import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';

class AppPolicyModel {
  final bool hasActiveSubscription;
  final String subscriptionStatus;
  final bool canCreateOrders;
  final bool canAccessWhatsApp;
  final bool canManageCatalog;
  final bool canViewReports;
  final String? lockReason;
  final String? lockMessage;
  final String? actionButtonText;
  final String? bannerTitle;
  final String bannerColor;

  AppPolicyModel({
    required this.hasActiveSubscription,
    required this.subscriptionStatus,
    required this.canCreateOrders,
    required this.canAccessWhatsApp,
    required this.canManageCatalog,
    required this.canViewReports,
    this.lockReason,
    this.lockMessage,
    this.actionButtonText,
    this.bannerTitle,
    this.bannerColor = 'EMERALD',
  });

  factory AppPolicyModel.fromJson(Map<String, dynamic> json) {
    return AppPolicyModel(
      hasActiveSubscription: json['hasActiveSubscription'] == true,
      subscriptionStatus: json['subscriptionStatus'] ?? 'PENDING',
      canCreateOrders: json['canCreateOrders'] == true,
      canAccessWhatsApp: json['canAccessWhatsApp'] == true,
      canManageCatalog: json['canManageCatalog'] == true,
      canViewReports: json['canViewReports'] == true,
      lockReason: json['lockReason'],
      lockMessage: json['lockMessage'],
      actionButtonText: json['actionButtonText'],
      bannerTitle: json['bannerTitle'],
      bannerColor: json['bannerColor'] ?? 'EMERALD',
    );
  }

  static AppPolicyModel defaultPermissive() {
    return AppPolicyModel(
      hasActiveSubscription: true,
      subscriptionStatus: 'ACTIVE',
      canCreateOrders: true,
      canAccessWhatsApp: true,
      canManageCatalog: true,
      canViewReports: true,
    );
  }
}

class AppPolicyNotifier extends Notifier<AsyncValue<AppPolicyModel>> {
  @override
  AsyncValue<AppPolicyModel> build() {
    fetchPolicy();
    return const AsyncValue.loading();
  }

  Future<void> fetchPolicy() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) {
      state = AsyncValue.data(AppPolicyModel.defaultPermissive());
      return;
    }

    try {
      final res = await ApiClient().dio.get('/businesses/${activeBiz.id}/app-policy');
      if (res.data['success'] == true && res.data['data'] != null) {
        state = AsyncValue.data(AppPolicyModel.fromJson(res.data['data']));
      } else {
        state = AsyncValue.data(AppPolicyModel.defaultPermissive());
      }
    } catch (e, stack) {
      debugPrint('[AppPolicyNotifier] Error fetch policy: $e');
      state = AsyncValue.error(e, stack);
    }
  }
}

final appPolicyProvider =
    NotifierProvider<AppPolicyNotifier, AsyncValue<AppPolicyModel>>(
  AppPolicyNotifier.new,
);
