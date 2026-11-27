import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../catalog/data/catalog_model.dart';
import '../../../catalog/providers/catalog_provider.dart';
import '../../../catalog/presentation/screens/catalog_management_screen.dart';
import '../../../catalog/presentation/screens/category_form_screen.dart';
import '../../services/thermal_receipt_service.dart';
import 'pickup_scanner_screen.dart';

// Model CartItem tetap di sini untuk state lokal POS
class CartItem {
  final ServiceItem service;
  double qty;
  String notes;
  String parfum;

  CartItem({
    required this.service,
    required this.qty,
    this.notes = '',
    this.parfum = 'Akasia (Standar)',
  });

  double get subtotal => qty * service.price;
}

class LaundryPosScreen extends ConsumerStatefulWidget {
  /// Callback dipanggil setelah transaksi berhasil disimpan, untuk navigasi ke Beranda
  final VoidCallback? onTransactionSuccess;
  final VoidCallback? onViewOrders;

  const LaundryPosScreen({
    super.key,
    this.onTransactionSuccess,
    this.onViewOrders,
  });

  @override
  ConsumerState<LaundryPosScreen> createState() => _LaundryPosScreenState();
}

class _LaundryPosScreenState extends ConsumerState<LaundryPosScreen> {
  final ApiClient _api = ApiClient();
  final NumberFormat _currencyFmt = NumberFormat('#,###', 'id_ID');

  // Katalog dinamis: kategori & layanan yang dipilih
  String? _selectedCategoryId; // null = kategori pertama
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<CartItem> _cart = [];

  // Timbangan Numpad states (untuk layanan satuan kg)
  String _weightInput = '0';
  ServiceItem? _activeWeightItem; // layanan yang sedang diinput beratnya

  // Customer states
  String _customerName = '';
  String _customerPhone = '';
  String _customerAddress = '';
  double? _customerLat;
  double? _customerLng;

  // Mobile 3-step wizard state: 0 = Pelanggan, 1 = Layanan, 2 = Bayar
  int _mobileStep = 0;
  final TextEditingController _custSearchCtrl = TextEditingController();
  List<dynamic> _mobileCustomers = [];
  bool _isLoadingMobileCustomers = false;
  String? _mobileCustomersError;

