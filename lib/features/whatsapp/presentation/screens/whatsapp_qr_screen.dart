import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:multibiz_mobile/core/constants/app_colors.dart';
import 'package:multibiz_mobile/core/network/api_client.dart';
import 'package:multibiz_mobile/features/auth/providers/auth_provider.dart';
import 'package:dio/dio.dart';

class WhatsAppQrScreen extends ConsumerStatefulWidget {
  const WhatsAppQrScreen({super.key});

  @override
  ConsumerState<WhatsAppQrScreen> createState() => _WhatsAppQrScreenState();
}

class _WhatsAppQrScreenState extends ConsumerState<WhatsAppQrScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _phoneCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isRequestingPairing = false;
  String? _qrString;
  String? _pairingCode;
  String _status = 'DISCONNECTED';
  String? _phoneNumber;
  Timer? _pollTimer;

  Future<void> _disconnectSession() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null || _isLoading) return;

    setState(() => _isLoading = true);
    try {
      await _api.dio.post(
        '/businesses/${activeBiz.id}/whatsapp/disconnect/${activeBiz.outletId}',
      );
      if (mounted) {
        setState(() {
          _status = 'DISCONNECTED';
          _qrString = null;
          _pairingCode = null;
          _phoneNumber = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koneksi WhatsApp berhasil diputuskan')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memutuskan koneksi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPairingCode() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    final phone = _phoneCtrl.text.trim();
    if (activeBiz == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nomor WhatsApp terlebih dahulu')),
      );
      return;
    }

    setState(() {
      _isRequestingPairing = true;
      _pairingCode = null;
    });
    try {
      final res = await _api.dio.post(
        '/businesses/${activeBiz.id}/whatsapp/pairing-code/${activeBiz.outletId}',
        data: {'phoneNumber': phone},
      );
      if (mounted && res.data['success'] == true) {
        setState(() {
          _pairingCode = res.data['data']?['pairingCode']?.toString();
        });
        _startPolling();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat kode pairing: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequestingPairing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkStatus();
      if (mounted && _status != 'CONNECTED' && _qrString != null) {
        _startPolling();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus({bool silent = false}) async {
    final authState = ref.read(authProvider);

    if (authState.isLoading) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) await _checkStatus(silent: silent);
      return;
    }

    final activeBiz = authState.activeBusiness;
    if (activeBiz == null) {
      debugPrint('[WhatsAppQR] activeBusiness null — auth belum selesai atau belum login');
      return;
    }
    if (activeBiz.outletId == null) {
      debugPrint('[WhatsAppQR] outletId null pada business: ${activeBiz.id}');
      return;
    }

    if (!silent) setState(() => _isLoading = true);
    try {
      debugPrint('[WhatsAppQR] Fetching status: /businesses/${activeBiz.id}/whatsapp/status/${activeBiz.outletId}');
      final res = await _api.dio.get('/businesses/${activeBiz.id}/whatsapp/status/${activeBiz.outletId}');
      debugPrint('[WhatsAppQR] Response: ${res.data}');
      if (res.data['success'] == true && mounted) {
        final data = res.data['data'];
        final newStatus = (data['status'] ?? 'DISCONNECTED').toString();
        setState(() {
          _status = newStatus;
          _phoneNumber = data['phoneNumber'];
          _qrString = data['qrString'];
        });
        if (newStatus == 'CONNECTED') {
          _pollTimer?.cancel();
        }
      }
    } on DioException catch (e) {
      debugPrint('[WhatsAppQR] DioException: ${e.response?.statusCode} — ${e.response?.data}');
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal cek status: ${e.response?.data?['message'] ?? e.message}')),
        );
      }
    } catch (e) {
      debugPrint('[WhatsAppQR] Error tidak terduga: $e');
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _startSession() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null || activeBiz.outletId == null) return;

    if (_status == 'CONNECTED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp sudah terhubung.')),
      );
      return;
    }

    _pollTimer?.cancel();
    setState(() {
      _isLoading = true;
      _qrString = null;
    });
    try {
      final res = await _api.dio.post('/businesses/${activeBiz.id}/whatsapp/connect/${activeBiz.outletId}');
      if (res.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sesi dimulai! Menunggu QR Code dari server...')),
          );
        }
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          await _checkStatus(silent: true);
          _startPolling();
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data?['message'] ?? 'Gagal menghubungkan WhatsApp')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terjadi kesalahan pada koneksi')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    int ticks = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      ticks++;
      if (!mounted || _status == 'CONNECTED' || ticks >= 60) {
        timer.cancel();
        return;
      }
      await _checkStatus(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _status == 'CONNECTED';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Koneksi WhatsApp Outlet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: _isLoading ? null : _checkStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isConnected ? AppColors.successLight : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isConnected ? AppColors.success : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.check_circle : Icons.error_outline,
                    color: isConnected ? AppColors.success : AppColors.warning,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected ? 'WhatsApp Terhubung' : 'WhatsApp Belum Terhubung',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isConnected ? AppColors.success : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isConnected
                              ? 'Nomor: +$_phoneNumber\nAI Otomatis Aktif Menjawab'
                              : 'Tautkan nomor WhatsApp outlet ini untuk mengaktifkan AI Customer Service.',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Panel QR / koneksi
            if (!isConnected) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    if (_qrString != null) ...[
                      QrImageView(
                        data: _qrString!,
                        version: QrVersions.auto,
                        size: 220.0,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Pindai QR ini melalui WhatsApp di HP Anda:\nMenu Titik Tiga › Perangkat Tertaut › Tautkan Perangkat',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ] else ...[
                      Container(
                        width: 220,
                        height: 220,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: AppColors.primary)
                            : const Icon(Icons.qr_code_scanner, size: 80, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Klik tombol di bawah untuk membuat QR Code koneksi WhatsApp.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('BUAT / PERBARUI QR CODE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isLoading ? null : _startSession,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Atau Hubungkan dengan Nomor WA',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Masukkan nomor WhatsApp Anda untuk mendapatkan kode unik (8 karakter).',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Nomor WhatsApp (cth: 08123456789)',
                        prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _isRequestingPairing ? null : _requestPairingCode,
                        icon: _isRequestingPairing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.key_rounded, size: 18),
                        label: const Text('BUAT KODE PAIRING', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (_pairingCode != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Text('Kode Pairing WhatsApp Anda:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            SelectableText(
                              _pairingCode!,
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, color: AppColors.primary),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Buka WhatsApp › Perangkat Tertaut › Tautkan dengan nomor telepon › Masukkan kode di atas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              // Connected state
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 60),
                    const SizedBox(height: 12),
                    const Text(
                      'WhatsApp Aktif!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.success),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'AI Customer Service sudah aktif menerima dan membalas pesan pelanggan secara otomatis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off_rounded, color: AppColors.danger),
                label: const Text('Putuskan Koneksi', style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isLoading ? null : _disconnectSession,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
