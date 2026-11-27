import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../auth/data/auth_model.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../catalog/providers/catalog_provider.dart';

class DashboardOverviewScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToPos;
  final VoidCallback? onNavigateToOrders;
  final VoidCallback? onNavigateToInbox;
  final VoidCallback? onNavigateToWhatsapp;

  const DashboardOverviewScreen({
    super.key,
    this.onNavigateToPos,
    this.onNavigateToOrders,
    this.onNavigateToInbox,
    this.onNavigateToWhatsapp,
  });

  @override
  ConsumerState<DashboardOverviewScreen> createState() => _DashboardOverviewScreenState();
}

class _DashboardOverviewScreenState extends ConsumerState<DashboardOverviewScreen> {
  final ApiClient _api = ApiClient();
  final NumberFormat _currencyFmt = NumberFormat('#,###', 'id_ID');

  String _selectedPeriod = 'Hari Ini';
  bool _isLoading = false;
  String? _errorMessage;

  double _totalRevenue = 0;
  int _totalOrders = 0;
  double _totalWeightKg = 0;
  int _queueCount = 0;
  int _washingCount = 0;
  int _ironingCount = 0;
  int _readyCount = 0;
  int _unpaidCount = 0;
  String _growthText = '0%';
  int _aiTokenBalance = 0;
  String _planName = 'Trial';
  String _subStatus = 'TRIAL';
  int _daysRemaining = 0;
  String? _subExpiresAt;
  List<Map<String, dynamic>> _weeklyTrend = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDashboardStats();
    });
  }

  String get _periodQuery {
    switch (_selectedPeriod) {
      case 'Minggu Ini':
        return 'week';
      case 'Bulan Ini':
        return 'month';
      default:
        return 'today';
    }
  }

  Future<void> _fetchDashboardStats() async {
    final authState = ref.read(authProvider);
    if (authState.isLoading) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) await _fetchDashboardStats();
      return;
    }

    final activeBiz = authState.activeBusiness;
    if (activeBiz == null) {
      debugPrint('[Dashboard] activeBusiness null');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _api.dio.get(
        '/businesses/${activeBiz.id}/dashboard/stats',
        queryParameters: {'period': _periodQuery},
      );

      if (res.data['success'] == true) {
        final data = res.data['data'] ?? {};
        setState(() {
          _totalRevenue = (data['totalRevenue'] ?? 0).toDouble();
          _totalOrders = (data['totalOrders'] ?? 0) as int;
          _totalWeightKg = (data['totalWeightKg'] ?? 0).toDouble();
          _queueCount = (data['queueCount'] ?? 0) as int;
          _washingCount = (data['washingCount'] ?? 0) as int;
          _ironingCount = (data['ironingCount'] ?? 0) as int;
          _readyCount = (data['readyCount'] ?? 0) as int;
          _unpaidCount = (data['unpaidCount'] ?? 0) as int;
          _growthText = data['growthPercent']?.toString() ?? '0%';
          _aiTokenBalance = int.tryParse(data['aiTokenBalance']?.toString() ?? '0') ?? 0;
          if (data['subscription'] is Map) {
            final sub = Map<String, dynamic>.from(data['subscription'] as Map);
            _planName = sub['planName']?.toString() ?? 'Trial';
            _subStatus = sub['status']?.toString() ?? 'TRIAL';
            _daysRemaining = int.tryParse(sub['daysRemaining']?.toString() ?? '0') ?? 0;
            _subExpiresAt = sub['currentPeriodEnd']?.toString();
          }
          _weeklyTrend = data['weeklyTrend'] is List
              ? (data['weeklyTrend'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : [];
        });
      }
    } on DioException catch (e) {
      debugPrint('[Dashboard] DioException: ${e.response?.statusCode}');
      if (mounted) {
        setState(() {
          _errorMessage = e.response?.data?['message'] ?? 'Gagal memuat data statistik dari server';
        });
      }
    } catch (e) {
      debugPrint('[Dashboard] Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openBusinessSwitcher(BuildContext context, List<BusinessModel> businesses, String? activeId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih Cabang / Usaha Aktif',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 12),
              ...businesses.map((b) {
                final isSelected = b.id == activeId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? AppColors.primary : AppColors.surfaceSubtle,
                    child: Icon(Icons.storefront_rounded, color: isSelected ? Colors.white : AppColors.textSecondary, size: 20),
                  ),
                  title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text('${b.outletName ?? 'Cabang Utama'} (${b.role})', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    ref.read(authProvider.notifier).switchBusiness(b);
                    Navigator.pop(ctx);
                    _fetchDashboardStats();
                    ref.read(catalogProvider.notifier).fetchCatalog();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appRefreshProvider, (_, __) => _fetchDashboardStats());
    ref.listen(authProvider, (prev, next) {
      if (prev?.activeBusiness?.id != next.activeBusiness?.id && next.activeBusiness != null) {
        _fetchDashboardStats();
      }
    });

    final authState = ref.watch(authProvider);
    final activeBiz = authState.activeBusiness;
    final businesses = authState.businesses;
    final avgPerOrder = _totalOrders > 0 ? (_totalRevenue / _totalOrders) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.analytics_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: businesses.length > 1
                    ? () => _openBusinessSwitcher(context, businesses, activeBiz?.id)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Beranda & Statistika',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${activeBiz?.name ?? 'Usaha Anda'} (${activeBiz?.outletName ?? 'Utama'})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                          ),
                        ),
                        if (businesses.length > 1) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: AppColors.primary),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_rounded, size: 13, color: Color(0xFF16A34A)),
                SizedBox(width: 4),
                Text(
                  'Outlet Buka',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: _fetchDashboardStats,
                        child: const Text('Coba Lagi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),

              // Filter chip periode
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['Hari Ini', 'Minggu Ini', 'Bulan Ini'].map((p) {
                    final isSel = _selectedPeriod == p;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p),
                        selected: isSel,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : const Color(0xFF475569),
                        ),
                        selectedColor: AppColors.primary,
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSel ? AppColors.primary : const Color(0xFFE2E8F0)),
                        ),
                        onSelected: (_) {
                          setState(() => _selectedPeriod = p);
                          _fetchDashboardStats();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Card Omzet Utama (Executive Navy dengan aksen geometris halus)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -36,
                        top: -36,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 24,
                        bottom: -54,
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentTeal.withOpacity(0.12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TOTAL PENDAPATAN',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFBAE6FD),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.trending_up_rounded, color: Color(0xFF4ADE80), size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        _growthText,
                                        style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Rp ${_currencyFmt.format(_totalRevenue)}',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(color: Colors.white12, height: 1),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _buildHeaderMiniMetric('Transaksi', '$_totalOrders Nota', Icons.receipt_long_rounded)),
                                const SizedBox(width: 6),
                                Expanded(child: _buildHeaderMiniMetric('Cucian', '${_totalWeightKg.toStringAsFixed(1)} kg', Icons.scale_rounded)),
                                const SizedBox(width: 6),
                                Expanded(child: _buildHeaderMiniMetric('Rata-rata', 'Rp ${_currencyFmt.format(avgPerOrder)}', Icons.pie_chart_rounded)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Kartu Waktu Berlangganan & Sisa Token AI SaaS
              _buildSubscriptionAndTokenCard(),
              const SizedBox(height: 16),

              // Ringkasan Operasional Ringkas (2 Kartu Utama)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Sedang Diproses',
                      count: '${_queueCount + _washingCount + _ironingCount} Nota',
                      subtitle: '$_queueCount antrian, ${_washingCount + _ironingCount} proses',
                      icon: Icons.local_laundry_service_rounded,
                      color: AppColors.primary,
                      bgColor: AppColors.primaryLight,
                      onTap: () {
                        ref.read(ordersFilterProvider.notifier).setFilter('DITERIMA');
                        widget.onNavigateToOrders?.call();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      title: 'Siap Diambil',
                      count: '$_readyCount Nota',
                      subtitle: _unpaidCount > 0
                          ? '$_unpaidCount belum lunas'
                          : 'Semua lunas',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                      bgColor: AppColors.successLight,
                      onTap: () {
                        ref.read(ordersFilterProvider.notifier).setFilter('SIAP_DIAMBIL');
                        widget.onNavigateToOrders?.call();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tren Transaksi Mingguan
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
                    const Text(
                      'Jumlah Nota per Hari (7 Hari Terakhir)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 16),
                    _buildWeeklyBarChart(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
    );
  }

  Widget _buildHeaderMiniMetric(String label, String val, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF93C5FD)),
        const SizedBox(width: 5),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Color(0xFFBFDBFE), fontWeight: FontWeight.w500)),
              Text(val, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFCBD5E1)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                count,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyBarChart() {
    if (_weeklyTrend.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Belum ada data tren transaksi 7 hari terakhir.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
      );
    }

    final maxCount = _weeklyTrend
        .map((d) => (int.tryParse(d['count']?.toString() ?? '0') ?? 0))
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: _weeklyTrend.map((d) {
        final count = int.tryParse(d['count']?.toString() ?? '0') ?? 0;
        final val = (count / maxCount).clamp(0.08, 1.0);
        final isMax = count == maxCount && count > 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isMax ? AppColors.primary : const Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            Container(
              width: 22,
              height: 80 * val,
              decoration: BoxDecoration(
                color: isMax ? AppColors.primary : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (d['day'] ?? '-').toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isMax ? FontWeight.w800 : FontWeight.w600,
                color: isMax ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSubscriptionAndTokenCard() {
    String formattedExpiry = '-';
    if (_subExpiresAt != null && _subExpiresAt!.isNotEmpty) {
      final parsed = DateTime.tryParse(_subExpiresAt!);
      if (parsed != null) {
        formattedExpiry = DateFormat('dd MMM yyyy').format(parsed.toLocal());
      }
    }
    final isExpiringSoon = _daysRemaining <= 7;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isExpiringSoon
                    ? AppColors.warning.withOpacity(0.5)
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isExpiringSoon
                            ? AppColors.warningLight
                            : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        size: 16,
                        color: isExpiringSoon
                            ? AppColors.warning
                            : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _planName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$_daysRemaining Hari Tersisa',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: isExpiringSoon
                        ? AppColors.warning
                        : AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aktif s/d $formattedExpiry ($_subStatus)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Token AI SaaS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _currencyFmt.format(_aiTokenBalance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sisa kuota balasan AI WA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