  // Fulfillment & Payment states
  String _fulfillmentType = 'AMBIL_SENDIRI'; // AMBIL_SENDIRI, ANTAR_JEMPUT
  double _deliveryFee = 0;
  double _discount = 0;
  String _selectedParfum = 'Akasia Segar';
  String _paymentMethod = 'CASH'; // CASH, QRIS, TRANSFER
  String _paymentType = 'FULL'; // FULL, DP, LATER
  double _dpAmount = 0;
  bool _isPaidNow = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    _custSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Fetch katalog dinamis & daftar pelanggan dari backend saat POS dibuka
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(catalogProvider.notifier).fetchCatalog();
      _fetchMobileCustomers();
    });
  }

  Future<void> _fetchMobileCustomers([String q = '']) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;
    setState(() {
      _isLoadingMobileCustomers = true;
      _mobileCustomersError = null;
    });
    try {
      final res = await _api.dio.get(
        '/businesses/${activeBiz.id}/laundry/customers',
        queryParameters: {'q': q.trim()},
      );
      if (res.data['success'] == true && mounted) {
        setState(() {
          _mobileCustomers = (res.data['data'] as List?) ?? [];
          _isLoadingMobileCustomers = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMobileCustomers = false;
          _mobileCustomersError =
              e.response?.data?['message'] ?? 'Gagal memuat daftar pelanggan';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMobileCustomers = false;
          _mobileCustomersError = 'Terjadi kesalahan saat memuat pelanggan';
        });
      }
    }
  }

  IconData _iconForService(ServiceItem item) {
    final lower = item.name.toLowerCase();
    if (item.unit == 'kg' ||
        lower.contains('kiloan') ||
        lower.contains('cuci')) {
      return Icons.local_laundry_service_rounded;
    }
    if (lower.contains('setrika')) return Icons.iron_rounded;
    if (lower.contains('sepatu') || lower.contains('helm'))
      return Icons.sports_motorsports_rounded;
    if (lower.contains('tas')) return Icons.shopping_bag_rounded;
    if (lower.contains('bed') ||
        lower.contains('sprei') ||
        lower.contains('selimut'))
      return Icons.bed_rounded;
    if (lower.contains('karpet') || lower.contains('gorden'))
      return Icons.layers_rounded;
    return Icons.checkroom_rounded;
  }

  IconData _iconForCategory(ServiceCategory cat) {
    final lower = cat.name.toLowerCase();
    if (lower.contains('kiloan')) return Icons.scale_rounded;
    if (lower.contains('satuan') || lower.contains('pakaian'))
      return Icons.checkroom_rounded;
    if (lower.contains('bed') || lower.contains('linen'))
      return Icons.bed_rounded;
    if (lower.contains('sepatu') ||
        lower.contains('tas') ||
        lower.contains('helm'))
      return Icons.shopping_bag_rounded;
    if (lower.contains('karpet') || lower.contains('gorden'))
      return Icons.layers_rounded;
    return Icons.category_rounded;
  }

  double get _cartTotal {
    final itemsTotal = _cart.fold(0.0, (acc, item) => acc + item.subtotal);
    final delivery = _fulfillmentType == 'ANTAR_JEMPUT' ? _deliveryFee : 0.0;
    final total = itemsTotal + delivery - _discount;
    return total < 0 ? 0.0 : total;
  }

  double get _effectivePaidAmount {
    if (_paymentType == 'FULL') return _cartTotal;
    if (_paymentType == 'DP') return _dpAmount.clamp(0.0, _cartTotal);
    return 0.0;
  }

  void _onNumpadPress(String val) {
    HapticFeedback.lightImpact();
    setState(() {
      if (val == 'C') {
        _weightInput = '0';
      } else if (val == '⌫') {
        if (_weightInput.length > 1) {
          _weightInput = _weightInput.substring(0, _weightInput.length - 1);
        } else {
          _weightInput = '0';
        }
      } else if (val == '.') {
        if (!_weightInput.contains('.')) {
          _weightInput += '.';
        }
      } else {
        if (_weightInput == '0') {
          _weightInput = val;
        } else {
          _weightInput += val;
        }
      }
    });
  }

  void _addKiloanToCart() {
    final weight = double.tryParse(_weightInput) ?? 0.0;
    if (weight <= 0 || _activeWeightItem == null) return;

    HapticFeedback.mediumImpact();
    setState(() {
      final existingIndex = _cart.indexWhere(
        (c) => c.service.id == _activeWeightItem!.id,
      );
      if (existingIndex >= 0) {
        _cart[existingIndex].qty += weight;
      } else {
        _cart.add(
          CartItem(
            service: _activeWeightItem!,
            qty: weight,
            parfum: _selectedParfum,
          ),
        );
      }
      _weightInput = '0';
    });
  }

  void _addPieceItemToCart(ServiceItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      final existingIndex = _cart.indexWhere((c) => c.service.id == item.id);
      if (existingIndex >= 0) {
        _cart[existingIndex].qty += 1;
      } else {
        _cart.add(CartItem(service: item, qty: 1, parfum: _selectedParfum));
      }
    });
  }

  Future<void> _submitOrder({bool fromModal = true}) async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keranjang cucian masih kosong!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_customerName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Silakan isi atau pilih data pelanggan terlebih dahulu!',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      _openCustomerSelectorDialog();
      return;
    }

    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null || activeBiz.outletId == null) return;

    setState(() => _isLoading = true);
    try {
      final items = _cart
          .map(
            (c) => {
              'serviceName': c.service.name,
              'unit': c.service.unit,
              'qty': c.qty,
              'price': c.service.price,
            },
          )
          .toList();

      final res = await _api.dio.post(
        '/businesses/${activeBiz.id}/laundry/orders',
        data: {
          'outletId': activeBiz.outletId,
          'customerName': _customerName,
          'customerPhone': _customerPhone,
          'customerAddress': _customerAddress,
          'latitude': _customerLat,
          'longitude': _customerLng,
          'items': items,
          'discount': _discount,
          'paidAmount': _effectivePaidAmount,
          'paymentMethod': _paymentMethod,
          'notes':
              'Parfum: $_selectedParfum (${_fulfillmentType == 'ANTAR_JEMPUT' ? 'Antar-Jemput' : 'Ambil Sendiri'})',
          'dueHours': 48,
        },
      );

      if (mounted) {
        // Picu refresh otomatis di Beranda, Pesanan, dan Inbox tanpa reload manual
        ref.read(appRefreshProvider.notifier).trigger();
        if (fromModal) {
          Navigator.pop(context); // Tutup modal checkout
        }
        _showSuccessReceiptDialog(res.data['data']);
        setState(() {
          _cart.clear();
          _weightInput = '0';
          _discount = 0;
          _dpAmount = 0;
          _paymentType = 'FULL';
          _isPaidNow = true;
          _mobileStep = 0;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.data?['message'] ?? 'Gagal membuat nota laundry',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terjadi kesalahan pada server'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessReceiptDialog(dynamic data) {
    final order = data['order'] ?? {};

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                  size: 44,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nota Laundry Berhasil Dibuat!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nomor Nota: ${order['orderNumber'] ?? '-'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildReceiptRow('Pelanggan', _customerName),
                    const SizedBox(height: 6),
                    _buildReceiptRow('WhatsApp', _customerPhone),
                    const SizedBox(height: 6),
                    _buildReceiptRow('Total Item', '${_cart.length} Layanan'),
                    const Divider(height: 18, color: Color(0xFFE2E8F0)),
                    _buildReceiptRow(
                      'Total Tagihan',
                      'Rp ${_currencyFmt.format(double.tryParse(order['total']?.toString() ?? '0') ?? _cartTotal)}',
                      isBold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.mark_chat_read_rounded,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nota digital otomatis dikirimkan ke WhatsApp pelanggan.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Kembali ke tab Beranda setelah transaksi selesai
                        widget.onTransactionSuccess?.call();
                      },
                      child: const Text(
                        'Selesai',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text(
                        'Cetak Struk',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        final activeBiz = ref.read(authProvider).activeBusiness;
                        ThermalReceiptService.generateLaundryReceiptBytes(
                          businessName: activeBiz?.name ?? 'Cleanique Laundry',
                          outletName: activeBiz?.outletName ?? 'Cabang Utama',
                          orderNumber: order['orderNumber'] ?? 'LD-001',
                          customerName: _customerName,
                          customerPhone: _customerPhone,
                          items: _cart
                              .map(
                                (c) => {
                                  'serviceName': c.service.name,
                                  'qty': c.qty,
                                  'unit': c.service.unit,
                                  'price': c.service.price,
                                },
                              )
                              .toList(),
                          total: _cartTotal,
                          paymentStatus: _isPaidNow ? 'PAID' : 'UNPAID',
                          paymentMethod: _paymentMethod,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Perintah cetak thermal dikirim via Bluetooth!',
                            ),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (widget.onViewOrders != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onViewOrders?.call();
                    },
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text(
                      'Lihat & Pantau di Daftar Pesanan',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isBold = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isBold ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isBold ? AppColors.primary : const Color(0xFF1E293B),
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  void _openCustomerSelectorDialog() {
    final searchCtrl = TextEditingController();
    List<dynamic> customers = [];
    bool isSearching = true;
    String? searchError;
    bool initialized = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> doSearch(String q) async {
            final activeBiz = ref.read(authProvider).activeBusiness;
            if (activeBiz == null) {
              setDialogState(() {
                isSearching = false;
                searchError = 'Bisnis aktif belum dipilih.';
              });
              return;
            }
            setDialogState(() {
              isSearching = true;
              searchError = null;
            });
            try {
              final res = await _api.dio.get(
                '/businesses/${activeBiz.id}/laundry/customers',
                queryParameters: {'q': q},
              );
              if (res.data['success'] == true) {
                setDialogState(() {
                  customers = (res.data['data'] as List?) ?? [];
                  isSearching = false;
                });
              } else {
                setDialogState(() {
                  isSearching = false;
                  searchError =
                      res.data['message'] ?? 'Gagal memuat pelanggan.';
                });
              }
            } on DioException catch (e) {
              setDialogState(() {
                isSearching = false;
                searchError =
                    e.response?.data?['message'] ??
                    'Gagal terhubung ke server.';
              });
            } catch (_) {
              setDialogState(() {
                isSearching = false;
                searchError = 'Terjadi kesalahan saat mencari pelanggan.';
              });
            }
          }

          if (!initialized) {
            initialized = true;
            Future.microtask(() => doSearch(''));
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: MediaQuery.of(ctx).size.height * 0.78,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pilih / Cari Pelanggan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (val) => doSearch(val),
                      decoration: InputDecoration(
                        hintText: 'Cari nama atau nomor WhatsApp...',
                        hintStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: Color(0xFF64748B),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pelanggan Terdaftar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 16,
                          ),
                          label: const Text(
                            'Daftar Baru',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openNewCustomerFormModal();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: isSearching
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : searchError != null
                          ? Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.cloud_off_rounded,
                                      size: 36,
                                      color: AppColors.danger,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      searchError!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () =>
                                          doSearch(searchCtrl.text),
                                      child: const Text('Coba Lagi'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : customers.isEmpty
                          ? Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.person_search_rounded,
                                      size: 40,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      searchCtrl.text.isEmpty
                                          ? 'Belum ada pelanggan terdaftar'
                                          : 'Pelanggan tidak ditemukan',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _openNewCustomerFormModal();
                                      },
                                      child: const Text(
                                        'Daftarkan Pelanggan Baru',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: customers.length,
                              separatorBuilder: (ctx, idx) => const Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (ctx, i) {
                                final c = customers[i];
                                final name = (c['name'] ?? '').toString();
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primary
                                        .withOpacity(0.1),
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'P',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${c['phoneNumber'] ?? '-'} ${c['address'] != null ? '• ${c['address']}' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _customerName = name;
                                      _customerPhone = (c['phoneNumber'] ?? '')
                                          .toString();
                                      _customerAddress = (c['address'] ?? '')
                                          .toString();
                                      _customerLat = c['latitude'];
                                      _customerLng = c['longitude'];
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
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

  void _openNewCustomerFormModal() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pendaftaran Pelanggan Baru',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Nama Lengkap *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: nameCtrl,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nama pelanggan wajib diisi'
                        : null,
                    decoration: InputDecoration(
                      hintText: 'Masukkan nama pelanggan',
                      prefixIcon: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nomor WhatsApp *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'Nomor WhatsApp minimal 8 digit'
                        : null,
                    decoration: InputDecoration(
                      hintText: '0812xxxxxxxx',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Alamat Antar-Jemput (Opsional)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: addressCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Nama jalan, nomor rumah, patokan',
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(
                        isSaving ? 'Menyimpan...' : 'Simpan & Pasang di Kasir',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              final activeBiz = ref.read(authProvider).activeBusiness;
                              if (activeBiz == null) return;
                              setModalState(() => isSaving = true);
                              try {
                                final res = await _api.dio.post(
                                  '/businesses/${activeBiz.id}/laundry/customers',
                                  data: {
                                    if (activeBiz.outletId != null)
                                      'outletId': activeBiz.outletId,
                                    'name': nameCtrl.text.trim(),
                                    'phoneNumber': phoneCtrl.text.trim(),
                                    'address': addressCtrl.text.trim(),
                                  },
                                );
                                final saved = res.data['data'] ?? {};
                                // Picu refresh Inbox & daftar pelanggan
                                ref.read(appRefreshProvider.notifier).trigger();
                                if (mounted) {
                                  setState(() {
                                    _customerName =
                                        (saved['name'] ?? nameCtrl.text.trim())
                                            .toString();
                                    _customerPhone =
                                        (saved['phoneNumber'] ??
                                                phoneCtrl.text.trim())
                                            .toString();
                                    _customerAddress =
                                        (saved['address'] ??
                                                addressCtrl.text.trim())
                                            .toString();
                                    if (_mobileStep == 0) {
                                      _mobileStep = 1;
                                    }
                                  });
                                  _fetchMobileCustomers();
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Pelanggan disimpan ke daftar & Inbox WhatsApp',
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
                                        e.response?.data?['message'] ??
                                            'Gagal menyimpan pelanggan',
                                      ),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setModalState(() => isSaving = false);
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 1024;
    final authState = ref.watch(authProvider);
    final activeBiz = authState.activeBusiness;
    final userName = authState.user?.fullName ?? 'Kasir';
    final role = (activeBiz?.role ?? 'OWNER').toUpperCase();
    final canManageCatalog = role == 'OWNER' || role == 'MANAGER';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Kasir Laundry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    '${activeBiz?.outletName ?? 'Cabang Utama'} • $userName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Scan Pengambilan Cucian',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PickupScannerScreen(),
              ),
            ),
            icon: const Icon(
              Icons.qr_code_scanner_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          if (canManageCatalog)
            IconButton(
              tooltip: 'Kelola Layanan',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CatalogManagementScreen(),
                ),
              ),
              icon: const Icon(
                Icons.edit_note_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildPosFlowStepper(isDesktop),
          Expanded(
            child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildPosFlowStepper(bool isDesktop) {
    final hasCustomer = _customerName.trim().isNotEmpty;
    final hasItems = _cart.isNotEmpty;

    final step1Done = isDesktop ? hasCustomer : _mobileStep > 0;
    final step2Done = isDesktop ? hasItems : _mobileStep > 1;
    final step1Active = isDesktop ? !hasCustomer : _mobileStep == 0;
    final step2Active = isDesktop ? (hasCustomer && !hasItems) : _mobileStep == 1;
    final step3Active = isDesktop ? (hasCustomer && hasItems) : _mobileStep == 2;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: isDesktop ? null : () => setState(() => _mobileStep = 0),
                  child: _buildStepBadge(
                    step: '1',
                    label: 'Pelanggan',
                    done: step1Done,
                    active: step1Active,
                  ),
                ),
                const SizedBox(width: 20, child: Divider(indent: 6, endIndent: 6)),
                InkWell(
                  onTap: isDesktop || !hasCustomer
                      ? null
                      : () => setState(() => _mobileStep = 1),
                  child: _buildStepBadge(
                    step: '2',
                    label: 'Layanan',
                    done: step2Done,
                    active: step2Active,
                  ),
                ),
                const SizedBox(width: 20, child: Divider(indent: 6, endIndent: 6)),
                InkWell(
                  onTap: isDesktop || !hasCustomer || !hasItems
                      ? null
                      : () => setState(() => _mobileStep = 2),
                  child: _buildStepBadge(
                    step: '3',
                    label: 'Bayar',
                    done: false,
                    active: step3Active,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBadge({
    required String step,
    required String label,
    required bool done,
    required bool active,
  }) {
    final bgColor = done
        ? AppColors.success
        : (active ? AppColors.primary : AppColors.surfaceSubtle);
    final textColor = (done || active) ? Colors.white : AppColors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
              : Text(
                  step,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: (done || active) ? FontWeight.w800 : FontWeight.w600,
            color: done
                ? AppColors.success
                : (active ? AppColors.primary : AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  List<ServiceCategory> _activeCategories(CatalogState catalogState) {
    return catalogState.categories.where((c) => c.isActive).toList();
  }

  ServiceCategory? _resolvedSelectedCategory(List<ServiceCategory> cats) {
    if (cats.isEmpty) return null;
    if (_selectedCategoryId == null) return cats.first;
    return cats.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => cats.first,
    );
  }

  Widget _buildServiceSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (val) =>
            setState(() => _searchQuery = val.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Cari layanan / produk...',
          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () {
                    _searchController.clear();
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
    );
  }

  List<ServiceItem> _filteredServices(
    CatalogState catalogState,
    ServiceCategory? selectedCat,
  ) {
    if (_searchQuery.isNotEmpty) {
      return catalogState.allActiveServices
          .where((s) => s.name.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return selectedCat?.services.where((s) => s.isActive).toList() ?? [];
  }

  Widget _buildDesktopLayout() {
    final catalogState = ref.watch(catalogProvider);
    final cats = _activeCategories(catalogState);
    final selectedCat = _resolvedSelectedCategory(cats);
    final services = _filteredServices(catalogState, selectedCat);
    final isKiloan =
        _searchQuery.isEmpty &&
        selectedCat != null &&
        (selectedCat.name.toLowerCase().contains('kiloan') ||
            services.any((s) => s.unit == 'kg'));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kolom Kiri: Search, Tab Kategori & Katalog Layanan Visual
        Expanded(
          flex: 7,
          child: Column(
            children: [
              _buildServiceSearchBar(),
              if (_searchQuery.isEmpty) _buildCategoryTabBar(cats, selectedCat),
              Expanded(
                child: catalogState.isLoading && cats.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : cats.isEmpty
                    ? _buildEmptyCatalogState()
                    : isKiloan
                    ? _buildKiloanOperationalView(services)
                    : _buildPieceCatalogGrid(services),
              ),
            ],
          ),
        ),

        // Garis Pembatas
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),

        // Kolom Kanan: Rincian Pelanggan, Keranjang, dan Checkout
        Expanded(
          flex: 3,
          child: Container(
            color: AppColors.primaryLight.withOpacity(0.18),
            child: Column(
              children: [
                _buildCustomerHeaderWidget(),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Expanded(child: _buildCartItemsList()),
                _buildCartCheckoutFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    if (_mobileStep == 0) return _buildMobileStep1Customer();
    if (_mobileStep == 1) return _buildMobileStep2Services();
    return _buildMobileStep3Checkout();
  }

  // ─── Mobile Halaman 1: Pilih / Tambah Pelanggan ─────────────────────────────

  Widget _buildMobileStep1Customer() {
    final hasCustomer = _customerName.trim().isNotEmpty;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pilih Pelanggan',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: _openNewCustomerFormModal,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text(
                      'Pelanggan Baru',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _custSearchCtrl,
                onChanged: (v) => _fetchMobileCustomers(v),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau nomor WhatsApp...',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _custSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _custSearchCtrl.clear();
                            _fetchMobileCustomers('');
                          },
                        )
                      : null,
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingMobileCustomers && _mobileCustomers.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _mobileCustomersError != null && _mobileCustomers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.danger),
                            const SizedBox(height: 8),
                            Text(_mobileCustomersError!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => _fetchMobileCustomers(_custSearchCtrl.text),
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _mobileCustomers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_search_rounded, size: 44, color: AppColors.textMuted),
                                const SizedBox(height: 8),
                                const Text(
                                  'Belum ada pelanggan terdaftar',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                                const SizedBox(height: 6),
                                ElevatedButton.icon(
                                  onPressed: _openNewCustomerFormModal,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Daftarkan Pelanggan Baru'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _fetchMobileCustomers(_custSearchCtrl.text),
                          color: AppColors.primary,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _mobileCustomers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final c = _mobileCustomers[i];
                              final name = (c['name'] ?? '').toString();
                              final phone = (c['phoneNumber'] ?? '').toString();
                              final addr = (c['address'] ?? '').toString();
                              final isSel = _customerPhone == phone && _customerName == name && name.isNotEmpty;

                              return Material(
                                color: isSel ? AppColors.primaryLight.withOpacity(0.45) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    setState(() {
                                      _customerName = name;
                                      _customerPhone = phone;
                                      _customerAddress = addr;
                                      _customerLat = c['latitude'];
                                      _customerLng = c['longitude'];
                                      _mobileStep = 1;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSel ? AppColors.primary : AppColors.border,
                                        width: isSel ? 1.8 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: AppColors.primary.withOpacity(0.1),
                                          child: Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                addr.isNotEmpty ? '$phone • $addr' : phone,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          isSel ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                                          size: isSel ? 20 : 14,
                                          color: isSel ? AppColors.primary : AppColors.textMuted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
        if (hasCustomer)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _mobileStep = 1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    'Lanjut: Pilih Layanan ($_customerName)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Mobile Halaman 2: Pilih Kategori & Layanan ─────────────────────────────

  Widget _buildMobileStep2Services() {
    final catalogState = ref.watch(catalogProvider);
    final cats = _activeCategories(catalogState);
    final selectedCat = _resolvedSelectedCategory(cats);
    final services = _filteredServices(catalogState, selectedCat);
    final isKiloan =
        _searchQuery.isEmpty &&
        selectedCat != null &&
        (selectedCat.name.toLowerCase().contains('kiloan') ||
            services.any((s) => s.unit == 'kg'));

    return Column(
      children: [
        // Bar ringkas pelanggan aktif
        InkWell(
          onTap: () => setState(() => _mobileStep = 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: AppColors.primaryLight.withOpacity(0.65),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 15, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$_customerName ($_customerPhone)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                  ),
                ),
                const Text(
                  'Ubah',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
        _buildServiceSearchBar(),
        if (_searchQuery.isEmpty) _buildCategoryTabBar(cats, selectedCat),
        Expanded(
          child: catalogState.isLoading && cats.isEmpty
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : cats.isEmpty
              ? _buildEmptyCatalogState()
              : isKiloan
              ? _buildMobileKiloanList(services)
              : _buildMobilePieceCatalogGrid(services),
        ),
        // Bottom Bar Halaman 2
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _mobileStep = 0),
                  child: const Text('Kembali'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _cart.isNotEmpty
                        ? () => setState(() => _mobileStep = 2)
                        : null,
                    child: Text(
                      _cart.isNotEmpty
                          ? 'Lanjut Bayar (${_cart.length} • Rp ${_currencyFmt.format(_cartTotal)})'
                          : 'Pilih Layanan Dulu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Mobile Halaman 3: Review Keranjang & Pembayaran ────────────────────────

  Widget _buildMobileStep3Checkout() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Ringkasan Pelanggan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          Text(
                            '$_customerPhone • ${_customerAddress.isNotEmpty ? _customerAddress : 'Ambil di Outlet'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _mobileStep = 0),
                      child: const Text('Ganti'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Rincian Keranjang
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.shopping_basket_rounded, size: 17, color: AppColors.primary),
                              const SizedBox(width: 6),
                              const Flexible(
                                child: Text(
                                  'Keranjang Layanan',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_cart.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _mobileStep = 1),
                          child: const Text('+ Tambah Layanan', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    Divider(color: AppColors.primary.withOpacity(0.18)),
                    ..._cart.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.service.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  Text(
                                    'Rp ${_currencyFmt.format(item.service.price)} / ${item.service.unit}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppColors.textMuted),
                              onPressed: () {
                                setState(() {
                                  if (item.qty > 1) {
                                    item.qty -= 1;
                                  } else {
                                    _cart.removeAt(i);
                                    if (_cart.isEmpty) _mobileStep = 1;
                                  }
                                });
                              },
                            ),
                            Text(
                              '${item.qty % 1 == 0 ? item.qty.toInt() : item.qty} ${item.service.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.primary),
                              onPressed: () => setState(() => item.qty += 1),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Parfum, Pengiriman & Diskon
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text('Parfum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        DropdownButton<String>(
                          value: _selectedParfum,
                          underline: const SizedBox(),
                          isDense: true,
                          items: const [
                            DropdownMenuItem(value: 'Akasia Segar', child: Text('Akasia Segar', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'Lavender Lembut', child: Text('Lavender Relaxing', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'Sakura Fresh', child: Text('Sakura Floral', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'Non-Parfum', child: Text('Non-Parfum', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (val) => setState(() => _selectedParfum = val!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            label: const Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Ambil Toko', style: TextStyle(fontSize: 11)),
                              ),
                            ),
                            selected: _fulfillmentType == 'AMBIL_SENDIRI',
                            onSelected: (_) => setState(() {
                              _fulfillmentType = 'AMBIL_SENDIRI';
                              _deliveryFee = 0;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            label: const Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Antar (+10k)', style: TextStyle(fontSize: 11)),
                              ),
                            ),
                            selected: _fulfillmentType == 'ANTAR_JEMPUT',
                            onSelected: (_) => setState(() {
                              _fulfillmentType = 'ANTAR_JEMPUT';
                              _deliveryFee = 10000;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _discount > 0 ? _discount.toInt().toString() : '',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
                      decoration: const InputDecoration(
                        labelText: 'Diskon / Potongan (Rp)',
                        hintText: '0',
                        prefixIcon: Icon(Icons.discount_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Metode & Status Pembayaran
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Metode Pembayaran', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Row(
                      children: ['CASH', 'QRIS', 'TRANSFER'].map((method) {
                        final isSel = _paymentMethod == method;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: method == 'TRANSFER' ? 0 : 8),
                            child: ChoiceChip(
                              showCheckmark: false,
                              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                              label: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    method,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isSel ? Colors.white : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppColors.primary,
                              onSelected: (_) => setState(() => _paymentMethod = method),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _paymentType == 'FULL' ? AppColors.primary.withOpacity(0.08) : Colors.white,
                              side: BorderSide(color: _paymentType == 'FULL' ? AppColors.primary : AppColors.border),
                            ),
                            onPressed: () => setState(() {
                              _paymentType = 'FULL';
                              _isPaidNow = true;
                            }),
                            child: const Text('Lunas', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _paymentType == 'DP' ? AppColors.primaryLight : Colors.white,
                              side: BorderSide(color: _paymentType == 'DP' ? AppColors.accent : AppColors.border),
                            ),
                            onPressed: () => setState(() {
                              _paymentType = 'DP';
                              _isPaidNow = false;
                            }),
                            child: const Text('DP', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _paymentType == 'LATER' ? AppColors.warningLight : Colors.white,
                              side: BorderSide(color: _paymentType == 'LATER' ? AppColors.warning : AppColors.border),
                            ),
                            onPressed: () => setState(() {
                              _paymentType = 'LATER';
                              _isPaidNow = false;
                            }),
                            child: const Text('Nanti', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                    if (_paymentType == 'DP') ...[
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: _dpAmount > 0 ? _dpAmount.toInt().toString() : '',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (v) => setState(() => _dpAmount = double.tryParse(v) ?? 0),
                        decoration: const InputDecoration(
                          labelText: 'Nominal DP (Rp)',
                          hintText: 'Masukkan jumlah DP',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // Bottom Checkout Bar Halaman 3
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('Total Tagihan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    Flexible(
                      child: Text(
                        'Rp ${_currencyFmt.format(_cartTotal)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _isLoading ? null : () => setState(() => _mobileStep = 1),
                      child: const Text('Kembali'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _submitOrder(fromModal: false),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Simpan Nota & Kirim WA'),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCatalogState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 52,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Katalog Layanan Masih Kosong',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tambahkan kategori dan layanan melalui menu Opsi › Katalog Layanan & Produk.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Kelola Kategori & Produk'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CatalogManagementScreen(),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Muat Ulang'),
                  onPressed: () =>
                      ref.read(catalogProvider.notifier).fetchCatalog(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileKiloanList(List<ServiceItem> kiloanList) {
    if (kiloanList.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada layanan di kategori ini.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: kiloanList.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final item = kiloanList[i];
        final inCart = _cart
            .where((c) => c.service.id == item.id)
            .fold(0.0, (acc, c) => acc + c.qty);

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          child: InkWell(
            onTap: () => item.unit == 'kg'
                ? _openWeightInputBottomSheet(item)
                : _addPieceItemToCart(item),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: inCart > 0
                      ? AppColors.primary
                      : const Color(0xFFE2E8F0),
                  width: inCart > 0 ? 1.8 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: inCart > 0
                        ? AppColors.primary.withOpacity(0.06)
                        : Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: inCart > 0
                          ? AppColors.primary
                          : AppColors.primaryLight.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconForService(item),
                      color: inCart > 0 ? Colors.white : AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${item.estHours} Jam Selesai',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (inCart > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Di Keranjang: ${inCart % 1 == 0 ? inCart.toInt() : inCart} kg',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rp ${_currencyFmt.format(item.price)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'per kg',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.scale_rounded,
                              size: 12,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Timbang',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobilePieceCatalogGrid(List<ServiceItem> filtered) {
    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada layanan di kategori ini.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: width >= 600 ? 3 : 2,
        mainAxisExtent: 156,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final item = filtered[i];
        final inCart = _cart
            .where((c) => c.service.id == item.id)
            .fold(0.0, (acc, c) => acc + c.qty);

        return InkWell(
          onTap: () => item.unit == 'kg'
              ? _openWeightInputBottomSheet(item)
              : _addPieceItemToCart(item),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: inCart > 0 ? AppColors.primary : const Color(0xFFE2E8F0),
                width: inCart > 0 ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _iconForService(item),
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                    if (inCart > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${inCart.toInt()} ${item.unit}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 19,
                        color: Color(0xFF94A3B8),
                      ),
                  ],
                ),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Rp ${_currencyFmt.format(item.price)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.estHours}j',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openWeightInputBottomSheet(ServiceItem item) {
    setState(() {
      _activeWeightItem = item;
      _weightInput = '0';
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void onModalNumpad(String val) {
            HapticFeedback.lightImpact();
            setModalState(() {
              if (val == 'C') {
                _weightInput = '0';
              } else if (val == '⌫') {
                if (_weightInput.length > 1) {
                  _weightInput = _weightInput.substring(
                    0,
                    _weightInput.length - 1,
                  );
                } else {
                  _weightInput = '0';
                }
              } else if (val == '.') {
                if (!_weightInput.contains('.')) {
                  _weightInput += '.';
                }
              } else {
                if (_weightInput == '0') {
                  _weightInput = val;
                } else {
                  _weightInput += val;
                }
              }
            });
            setState(() {});
          }

          final weightVal = double.tryParse(_weightInput) ?? 0.0;
          final subtotal = weightVal * item.price;

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _iconForService(item),
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Rp ${_currencyFmt.format(item.price)} / kg • Estimasi ${item.estHours} jam',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Digital Scale Display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'TIMBANGAN DIGITAL KASIR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _weightInput,
                              style: const TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF38BDF8),
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'kg',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Total: Rp ${_currencyFmt.format(subtotal)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Native Numpad Grid
                  SizedBox(
                    height: 220,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: ['1', '2', '3']
                                .map(
                                  (v) => _buildModalNumpadKey(v, onModalNumpad),
                                )
                                .toList(),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: ['4', '5', '6']
                                .map(
                                  (v) => _buildModalNumpadKey(v, onModalNumpad),
                                )
                                .toList(),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: ['7', '8', '9']
                                .map(
                                  (v) => _buildModalNumpadKey(v, onModalNumpad),
                                )
                                .toList(),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: ['.', '0', '⌫']
                                .map(
                                  (v) => _buildModalNumpadKey(v, onModalNumpad),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action Add Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: weightVal > 0
                            ? AppColors.primary
                            : const Color(0xFFCBD5E1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 20,
                      ),
                      label: Text(
                        weightVal > 0
                            ? 'TAMBAH KE KERANJANG (Rp ${_currencyFmt.format(subtotal)})'
                            : 'MASUKKAN BERAT PAKAIAN',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: weightVal > 0
                          ? () {
                              _addKiloanToCart();
                              Navigator.pop(ctx);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildModalNumpadKey(String val, void Function(String) onPress) {
    final isAction = val == '⌫';
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: isAction ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => onPress(val),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                val,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isAction
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabBar(
    List<ServiceCategory> cats,
    ServiceCategory? selectedCat,
  ) {
    if (cats.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...cats.map((cat) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildCategoryPill(cat, selectedCat?.id == cat.id),
              );
            }),
            if ((ref.read(authProvider).activeBusiness?.role ?? 'OWNER').toUpperCase() == 'OWNER' ||
                (ref.read(authProvider).activeBusiness?.role ?? '').toUpperCase() == 'MANAGER')
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategoryFormScreen()),
                ),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Kategori',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPill(ServiceCategory cat, bool isSelected) {
    final activeCount = cat.services.where((s) => s.isActive).length;
    return InkWell(
      onTap: () => setState(() {
        _selectedCategoryId = cat.id;
        _activeWeightItem = null;
      }),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForCategory(cat),
              size: 18,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$activeCount layanan',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? Colors.white.withOpacity(0.85)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerHeaderWidget() {
    final hasCustomer = _customerName.trim().isNotEmpty;
    return InkWell(
      onTap: _openCustomerSelectorDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: Colors.white,
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: hasCustomer
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.warningLight,
              child: hasCustomer
                  ? Text(
                      _customerName.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        fontSize: 16,
                      ),
                    )
                  : const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          hasCustomer
                              ? _customerName
                              : 'Pilih / Isi Data Pelanggan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: hasCustomer
                                ? const Color(0xFF0F172A)
                                : AppColors.warning,
                          ),
                        ),
                      ),
                      if (hasCustomer) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pelanggan',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasCustomer
                        ? '${_customerPhone.isNotEmpty ? _customerPhone : '-'} • ${_customerAddress.isNotEmpty ? _customerAddress : 'Walk-in Counter'}'
                        : 'Ketuk untuk mengisi nama & nomor WhatsApp pelanggan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasCustomer ? Icons.swap_horiz_rounded : Icons.edit_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasCustomer ? 'Ganti' : 'Isi',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKiloanOperationalView(List<ServiceItem> kiloanList) {
    if (kiloanList.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada layanan di kategori ini.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final currentWeightItem =
        _activeWeightItem != null &&
            kiloanList.any((s) => s.id == _activeWeightItem!.id)
        ? _activeWeightItem!
        : kiloanList.first;
    _activeWeightItem = currentWeightItem;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Pilihan Layanan Kiloan
          Expanded(
            flex: 3,
            child: ListView.separated(
              itemCount: kiloanList.length,
              separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final item = kiloanList[i];
                final isSelected = currentWeightItem.id == item.id;
                return InkWell(
                  onTap: () => setState(() => _activeWeightItem = item),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryLight
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : const Color(0xFFE2E8F0),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _iconForService(item),
                            color: isSelected
                                ? Colors.white
                                : AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Estimasi: ${item.estHours} Jam Selesai',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Rp ${_currencyFmt.format(item.price)}/${item.unit}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 16),

          // Timbangan LCD & Numpad
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'TIMBANGAN DIGITAL KASIR',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                            letterSpacing: 1.2,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _weightInput,
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              currentWeightItem.unit,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Layanan: ${currentWeightItem.name}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _buildNumpadRow(['1', '2', '3'])),
                        Expanded(child: _buildNumpadRow(['4', '5', '6'])),
                        Expanded(child: _buildNumpadRow(['7', '8', '9'])),
                        Expanded(child: _buildNumpadRow(['.', '0', '⌫'])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 18,
                      ),
                      label: Text(
                        (double.tryParse(_weightInput) ?? 0) > 0
                            ? 'MASUKKAN KERANJANG (Rp ${_currencyFmt.format((double.tryParse(_weightInput) ?? 0) * currentWeightItem.price)})'
                            : 'MASUKKAN BERAT',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      onPressed: (double.tryParse(_weightInput) ?? 0) > 0
                          ? _addKiloanToCart
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumpadRow(List<String> values) {
    return Row(
      children: values.map((val) {
        final isAction = val == '⌫';
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: Material(
              color: isAction
                  ? const Color(0xFFFEF2F2)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _onNumpadPress(val),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    val,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isAction
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPieceCatalogGrid(List<ServiceItem> filtered) {
    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada layanan di kategori ini.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: width >= 1360 ? 4 : 3,
        childAspectRatio: 1.45,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final item = filtered[i];
        final inCart = _cart
            .where((c) => c.service.id == item.id)
            .fold(0.0, (acc, c) => acc + c.qty);

        return InkWell(
          onTap: () => _addPieceItemToCart(item),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: inCart > 0 ? AppColors.primary : const Color(0xFFE2E8F0),
                width: inCart > 0 ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _iconForService(item),
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                    if (inCart > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${inCart.toInt()} ${item.unit}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Rp ${_currencyFmt.format(item.price)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.estHours}j',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartItemsList() {
    if (_cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_basket_outlined,
                  size: 42,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Keranjang cucian masih kosong',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pilih layanan atau timbang pakaian di sebelah kiri.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withOpacity(0.45),
            border: Border(bottom: BorderSide(color: AppColors.primary.withOpacity(0.18))),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_basket_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Keranjang Cucian',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_cart.length} item',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _cart.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final item = _cart[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.service.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@ Rp ${_currencyFmt.format(item.service.price)} / ${item.service.unit}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () {
                            setState(() {
                              if (item.qty > 1) {
                                item.qty -= 1;
                              } else {
                                _cart.removeAt(i);
                              }
                            });
                          },
                        ),
                        Text(
                          '${item.qty} ${item.service.unit}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.add_circle_outline,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          onPressed: () => setState(() => item.qty += 1),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Rp ${_currencyFmt.format(item.subtotal)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCartCheckoutFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.primary.withOpacity(0.22))),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pilihan Parfum:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              DropdownButton<String>(
                value: _selectedParfum,
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(
                    value: 'Akasia Segar',
                    child: Text(
                      'Akasia Segar (Best Seller)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Lavender Lembut',
                    child: Text(
                      'Lavender Relaxing',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Sakura Fresh',
                    child: Text(
                      'Sakura Floral',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Non-Parfum',
                    child: Text(
                      'Non-Parfum (Khusus Alergi)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedParfum = val!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Pembayaran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              Text(
                'Rp ${_currencyFmt.format(_cartTotal)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _cart.isNotEmpty
                    ? AppColors.primary
                    : const Color(0xFF94A3B8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _cart.isNotEmpty ? _openCheckoutModal : null,
              child: const Text(
                'PROSES NOTA & CETAK STRUK',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCheckoutModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        'Konfirmasi Nota Laundry',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        avatar: const Icon(Icons.storefront_rounded, size: 16),
                        label: const Text(
                          'Ambil Toko',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _fulfillmentType == 'AMBIL_SENDIRI',
                        onSelected: (val) {
                          setModalState(() {
                            _fulfillmentType = 'AMBIL_SENDIRI';
                            _deliveryFee = 0;
                          });
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        avatar: const Icon(
                          Icons.delivery_dining_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'Antar (+10k)',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _fulfillmentType == 'ANTAR_JEMPUT',
                        onSelected: (val) {
                          setModalState(() {
                            _fulfillmentType = 'ANTAR_JEMPUT';
                            _deliveryFee = 10000;
                          });
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Diskon
                TextFormField(
                  initialValue: _discount > 0
                      ? _discount.toInt().toString()
                      : '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    setModalState(() => _discount = double.tryParse(v) ?? 0);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Diskon / Potongan (Rp)',
                    hintText: '0',
                    prefixIcon: const Icon(Icons.discount_outlined, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Tagihan',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Rp ${_currencyFmt.format(_cartTotal)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Metode Pembayaran
                Row(
                  children: ['CASH', 'QRIS', 'TRANSFER'].map((method) {
                    final isSel = _paymentMethod == method;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: method == 'TRANSFER' ? 0 : 8,
                        ),
                        child: ChoiceChip(
                          label: Center(
                            child: Text(
                              method,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          selected: isSel,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceSubtle,
                          onSelected: (_) =>
                              setModalState(() => _paymentMethod = method),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // Status Pembayaran: Lunas, DP, Bayar Nanti
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _paymentType == 'FULL'
                              ? AppColors.primary.withOpacity(0.08)
                              : Colors.white,
                          side: BorderSide(
                            color: _paymentType == 'FULL'
                                ? AppColors.primary
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => setModalState(() {
                          _paymentType = 'FULL';
                          _isPaidNow = true;
                        }),
                        child: Text(
                          'Lunas',
                          style: TextStyle(
                            color: _paymentType == 'FULL'
                                ? AppColors.primary
                                : const Color(0xFF475569),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _paymentType == 'DP'
                              ? AppColors.primaryLight
                              : Colors.white,
                          side: BorderSide(
                            color: _paymentType == 'DP'
                                ? AppColors.accent
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => setModalState(() {
                          _paymentType = 'DP';
                          _isPaidNow = false;
                        }),
                        child: Text(
                          'DP Sebagian',
                          style: TextStyle(
                            color: _paymentType == 'DP'
                                ? AppColors.accent
                                : const Color(0xFF475569),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _paymentType == 'LATER'
                              ? const Color(0xFFFFFBEB)
                              : Colors.white,
                          side: BorderSide(
                            color: _paymentType == 'LATER'
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => setModalState(() {
                          _paymentType = 'LATER';
                          _isPaidNow = false;
                        }),
                        child: Text(
                          'Bayar Nanti',
                          style: TextStyle(
                            color: _paymentType == 'LATER'
                                ? const Color(0xFFB45309)
                                : const Color(0xFF475569),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_paymentType == 'DP') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _dpAmount > 0
                        ? _dpAmount.toInt().toString()
                        : '',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => setModalState(
                      () => _dpAmount = double.tryParse(v) ?? 0,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Nominal DP (Rp)',
                      hintText: 'Masukkan jumlah DP',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _submitOrder,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'SIMPAN NOTA & KIRIM WHATSAPP',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
