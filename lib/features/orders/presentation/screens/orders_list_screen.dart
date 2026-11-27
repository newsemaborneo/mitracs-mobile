import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../../core/widgets/app_state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';

class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  final ApiClient _api = ApiClient();
  final NumberFormat _currencyFmt = NumberFormat('#,###', 'id_ID');
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String _selectedFilter =
      'ALL'; // ALL, DITERIMA, DICUCI, DISETRIKA, SIAP_DIAMBIL, SELESAI, UNPAID
  String _searchQuery = '';
  List<Map<String, dynamic>> _orders = [];

  final List<Map<String, String>> _filters = const [
    {'key': 'ALL', 'label': 'Semua'},
    {'key': 'MENUNGGU_VALIDASI', 'label': 'Validasi WA'},
    {'key': 'DITERIMA', 'label': 'Antrian'},
    {'key': 'DICUCI', 'label': 'Dicuci'},
    {'key': 'DISETRIKA', 'label': 'Setrika'},
    {'key': 'SIAP_DIAMBIL', 'label': 'Siap'},
    {'key': 'DIAMBIL', 'label': 'Diambil'},
    {'key': 'UNPAID', 'label': 'Belum Lunas'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOrders());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.dio.get(
        '/businesses/${activeBiz.id}/laundry/orders',
        queryParameters: {
          if (activeBiz.outletId != null) 'outletId': activeBiz.outletId,
        },
      );
      if (res.data['success'] == true) {
        final raw = (res.data['data'] as List?) ?? [];
        final parsed = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final incomingCount = parsed.where((o) {
          final st = (o['status'] ?? '').toString().toUpperCase();
          return st == 'MENUNGGU_VALIDASI' || st == 'DITERIMA';
        }).length;
        ref.read(incomingOrdersCountProvider.notifier).setCount(incomingCount);
        setState(() {
          _orders = parsed;
        });
      }
    } on DioException catch (e) {
      debugPrint('[Orders] fetch error: ${e.response?.data}');
      setState(() {
        _error = e.response?.data?['message'] ?? 'Gagal memuat daftar pesanan';
      });
    } catch (e) {
      setState(() => _error = 'Terjadi kesalahan saat memuat pesanan');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateOrderStatus(String orderId, String nextStatus) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    try {
      final res = await _api.dio.patch(
        '/businesses/${activeBiz.id}/laundry/orders/$orderId/status',
        data: {'status': nextStatus},
      );
      if (res.data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status diperbarui ke ${_statusLabel(nextStatus)}'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.read(appRefreshProvider.notifier).trigger();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.data?['message'] ?? 'Gagal mengubah status',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _markOrderPaid(Map<String, dynamic> order) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    final total = double.tryParse(order['total']?.toString() ?? '0') ?? 0;
    try {
      final res = await _api.dio.post(
        '/businesses/${activeBiz.id}/laundry/orders/${order['id']}/pay',
        data: {'paidAmount': total, 'paymentMethod': 'CASH'},
      );
      if (res.data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pembayaran berhasil dilunasi!'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.read(appRefreshProvider.notifier).trigger();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.data?['message'] ?? 'Gagal melunasi pesanan',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  String _customerNameOf(Map<String, dynamic> o) {
    final cust = o['customer'];
    if (cust is Map && cust['name'] != null) return cust['name'].toString();
    return (o['customerName'] ?? 'Pelanggan').toString();
  }

  String _customerPhoneOf(Map<String, dynamic> o) {
    final cust = o['customer'];
    if (cust is Map && cust['phoneNumber'] != null)
      return cust['phoneNumber'].toString();
    return (o['customerPhone'] ?? '-').toString();
  }

  List<Map<String, dynamic>> get _filteredOrders {
    return _orders.where((o) {
      final status = (o['status'] ?? 'DITERIMA').toString().toUpperCase();
      final payStatus = (o['paymentStatus'] ?? 'UNPAID')
          .toString()
          .toUpperCase();

      if (_selectedFilter == 'UNPAID') {
        if (payStatus == 'PAID') return false;
      } else if (_selectedFilter != 'ALL') {
        if (status != _selectedFilter) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final orderNo = (o['orderNumber'] ?? '').toString().toLowerCase();
        final name = _customerNameOf(o).toLowerCase();
        final phone = _customerPhoneOf(o).toLowerCase();
        return orderNo.contains(q) || name.contains(q) || phone.contains(q);
      }
      return true;
    }).toList();
  }

  int _countForFilter(String key) {
    if (key == 'ALL') return _orders.length;
    if (key == 'UNPAID') {
      return _orders
          .where((o) => (o['paymentStatus'] ?? '').toString() != 'PAID')
          .length;
    }
    return _orders
        .where(
          (o) => (o['status'] ?? 'DITERIMA').toString().toUpperCase() == key,
        )
        .length;
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'MENUNGGU_VALIDASI':
        return 'Perlu Validasi';
      case 'DITERIMA':
        return 'Antrian';
      case 'DICUCI':
        return 'Dicuci';
      case 'DISETRIKA':
        return 'Setrika';
      case 'SIAP_DIAMBIL':
        return 'Siap Diambil';
      case 'DIAMBIL':
        return 'Sudah Diambil';
      case 'SELESAI':
        return 'Selesai';
      default:
        return status;
    }
  }

  String? _nextStatus(String current) {
    switch (current.toUpperCase()) {
      case 'DITERIMA':
        return 'DICUCI';
      case 'DICUCI':
        return 'DISETRIKA';
      case 'DISETRIKA':
        return 'SIAP_DIAMBIL';
      case 'SIAP_DIAMBIL':
        return 'DIAMBIL';
      default:
        return null;
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'MENUNGGU_VALIDASI':
        return AppColors.warning;
      case 'DITERIMA':
        return const Color(0xFF64748B);
      case 'DICUCI':
        return const Color(0xFF0284C7);
      case 'DISETRIKA':
        return const Color(0xFFD97706);
      case 'SIAP_DIAMBIL':
        return const Color(0xFF16A34A);
      case 'DIAMBIL':
      case 'SELESAI':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appRefreshProvider, (_, __) => _fetchOrders());
    ref.listen<String>(ordersFilterProvider, (_, next) {
      if (mounted && _selectedFilter != next) {
        setState(() => _selectedFilter = next);
      }
    });
    ref.listen(authProvider, (prev, next) {
      if (prev?.activeBusiness?.id != next.activeBusiness?.id &&
          next.activeBusiness != null) {
        _fetchOrders();
      }
    });

    final list = _filteredOrders;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Daftar & Tracking Pesanan',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: _isLoading ? null : _fetchOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'Cari nomor nota, nama, atau nomor WA...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceSubtle,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Filter Chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final key = f['key']!;
                  final isSel = _selectedFilter == key;
                  final count = _countForFilter(key);
                  final isUrgentBadge =
                      (key == 'MENUNGGU_VALIDASI' || key == 'DITERIMA') &&
                      count > 0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(f['label']!),
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.white.withOpacity(0.24)
                                    : (isUrgentBadge
                                          ? AppColors.danger
                                          : AppColors.primary.withOpacity(0.14)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSel
                                      ? Colors.white
                                      : (isUrgentBadge
                                            ? Colors.white
                                            : AppColors.primaryDark),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      selected: isSel,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSel ? Colors.white : AppColors.textSecondary,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceSubtle,
                      onSelected: (_) =>
                          setState(() => _selectedFilter = key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading && _orders.isEmpty
                ? const LoadingListPlaceholder()
                : _error != null && _orders.isEmpty
                ? ErrorStateWidget(message: _error!, onRetry: _fetchOrders)
                : list.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.receipt_long_outlined,
                    title: 'Belum Ada Pesanan',
                    subtitle: 'Pesanan dari kasir akan muncul di sini untuk dipantau prosesnya.',
                    actionLabel: 'Muat Ulang',
                    onAction: _fetchOrders,
                  )
                : RefreshIndicator(
                    onRefresh: _fetchOrders,
                    color: AppColors.primary,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildOrderCard(list[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'DITERIMA').toString();
    final payStatus = (order['paymentStatus'] ?? 'UNPAID')
        .toString()
        .toUpperCase();
    final isPaid = payStatus == 'PAID';
    final total = double.tryParse(order['total']?.toString() ?? '0') ?? 0;
    final next = _nextStatus(status);
    final statusColor = _statusColor(status);
    final custName = _customerNameOf(order);
    final custPhone = _customerPhoneOf(order);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order['orderNumber'] ?? '#NOTA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? AppColors.successLight
                          : AppColors.warningLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isPaid
                          ? 'Lunas'
                          : (payStatus == 'PARTIAL' ? 'DP' : 'Belum Lunas'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isPaid
                            ? AppColors.success
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withOpacity(0.08),
                child: Text(
                  custName.isNotEmpty ? custName[0].toUpperCase() : 'P',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      custName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      custPhone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Rp ${_currencyFmt.format(total)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (order['notes'] != null &&
              order['notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              order['notes'].toString(),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
          if (!isPaid || next != null) ...[
            const Divider(height: 20, color: AppColors.surfaceSubtle),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!isPaid)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                        side: const BorderSide(color: AppColors.success),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _markOrderPaid(order),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text(
                        'Lunasi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (status.toUpperCase() == 'MENUNGGU_VALIDASI')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _openValidateOrderModal(order),
                      icon: const Icon(Icons.scale_rounded, size: 16),
                      label: const Text(
                        'Validasi Berat & Terima',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else if (next != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () =>
                          _updateOrderStatus(order['id'].toString(), next),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(
                        'Ke ${_statusLabel(next)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openValidateOrderModal(Map<String, dynamic> order) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    List<Map<String, dynamic>> services = [];
    try {
      final res = await _api.dio.get('/businesses/${activeBiz.id}/laundry/services');
      if (res.data['success'] == true && res.data['data'] is List) {
        services = (res.data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;
    if (services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daftar layanan belum tersedia untuk validasi.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final existingItems = (order['items'] as List? ?? []);
    final firstItem = existingItems.isNotEmpty
        ? Map<String, dynamic>.from(existingItems.first as Map)
        : null;
    String selectedServiceId =
        firstItem?['serviceId']?.toString() ?? services.first['id'].toString();
    if (!services.any((s) => s['id'].toString() == selectedServiceId)) {
      selectedServiceId = services.first['id'].toString();
    }
    final qtyCtrl = TextEditingController(
      text: (firstItem?['qty'] ?? 1).toString(),
    );
    final notesCtrl = TextEditingController(
      text: order['notes']?.toString() ?? '',
    );
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final svc = services.firstWhere(
            (s) => s['id'].toString() == selectedServiceId,
            orElse: () => services.first,
          );
          final unitPrice =
              double.tryParse(svc['price']?.toString() ?? '0') ?? 0;
          final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
          final estTotal = unitPrice * qty;

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
                    Text(
                      'Validasi Cucian Masuk (${order['orderNumber'] ?? '-'})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pelanggan: ${order['customer']?['name'] ?? 'Pelanggan'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedServiceId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Jenis Layanan Tervalidasi',
                      ),
                      items: services.map((s) {
                        final p =
                            double.tryParse(s['price']?.toString() ?? '0') ?? 0;
                        return DropdownMenuItem<String>(
                          value: s['id'].toString(),
                          child: Text(
                            '${s['name']} (Rp ${_currencyFmt.format(p)} / ${s['unit']})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedServiceId = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Berat / Jumlah Aktual (${svc['unit']})',
                        prefixIcon: const Icon(Icons.scale_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Catatan Penerimaan (Opsional)',
                        prefixIcon: Icon(Icons.note_alt_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Tagihan Aktual',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          Text(
                            'Rp ${_currencyFmt.format(estTotal)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: isSubmitting || qty <= 0
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                final res = await _api.dio.post(
                                  '/businesses/${activeBiz.id}/laundry/orders/${order['id']}/validate',
                                  data: {
                                    'items': [
                                      {
                                        'serviceId': selectedServiceId,
                                        'qty': qty,
                                      },
                                    ],
                                    'notes': notesCtrl.text.trim(),
                                  },
                                );
                                if (!ctx.mounted) return;
                                if (res.data['success'] == true) {
                                  Navigator.pop(ctx);
                                  ref.read(appRefreshProvider.notifier).trigger();
                                  _fetchOrders();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Cucian divalidasi & WA Diterima + QR Code telah dikirim!',
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } on DioException catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e.response?.data?['message']
                                                ?.toString() ??
                                            'Gagal memvalidasi pesanan.',
                                      ),
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
                        isSubmitting
                            ? 'Memvalidasi...'
                            : 'Validasi & Kirim WA Diterima',
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
