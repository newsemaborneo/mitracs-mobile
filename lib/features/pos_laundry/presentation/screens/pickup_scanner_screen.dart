import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:multibiz_mobile/core/constants/app_colors.dart';
import 'package:multibiz_mobile/core/network/api_client.dart';
import 'package:multibiz_mobile/core/providers/app_refresh_provider.dart';
import 'package:multibiz_mobile/features/auth/providers/auth_provider.dart';

class PickupScannerScreen extends ConsumerStatefulWidget {
  const PickupScannerScreen({super.key});

  @override
  ConsumerState<PickupScannerScreen> createState() =>
      _PickupScannerScreenState();
}

class _PickupScannerScreenState extends ConsumerState<PickupScannerScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final NumberFormat _currencyFmt = NumberFormat('#,###', 'id_ID');
  final TextEditingController _manualCodeCtrl = TextEditingController();
  final MobileScannerController _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: true,
  );
  final ImagePicker _picker = ImagePicker();
  late final AnimationController _scanLineCtrl;

  bool _isSearching = false;
  bool _isSubmitting = false;
  bool _hasCameraPermission = true;
  bool _isPermanentlyDenied = false;
  bool _torchOn = false;
  String? _errorMessage;
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _searchResults = [];
  String _paymentMethod = 'CASH';

  @override
  void initState() {
    super.initState();
    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestCameraPermissionAndStart();
    });
  }

  Future<void> _requestCameraPermissionAndStart() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _hasCameraPermission = false;
          _isPermanentlyDenied = status.isPermanentlyDenied;
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _hasCameraPermission = true;
        _isPermanentlyDenied = false;
      });
    }
    await _scannerCtrl.start().catchError((_) {});
  }

  Future<void> _scanFromGallery() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final capture = await _scannerCtrl.analyzeImage(picked.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final raw = capture.barcodes.first.rawValue;
        if (raw != null && raw.trim().isNotEmpty) {
          await _lookupCode(raw);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Code tidak terbaca pada gambar tersebut.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal memindai gambar QR Code.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _manualCodeCtrl.dispose();
    _scannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _isSearching) return;

    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _manualCodeCtrl.text = code;
    });

    try {
      final res = await _api.dio.get(
        '/businesses/${activeBiz.id}/laundry/orders/pickup-search',
        queryParameters: {'q': code},
      );
      if (res.data['success'] == true && mounted) {
        final rawList = (res.data['data'] as List?) ?? [];
        final results = rawList
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (results.isEmpty) {
          setState(() {
            _order = null;
            _searchResults = [];
            _errorMessage =
                'Pesanan dengan nama atau kode "$code" tidak ditemukan.';
          });
        } else if (results.length == 1) {
          setState(() {
            _order = results.first;
            _searchResults = [];
          });
        } else {
          setState(() {
            _order = null;
            _searchResults = results;
          });
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _order = null;
          _errorMessage =
              e.response?.data?['message']?.toString() ??
              'Nota tidak ditemukan.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _order = null;
          _errorMessage = 'Gagal memeriksa kode nota.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _confirmPickup({required bool payRemaining}) async {
    final order = _order;
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (order == null || activeBiz == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final res = await _api.dio.post(
        '/businesses/${activeBiz.id}/laundry/orders/pickup',
        data: {
          'code': order['orderNumber'],
          'payRemaining': payRemaining,
          'paymentMethod': _paymentMethod,
        },
      );
      if (res.data['success'] == true && mounted) {
        ref.read(appRefreshProvider.notifier).trigger();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data['message']?.toString() ??
                  'Pengambilan cucian berhasil dikonfirmasi!',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.data?['message']?.toString() ??
                  'Gagal memproses pengambilan.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terjadi kesalahan saat konfirmasi pengambilan.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Scan Pengambilan Cucian'),
        actions: [
          IconButton(
            tooltip: 'Scan dari Galeri',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _scanFromGallery,
          ),
          IconButton(
            tooltip: 'Mulai Ulang Kamera',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _scannerCtrl.start().catchError((_) {}),
          ),
          IconButton(
            tooltip: 'Lampu Kilat',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _scannerCtrl.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Ganti Kamera',
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _scannerCtrl.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Area Kamera Scanner (tampil saat belum ada nota/hasil pencarian nama)
          if (_order == null && _searchResults.isEmpty)
            Expanded(
              child: !_hasCameraPermission
                  ? Container(
                      color: const Color(0xFF0F172A),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.no_photography_rounded,
                              color: Colors.white70,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Izin akses kamera belum diberikan',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Izinkan kamera untuk memindai QR Code WhatsApp pelanggan.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isPermanentlyDenied
                                ? openAppSettings
                                : _requestCameraPermissionAndStart,
                            icon: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: Text(
                              _isPermanentlyDenied
                                  ? 'Buka Pengaturan Izin'
                                  : 'Izinkan Akses Kamera',
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _scannerCtrl,
                          fit: BoxFit.cover,
                          placeholderBuilder: (ctx) => Container(
                            color: const Color(0xFF0F172A),
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: AppColors.accent,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Mengaktifkan kamera...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onDetect: (capture) {
                            if (_isSearching || _order != null) return;
                            for (final barcode in capture.barcodes) {
                              final val = barcode.rawValue;
                              if (val != null && val.trim().isNotEmpty) {
                                _lookupCode(val);
                                break;
                              }
                            }
                          },
                          errorBuilder: (ctx, error) => Container(
                            color: const Color(0xFF0F172A),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(24),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_off_rounded,
                                  color: Colors.white70,
                                  size: 40,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Kamera tidak tersedia.\nGunakan Galeri QR atau input kode nota di bawah.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Vignette gelap dengan lubang kotak scan
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _ScannerOverlayPainter(
                              cutoutSize: 230,
                              borderRadius: 20,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        // Bingkai sudut Emerald + garis laser animasi
                        Center(
                          child: SizedBox(
                            width: 230,
                            height: 230,
                            child: Stack(
                              children: [
                                CustomPaint(
                                  painter: _ScannerCornersPainter(
                                    color: AppColors.accent,
                                    radius: 20,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                                AnimatedBuilder(
                                  animation: _scanLineCtrl,
                                  builder: (ctx, _) => Positioned(
                                    left: 14,
                                    right: 14,
                                    top: 14 + (_scanLineCtrl.value * 198),
                                    child: Container(
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.accent.withOpacity(0.0),
                                            AppColors.accent,
                                            AppColors.accent.withOpacity(0.0),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.accent.withOpacity(0.6),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Petunjuk di atas kotak scan
                        Positioned(
                          top: 20,
                          left: 24,
                          right: 24,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Arahkan QR Code WhatsApp ke dalam kotak',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Kontrol kamera mengambang di bawah
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildCameraActionPill(
                                icon: Icons.photo_library_outlined,
                                label: 'Galeri',
                                onTap: _scanFromGallery,
                              ),
                              const SizedBox(width: 12),
                              _buildCameraActionPill(
                                icon: _torchOn
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                label: _torchOn ? 'Flash On' : 'Flash',
                                active: _torchOn,
                                onTap: () async {
                                  await _scannerCtrl.toggleTorch();
                                  if (mounted) {
                                    setState(() => _torchOn = !_torchOn);
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildCameraActionPill(
                                icon: Icons.cameraswitch_rounded,
                                label: 'Kamera',
                                onTap: () => _scannerCtrl.switchCamera(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

          // Input Manual Kode Nota & Pesan Error Ringkas
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null && _order == null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualCodeCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _lookupCode,
                        decoration: InputDecoration(
                          hintText: 'Ketik nama pelanggan / kode nota...',
                          hintStyle: const TextStyle(fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _manualCodeCtrl.text.isNotEmpty ||
                                  _searchResults.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _manualCodeCtrl.clear();
                                      _searchResults = [];
                                      _order = null;
                                      _errorMessage = null;
                                    });
                                  },
                                )
                              : null,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isSearching
                          ? null
                          : () => _lookupCode(_manualCodeCtrl.text),
                      child: _isSearching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Cari'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_order != null)
            Expanded(child: _buildOrderPickupCard(_order!))
          else if (_searchResults.isNotEmpty)
            Expanded(child: _buildSearchResultsList()),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList() {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final o = _searchResults[i];
        final customer = Map<String, dynamic>.from((o['customer'] ?? {}) as Map);
        final total = double.tryParse(o['total']?.toString() ?? '0') ?? 0;
        final paid = double.tryParse(o['paidAmount']?.toString() ?? '0') ?? 0;
        final remaining = (total - paid).clamp(0, double.infinity);
        final status = (o['status'] ?? 'DITERIMA').toString();
        final isPickedUp = status == 'DIAMBIL';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPickedUp
                  ? AppColors.border
                  : AppColors.primary.withOpacity(0.28),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _order = o),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer['name']?.toString() ?? 'Pelanggan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${o['orderNumber'] ?? '-'} • $status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        remaining > 0
                            ? 'Sisa: Rp ${_currencyFmt.format(remaining)}'
                            : 'Lunas (Rp ${_currencyFmt.format(total)})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: remaining > 0
                              ? AppColors.danger
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (isPickedUp)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Sudah Diambil',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                )
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          if (remaining > 0) {
                            setState(() => _order = o);
                          } else {
                            setState(() => _order = o);
                            _confirmPickup(payRemaining: false);
                          }
                        },
                  child: Text(
                    remaining > 0 ? 'Lunasi & Ambil' : 'Sudah Diambil',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrderPickupCard(Map<String, dynamic> order) {
    final customer = Map<String, dynamic>.from(
      (order['customer'] ?? {}) as Map,
    );
    final items = (order['items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final total = double.tryParse(order['total']?.toString() ?? '0') ?? 0;
    final paid = double.tryParse(order['paidAmount']?.toString() ?? '0') ?? 0;
    final remaining = (total - paid).clamp(0, double.infinity);
    final status = (order['status'] ?? 'DITERIMA').toString();
    final isAlreadyPickedUp = status == 'DIAMBIL';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order['orderNumber']?.toString() ?? '-',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isAlreadyPickedUp
                          ? AppColors.successLight
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isAlreadyPickedUp
                            ? AppColors.success
                            : AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${customer['name'] ?? 'Pelanggan'} • ${customer['phoneNumber'] ?? '-'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Divider(height: 20),
              ...items.map(
                (it) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${it['serviceName'] ?? '-'} (${it['qty']} ${it['unit'] ?? ''})',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Text(
                        'Rp ${_currencyFmt.format(double.tryParse(it['subtotal']?.toString() ?? '0') ?? 0)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Tagihan', style: TextStyle(fontSize: 12.5)),
                  Text(
                    'Rp ${_currencyFmt.format(total)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sudah Dibayar', style: TextStyle(fontSize: 12.5)),
                  Text(
                    'Rp ${_currencyFmt.format(paid)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sisa Tagihan',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Rp ${_currencyFmt.format(remaining)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: remaining > 0
                          ? AppColors.danger
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!isAlreadyPickedUp && remaining > 0) ...[
          const Text(
            'Metode Pelunasan Sisa Tagihan',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['CASH', 'QRIS', 'TRANSFER'].map((m) {
              final isSel = _paymentMethod == m;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: m == 'TRANSFER' ? 0 : 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Center(
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    selected: isSel,
                    selectedColor: AppColors.primary,
                    onSelected: (_) => setState(() => _paymentMethod = m),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],
        if (isAlreadyPickedUp)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cucian untuk nota ini sudah diambil.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: _isSubmitting
                ? null
                : () => _confirmPickup(payRemaining: remaining > 0),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_rounded, size: 20),
            label: Text(
              remaining > 0
                  ? 'Lunasi Rp ${_currencyFmt.format(remaining)} & Sudah Diambil'
                  : 'Sudah Diambil',
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _order = null;
              _errorMessage = null;
              _manualCodeCtrl.clear();
            });
          },
          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
          label: const Text('Scan Nota Lain'),
        ),
      ],
    );
  }

  Widget _buildCameraActionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Material(
      color: active ? AppColors.primary : Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: active
                  ? AppColors.accent
                  : Colors.white.withOpacity(0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double cutoutSize;
  final double borderRadius;

  const _ScannerOverlayPainter({
    required this.cutoutSize,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.52);
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutoutSize,
      height: cutoutSize,
    );
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(cutoutRect, Radius.circular(borderRadius)),
      );
    final combined = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(combined, bgPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.cutoutSize != cutoutSize ||
      oldDelegate.borderRadius != borderRadius;
}

class _ScannerCornersPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _ScannerCornersPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, radius)
        ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
        ..lineTo(len, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w - radius, 0)
        ..arcToPoint(Offset(w, radius), radius: Radius.circular(radius))
        ..lineTo(w, len),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, h - len)
        ..lineTo(0, h - radius)
        ..arcToPoint(
          Offset(radius, h),
          radius: Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(len, h),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(w - len, h)
        ..lineTo(w - radius, h)
        ..arcToPoint(
          Offset(w, h - radius),
          radius: Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(w, h - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerCornersPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
