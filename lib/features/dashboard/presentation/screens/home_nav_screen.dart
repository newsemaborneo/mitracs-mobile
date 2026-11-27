import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../auth/data/auth_model.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../pos_laundry/presentation/screens/laundry_pos_screen.dart';
import '../../../orders/presentation/screens/orders_list_screen.dart';
import '../../../customers/presentation/screens/customers_management_screen.dart';
import '../../../whatsapp/presentation/screens/whatsapp_qr_screen.dart';
import '../../../whatsapp/presentation/screens/wa_templates_screen.dart';
import '../../../staff/presentation/screens/staff_management_screen.dart';
import '../../../chat/presentation/screens/multi_cs_inbox_screen.dart';
import '../../../subscription/presentation/screens/owner_onboarding_plan_screen.dart';
import '../../../catalog/presentation/screens/catalog_management_screen.dart';
import 'dashboard_overview_screen.dart';

class HomeNavScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const HomeNavScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<HomeNavScreen> createState() => _HomeNavScreenState();
}

class _HomeNavScreenState extends ConsumerState<HomeNavScreen> {
  late int _currentIndex;
  Timer? _badgeTimer;
  bool _notifiedLowSub = false;
  bool _notifiedLowToken = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.init();
      _fetchIncomingOrdersCount();
      _checkSubscriptionAndTokenAlerts();
    });
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchIncomingOrdersCount(),
    );
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSubscriptionAndTokenAlerts() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;
    try {
      final res = await ApiClient().dio.get(
        '/businesses/${activeBiz.id}/dashboard/stats',
      );
      if (res.data['success'] == true && res.data['data'] is Map) {
        final data = res.data['data'] as Map;
        final sub = data['subscription'];
        final daysRemaining = sub is Map ? (sub['daysRemaining'] as num?)?.toInt() : null;
        final tokenBalance = (data['aiTokenBalance'] as num?)?.toInt();

        if (!_notifiedLowSub && daysRemaining != null && daysRemaining <= 3) {
          _notifiedLowSub = true;
          await NotificationService.instance.showCustomNotification(
            title: 'Langganan Hampir Habis',
            body: daysRemaining <= 0
                ? 'Masa aktif paket Anda sudah habis. Segera perpanjang layanan.'
                : 'Masa aktif paket Anda tersisa $daysRemaining hari. Segera perpanjang.',
          );
        }
        if (!_notifiedLowToken && tokenBalance != null && tokenBalance <= 10000) {
          _notifiedLowToken = true;
          await NotificationService.instance.showCustomNotification(
            title: 'Token AI Hampir Habis',
            body: 'Sisa Token AI Anda tinggal $tokenBalance token. Segera beli token tambahan.',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchIncomingOrdersCount() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;
    if (activeBiz.outletId != null) {
      NotificationService.instance.connectOutlet(activeBiz.outletId!);
    }
    try {
      final res = await ApiClient().dio.get(
        '/businesses/${activeBiz.id}/laundry/orders',
        queryParameters: {
          if (activeBiz.outletId != null) 'outletId': activeBiz.outletId,
        },
      );
      if (res.data['success'] == true && res.data['data'] is List && mounted) {
        final list = res.data['data'] as List;
        final incoming = list.where((o) {
          final st = (o['status'] ?? '').toString().toUpperCase();
          return st == 'MENUNGGU_VALIDASI' || st == 'DITERIMA';
        }).length;
        ref.read(incomingOrdersCountProvider.notifier).setCount(incoming);
      }
    } catch (_) {}
  }

  void _switchTab(int index, List<int> refreshIndices) {
    setState(() => _currentIndex = index);
    if (refreshIndices.contains(index)) {
      ref.read(appRefreshProvider.notifier).trigger();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appRefreshProvider, (_, __) => _fetchIncomingOrdersCount());
    ref.listen(authProvider, (prev, next) {
      if (prev?.activeBusiness?.id != next.activeBusiness?.id &&
          next.activeBusiness != null) {
        _fetchIncomingOrdersCount();
      }
    });
    final incomingOrdersCount = ref.watch(incomingOrdersCountProvider);
    final activeBiz = ref.watch(authProvider).activeBusiness;
    final role = (activeBiz?.role ?? 'OWNER').toUpperCase();
    final isCashier = role == 'CASHIER';
    final isCsOperator = role == 'CS_OPERATOR';

    if (isCashier) {
      // Role CASHIER: Fokus Kasir -> Pesanan -> Pelanggan -> Opsi
      final screens = [
        LaundryPosScreen(
          onTransactionSuccess: () => _switchTab(1, [1]),
          onViewOrders: () {
            ref.read(ordersFilterProvider.notifier).setFilter('ALL');
            _switchTab(1, [1]);
          },
        ),
        const OrdersListScreen(),
        const CustomersManagementScreen(),
        const _SettingsTabScreen(),
      ];
      final safeIndex = _currentIndex.clamp(0, screens.length - 1);

      return Scaffold(
        backgroundColor: AppColors.background,
        body: TweenAnimationBuilder<double>(
        key: ValueKey('tab_anim_$safeIndex'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: 0.35 + (0.65 * value),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        ),
        child: IndexedStack(index: safeIndex, children: screens),
      ),
        bottomNavigationBar: _buildDockBar(
          children: [
            _buildNavItem(
              index: 0,
              currentIndex: safeIndex,
              icon: Icons.point_of_sale_outlined,
              activeIcon: Icons.point_of_sale_rounded,
              label: 'Kasir',
              onTap: () => _switchTab(0, [1]),
            ),
            _buildNavItem(
              index: 1,
              currentIndex: safeIndex,
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'Pesanan',
              badgeCount: incomingOrdersCount,
              onTap: () => _switchTab(1, [1]),
            ),
            _buildNavItem(
              index: 2,
              currentIndex: safeIndex,
              icon: Icons.contacts_outlined,
              activeIcon: Icons.contacts_rounded,
              label: 'Pelanggan',
              onTap: () => _switchTab(2, [1]),
            ),
            _buildNavItem(
              index: 3,
              currentIndex: safeIndex,
              icon: Icons.tune_outlined,
              activeIcon: Icons.tune_rounded,
              label: 'Opsi',
              onTap: () => _switchTab(3, [1]),
            ),
          ],
        ),
      );
    }

    if (isCsOperator) {
      // Role CS_OPERATOR: Fokus Inbox WA -> Pesanan -> Pelanggan -> Opsi
      final screens = [
        const MultiCsInboxScreen(),
        const OrdersListScreen(),
        const CustomersManagementScreen(),
        const _SettingsTabScreen(),
      ];
      final safeIndex = _currentIndex.clamp(0, screens.length - 1);

      return Scaffold(
        backgroundColor: AppColors.background,
        body: TweenAnimationBuilder<double>(
        key: ValueKey('tab_anim_$safeIndex'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: 0.35 + (0.65 * value),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        ),
        child: IndexedStack(index: safeIndex, children: screens),
      ),
        bottomNavigationBar: _buildDockBar(
          children: [
            _buildNavItem(
              index: 0,
              currentIndex: safeIndex,
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: 'Inbox',
              onTap: () => _switchTab(0, [0, 1]),
            ),
            _buildNavItem(
              index: 1,
              currentIndex: safeIndex,
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'Pesanan',
              badgeCount: incomingOrdersCount,
              onTap: () => _switchTab(1, [0, 1]),
            ),
            _buildNavItem(
              index: 2,
              currentIndex: safeIndex,
              icon: Icons.contacts_outlined,
              activeIcon: Icons.contacts_rounded,
              label: 'Pelanggan',
              onTap: () => _switchTab(2, [0, 1]),
            ),
            _buildNavItem(
              index: 3,
              currentIndex: safeIndex,
              icon: Icons.tune_outlined,
              activeIcon: Icons.tune_rounded,
              label: 'Opsi',
              onTap: () => _switchTab(3, [0, 1]),
            ),
          ],
        ),
      );
    }

    // Role OWNER / MANAGER: Akses Penuh (Beranda, Pesanan, [Kasir], Inbox, Opsi)
    final screens = [
      DashboardOverviewScreen(
        onNavigateToPos: () => _switchTab(2, [0, 1, 3]),
        onNavigateToOrders: () => _switchTab(1, [0, 1, 3]),
        onNavigateToInbox: () => _switchTab(3, [0, 1, 3]),
        onNavigateToWhatsapp: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WhatsAppQrScreen()),
        ),
      ),
      const OrdersListScreen(),
      LaundryPosScreen(
        onTransactionSuccess: () => _switchTab(0, [0, 1, 3]),
        onViewOrders: () {
          ref.read(ordersFilterProvider.notifier).setFilter('ALL');
          _switchTab(1, [0, 1, 3]);
        },
      ),
      const MultiCsInboxScreen(),
      const _SettingsTabScreen(),
    ];
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: TweenAnimationBuilder<double>(
        key: ValueKey('tab_anim_$safeIndex'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: 0.35 + (0.65 * value),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        ),
        child: IndexedStack(index: safeIndex, children: screens),
      ),
      bottomNavigationBar: _buildDockBar(
        children: [
          _buildNavItem(
            index: 0,
            currentIndex: safeIndex,
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Beranda',
            onTap: () => _switchTab(0, [0, 1, 3]),
          ),
          _buildNavItem(
            index: 1,
            currentIndex: safeIndex,
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
            label: 'Pesanan',
            badgeCount: incomingOrdersCount,
            onTap: () => _switchTab(1, [0, 1, 3]),
          ),
          _buildCenterPosButton(
            isSelected: safeIndex == 2,
            onTap: () => _switchTab(2, [0, 1, 3]),
          ),
          _buildNavItem(
            index: 3,
            currentIndex: safeIndex,
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
            label: 'Inbox',
            onTap: () => _switchTab(3, [0, 1, 3]),
          ),
          _buildNavItem(
            index: 4,
            currentIndex: safeIndex,
            icon: Icons.tune_outlined,
            activeIcon: Icons.tune_rounded,
            label: 'Opsi',
            onTap: () => _switchTab(4, [0, 1, 3]),
          ),
        ],
      ),
    );
  }

  Widget _buildDockBar({required List<Widget> children}) {
    return Container(
      clipBehavior: Clip.none,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 14,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    final isSelected = currentIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: badgeCount > 0,
                  backgroundColor: AppColors.danger,
                  textColor: Colors.white,
                  label: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Icon(
                    isSelected ? activeIcon : icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPosButton({
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 62,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                top: -10,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryDark : AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                bottom: 5,
                child: Text(
                  'Kasir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? AppColors.primary : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTabScreen extends ConsumerWidget {
  const _SettingsTabScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final activeBiz = authState.activeBusiness;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Pengaturan Bisnis & Akun',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // User profile card (Tap untuk CRUD Profil)
              InkWell(
                onTap: () => _openProfileCrudModal(context, ref),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        backgroundImage:
                            (user?.avatarUrl != null &&
                                user!.avatarUrl!.isNotEmpty)
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child:
                            (user?.avatarUrl != null &&
                                user!.avatarUrl!.isNotEmpty)
                            ? null
                            : Text(
                                user?.fullName.isNotEmpty == true
                                    ? user!.fullName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                  fontSize: 18,
                                ),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Pemilik Laundry',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          activeBiz?.role ?? 'Owner',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Business Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Informasi Usaha & Toko',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (activeBiz != null)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.edit_rounded, size: 14),
                            label: const Text(
                              'Ubah Data',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () => _openBusinessCrudModal(context, ref, activeBiz),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildInfoTile(
                      icon: Icons.storefront_rounded,
                      title: activeBiz?.name ?? '-',
                      subtitle: 'Kategori: ${activeBiz?.category ?? 'LAUNDRY'}',
                    ),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    _buildInfoTile(
                      icon: Icons.location_on_outlined,
                      title: activeBiz?.outletName ?? 'Outlet Utama',
                      subtitle: activeBiz?.address != null && activeBiz!.address!.isNotEmpty
                          ? activeBiz.address!
                          : 'Alamat belum diatur',
                    ),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    _buildInfoTile(
                      icon: Icons.access_time_rounded,
                      title: 'Jam Operasional Toko',
                      subtitle: activeBiz?.operationalHours ?? 'Setiap Hari: 08:00 - 21:00',
                    ),
                    if (activeBiz?.phoneNumber != null && activeBiz!.phoneNumber!.isNotEmpty) ...[
                      const Divider(height: 20, color: Color(0xFFF1F5F9)),
                      _buildInfoTile(
                        icon: Icons.phone_outlined,
                        title: activeBiz.phoneNumber!,
                        subtitle: 'Nomor WhatsApp / Kontak Toko',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Informasi Paket Langganan & Perpanjangan
              const _SubscriptionPlanOptionCard(),
              const SizedBox(height: 16),

              // ★ BARU: Menu Manajemen (hanya untuk Owner)
              if (activeBiz?.role == 'OWNER' || activeBiz?.role == null) ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(
                          'Manajemen Usaha',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      _buildMenuTile(
                        context: context,
                        icon: Icons.category_rounded,
                        iconColor: const Color(0xFF7C3AED),
                        bgColor: const Color(0xFFEDE9FE),
                        title: 'Katalog Layanan & Produk',
                        subtitle: 'Tambah/edit kategori, layanan, dan harga',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CatalogManagementScreen(),
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        indent: 56,
                        color: Color(0xFFF1F5F9),
                      ),
                      _buildMenuTile(
                        context: context,
                        icon: Icons.contacts_rounded,
                        iconColor: const Color(0xFF0EA5E9),
                        bgColor: const Color(0xFFE0F2FE),
                        title: 'Daftar Pelanggan',
                        subtitle: 'Kelola data pelanggan & sinkron ke Inbox WA',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CustomersManagementScreen(),
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        indent: 56,
                        color: Color(0xFFF1F5F9),
                      ),
                      _buildMenuTile(
                        context: context,
                        icon: Icons.qr_code_2_rounded,
                        iconColor: const Color(0xFF008069),
                        bgColor: const Color(0xFFD1FAE5),
                        title: 'Koneksi WhatsApp Outlet',
                        subtitle: 'Scan QR & status bot WhatsApp outlet',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WhatsAppQrScreen(),
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        indent: 56,
                        color: Color(0xFFF1F5F9),
                      ),
                      _buildMenuTile(
                        context: context,
                        icon: Icons.workspace_premium_rounded,
                        iconColor: const Color(0xFFD97706),
                        bgColor: const Color(0xFFFEF3C7),
                        title: 'Paket & Berlangganan',
                        subtitle: 'Pilih paket, atur outlet, & pembayaran',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OwnerOnboardingPlanScreen(
                              ownerEmail: user?.email ?? '',
                              defaultBusinessName: activeBiz?.name,
                              isFromSettings: true,
                            ),
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        indent: 56,
                        color: Color(0xFFF1F5F9),
                      ),
                      _buildMenuTile(
                        context: context,
                        icon: Icons.people_alt_rounded,
                        iconColor: const Color(0xFF0284C7),
                        bgColor: const Color(0xFFE0F2FE),
                        title: 'Kelola Staf & Kasir',
                        subtitle: 'Tambah akun kasir, atur hak akses',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StaffManagementScreen(),
                          ),
                        ),
                      ),
                      const Divider(
                        height: 1,
                        indent: 56,
                        color: Color(0xFFF1F5F9),
                      ),
                      _buildMenuTile(
                        context: context,
                        icon: Icons.message_rounded,
                        iconColor: const Color(0xFF16A34A),
                        bgColor: const Color(0xFFDCFCE7),
                        title: 'Template Pesan WhatsApp',
                        subtitle: 'Edit pesan notif otomatis ke pelanggan',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WaTemplatesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Portal Super Admin
              if (user?.isPlatformSuperAdmin == true ||
                  (user?.email.contains('admin') ?? false)) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.admin_panel_settings_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Super Admin',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Kelola provider AI, engine, dan paket langganan mitra.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(
                          Icons.dashboard_customize_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'Buka Dashboard Super Admin',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Panel Superadmin tersedia di Web Console.',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Logout Button
              OutlinedButton.icon(
                icon: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
                label: const Text(
                  'Keluar dari Akun',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  backgroundColor: const Color(0xFFFEF2F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBusinessCrudModal(
    BuildContext context,
    WidgetRef ref,
    BusinessModel currentBiz,
  ) async {
    final nameCtrl = TextEditingController(text: currentBiz.name);
    final outletNameCtrl = TextEditingController(text: currentBiz.outletName ?? '');
    final phoneCtrl = TextEditingController(text: currentBiz.phoneNumber ?? '');
    final addressCtrl = TextEditingController(text: currentBiz.address ?? '');
    final hoursCtrl = TextEditingController(text: currentBiz.operationalHours ?? 'Setiap Hari: 08:00 - 21:00');
    String selectedCategory = currentBiz.category;

    bool isSaving = false;
    String? modalError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Kelola Informasi Usaha & Toko',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Atur nama bisnis, outlet, nomor kontak, dan jam buka operasional.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (modalError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Text(
                          modalError!,
                          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Usaha / Brand',
                        prefixIcon: Icon(Icons.storefront_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: outletNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Outlet / Cabang',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Jam Operasional Toko',
                        hintText: 'Contoh: Setiap Hari: 08:00 - 21:00',
                        prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Nomor WhatsApp Toko',
                        hintText: '081234567890',
                        prefixIcon: Icon(Icons.phone_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Alamat Toko / Outlet',
                        hintText: 'Jl. Contoh No. 123, Kota...',
                        prefixIcon: Icon(Icons.map_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final outletName = outletNameCtrl.text.trim();
                              final hours = hoursCtrl.text.trim();
                              final phone = phoneCtrl.text.trim();
                              final address = addressCtrl.text.trim();

                              if (name.isEmpty) {
                                setModalState(() => modalError = 'Nama usaha wajib diisi.');
                                return;
                              }

                              setModalState(() {
                                isSaving = true;
                                modalError = null;
                              });

                              try {
                                final res = await ApiClient().dio.post(
                                  '/businesses/${currentBiz.id}',
                                  data: {
                                    'name': name,
                                    'outletName': outletName,
                                    'operationalHours': hours,
                                    'phoneNumber': phone,
                                    'address': address,
                                  },
                                );

                                if (res.data['success'] == true && ctx.mounted) {
                                  Navigator.pop(ctx);
                                  if (res.data['data'] != null) {
                                    ref.read(authProvider.notifier).updateActiveBusiness(
                                      BusinessModel.fromJson({
                                        'role': currentBiz.role,
                                        ...res.data['data'],
                                      }),
                                    );
                                  }
                                  await ref.read(authProvider.notifier).refreshProfile();
                                  ref.read(appRefreshProvider.notifier).trigger();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Informasi usaha & jam operasional berhasil diperbarui!'),
                                        backgroundColor: AppColors.success,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                setModalState(() {
                                  modalError = 'Gagal menyimpan data: $e';
                                });
                              } finally {
                                setModalState(() => isSaving = false);
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Simpan Perubahan',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showServerUrlDialog(BuildContext context) async {
    final api = ApiClient();
    final saved = await api.storage.read(key: 'custom_base_url');
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: saved ?? ApiClient.defaultBaseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'URL Server Backend',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'http://10.0.2.2:3001/api/v1',
            helperText: 'Emulator Android: 10.0.2.2 | Device fisik: IP LAN',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await api.storage.delete(key: 'custom_base_url');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Reset Default'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) {
                await api.storage.write(key: 'custom_base_url', value: url);
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('URL Server disimpan!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfileCrudModal(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(authProvider.notifier).refreshProfile();
    if (!context.mounted) return;
    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;

    final nameCtrl = TextEditingController(text: currentUser.fullName);
    final emailCtrl = TextEditingController(text: currentUser.email);
    final avatarCtrl = TextEditingController(text: currentUser.avatarUrl ?? '');
    bool isSaving = false;
    bool isDeleting = false;
    String? modalError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final previewUrl = avatarCtrl.text.trim();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primaryLight,
                          backgroundImage: previewUrl.isNotEmpty
                              ? NetworkImage(previewUrl)
                              : null,
                          child: previewUrl.isEmpty
                              ? Text(
                                  nameCtrl.text.trim().isNotEmpty
                                      ? nameCtrl.text.trim()[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                    fontSize: 18,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kelola Profil Pengguna',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Lihat, perbarui, atau hapus data akun Anda',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Muat Ulang Data',
                          onPressed: isSaving || isDeleting
                              ? null
                              : () async {
                                  await ref
                                      .read(authProvider.notifier)
                                      .refreshProfile();
                                  final latest = ref.read(authProvider).user;
                                  if (latest != null) {
                                    setModalState(() {
                                      nameCtrl.text = latest.fullName;
                                      emailCtrl.text = latest.email;
                                      avatarCtrl.text = latest.avatarUrl ?? '';
                                    });
                                  }
                                },
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      onChanged: (_) => setModalState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nama Lengkap',
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Alamat Email',
                        prefixIcon: Icon(Icons.email_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: avatarCtrl,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'URL Foto Profil (Opsional)',
                        prefixIcon: const Icon(Icons.image_outlined, size: 18),
                        suffixIcon: avatarCtrl.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Hapus Foto',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () =>
                                    setModalState(() => avatarCtrl.clear()),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (modalError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.dangerLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.danger.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          modalError!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: isSaving || isDeleting
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().length < 2) {
                                setModalState(() {
                                  modalError = 'Nama lengkap minimal 2 karakter.';
                                });
                                return;
                              }
                              setModalState(() {
                                isSaving = true;
                                modalError = null;
                              });
                              final err = await ref
                                  .read(authProvider.notifier)
                                  .updateProfile(
                                    fullName: nameCtrl.text,
                                    email: emailCtrl.text,
                                    avatarUrl: avatarCtrl.text,
                                  );
                              if (!ctx.mounted) return;
                              setModalState(() => isSaving = false);
                              if (err == null) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Profil pengguna berhasil diperbarui!',
                                    ),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              } else {
                                setModalState(() => modalError = err);
                              }
                            },
                      icon: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        isSaving ? 'Menyimpan...' : 'Simpan Perubahan',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        backgroundColor: const Color(0xFFFEF2F2),
                      ),
                      onPressed: isSaving || isDeleting
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  title: const Text('Hapus Akun Profil?'),
                                  content: const Text(
                                    'Tindakan ini permanen dan akan mengeluarkan sesi Anda.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dCtx, false),
                                      child: const Text('Batal'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.danger,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(dCtx, true),
                                      child: const Text('Ya, Hapus'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !ctx.mounted) return;
                              setModalState(() => isDeleting = true);
                              final err = await ref
                                  .read(authProvider.notifier)
                                  .deleteProfile();
                              if (!ctx.mounted) return;
                              setModalState(() => isDeleting = false);
                              if (err == null) {
                                Navigator.pop(ctx);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(err),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                            },
                      icon: isDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.danger,
                              ),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(
                        isDeleting ? 'Menghapus...' : 'Hapus Akun Profil',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubscriptionPlanOptionCard extends ConsumerStatefulWidget {
  const _SubscriptionPlanOptionCard();

  @override
  ConsumerState<_SubscriptionPlanOptionCard> createState() =>
      _SubscriptionPlanOptionCardState();
}

class _SubscriptionPlanOptionCardState
    extends ConsumerState<_SubscriptionPlanOptionCard> {
  bool _loading = true;
  String _planName = 'Belum Berlangganan';
  String _status = 'TRIAL';
  String _billingCycle = 'TRIAL';
  int _daysRemaining = 0;
  int _aiTokenBalance = 0;
  String _expiresText = '-';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;
    if (activeBiz.outletId != null) {
      NotificationService.instance.connectOutlet(activeBiz.outletId!);
    }
    setState(() => _loading = true);
    try {
      final res = await ApiClient().dio.get(
        '/businesses/${activeBiz.id}/dashboard/stats',
        queryParameters: {'period': 'today'},
      );
      if (res.data['success'] == true && mounted) {
        final data = res.data['data'] ?? {};
        final sub = data['subscription'] is Map
            ? Map<String, dynamic>.from(data['subscription'] as Map)
            : <String, dynamic>{};
        String expText = '-';
        final rawExp = sub['currentPeriodEnd']?.toString();
        if (rawExp != null && rawExp.isNotEmpty) {
          final dt = DateTime.tryParse(rawExp);
          if (dt != null) {
            final local = dt.toLocal();
            expText =
                '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
          }
        }
        setState(() {
          _planName = sub['planName']?.toString() ?? 'Belum Berlangganan';
          _status = sub['status']?.toString() ?? 'TRIAL';
          _billingCycle = sub['billingCycle']?.toString() ?? 'TRIAL';
          _daysRemaining =
              int.tryParse(sub['daysRemaining']?.toString() ?? '0') ?? 0;
          _aiTokenBalance =
              int.tryParse(data['aiTokenBalance']?.toString() ?? '0') ?? 0;
          _expiresText = expText;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appRefreshProvider, (_, __) => _load());
    final activeBiz = ref.watch(authProvider).activeBusiness;
    final canRenew = activeBiz?.role == 'OWNER' || activeBiz?.role == null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paket Langganan SaaS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _loading
                          ? 'Memuat info langganan...'
                          : '$_planName ($_billingCycle)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _daysRemaining <= 7
                      ? AppColors.warningLight
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _daysRemaining <= 7
                        ? AppColors.warning
                        : AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Masa Aktif',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_daysRemaining hari (s/d $_expiresText)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Sisa Token AI',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_aiTokenBalance Token',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canRenew) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OwnerOnboardingPlanScreen(
                            ownerEmail: ref.read(authProvider).user?.email ?? '',
                            defaultBusinessName: activeBiz?.name,
                            isFromSettings: true,
                          ),
                        ),
                      );
                      if (mounted) {
                        _load();
                        ref.read(appRefreshProvider.notifier).trigger();
                      }
                    },
                    icon: const Icon(Icons.autorenew_rounded, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Perpanjang', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                    ),
                    onPressed: () => _openTopupTokenModal(context),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Beli Token AI', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openTopupTokenModal(BuildContext context) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;
    if (activeBiz.outletId != null) {
      NotificationService.instance.connectOutlet(activeBiz.outletId!);
    }

    final packages = [
      {'tokens': 50000, 'label': '50.000 Token AI', 'price': 'Rp 25.000', 'amount': 25000},
      {'tokens': 150000, 'label': '150.000 Token AI', 'price': 'Rp 60.000', 'amount': 60000},
      {'tokens': 500000, 'label': '500.000 Token AI', 'price': 'Rp 175.000', 'amount': 175000},
    ];
    int selectedIdx = 1;
    String method = 'QRIS';
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Beli Token AI SaaS',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pilih paket kuota balasan otomatis AI WhatsApp',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                ...packages.asMap().entries.map((entry) {
                  final i = entry.key;
                  final pkg = entry.value;
                  final isSel = selectedIdx == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setModalState(() => selectedIdx = i),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.primaryLight.withOpacity(0.45)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSel ? AppColors.primary : AppColors.border,
                            width: isSel ? 1.8 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              pkg['label'].toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              pkg['price'].toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: ['QRIS', 'BCA', 'MANDIRI'].map((m) {
                    final isSel = method == m;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: m == 'MANDIRI' ? 0 : 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Center(
                            child: Text(
                              m,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          selected: isSel,
                          selectedColor: AppColors.primary,
                          onSelected: (_) => setModalState(() => method = m),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setModalState(() => isSubmitting = true);
                          try {
                            final chosen = packages[selectedIdx];
                            final res = await ApiClient().dio.post(
                              '/businesses/${activeBiz.id}/subscription/topup-tokens',
                              data: {
                                'tokens': chosen['tokens'],
                                'amount': chosen['amount'],
                                'paymentMethod': method,
                              },
                            );
                            if (!ctx.mounted) return;
                            if (res.data['success'] == true) {
                              Navigator.pop(ctx);
                              _load();
                              ref.read(appRefreshProvider.notifier).trigger();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    res.data['message']?.toString() ??
                                        'Token AI berhasil ditambahkan!',
                                  ),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (_) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Gagal memproses pembelian token AI.'),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          } finally {
                            if (ctx.mounted) {
                              setModalState(() => isSubmitting = false);
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    isSubmitting ? 'Memproses...' : 'Bayar & Tambah Token',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
