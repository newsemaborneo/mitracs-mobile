import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/app_state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/presentation/screens/sso_login_screen.dart';
import '../../../dashboard/presentation/screens/home_nav_screen.dart';

class OwnerOnboardingPlanScreen extends ConsumerStatefulWidget {
  final String ownerEmail;
  final String? defaultBusinessName;
  final bool isFromSettings;

  const OwnerOnboardingPlanScreen({
    super.key,
    required this.ownerEmail,
    this.defaultBusinessName,
    this.isFromSettings = false,
  });

  @override
  ConsumerState<OwnerOnboardingPlanScreen> createState() =>
      _OwnerOnboardingPlanScreenState();
}

class _OwnerOnboardingPlanScreenState
    extends ConsumerState<OwnerOnboardingPlanScreen> {
  final ApiClient _api = ApiClient();
  final _step1FormKey = GlobalKey<FormState>();
  final _currencyFmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  int _currentStep = 0; // 0: Data Diri, 1: Pilih Paket, 2: Pembayaran

  late TextEditingController _ownerNameCtrl;
  late TextEditingController _businessNameCtrl;
  late TextEditingController _outletNameCtrl;
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  LatLng _outletLocation = const LatLng(-6.8905, 107.6166);
  final MapController _mapController = MapController();

  XFile? _paymentProofImage;
  final ImagePicker _picker = ImagePicker();
  String _selectedPaymentMethod = 'BCA'; // BCA, MANDIRI, QRIS

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;

  List<dynamic> _plans = [];
  String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.isFromSettings ? 1 : 0;
    final authState = ref.read(authProvider);
    _ownerNameCtrl = TextEditingController(
      text: authState.user?.fullName ?? '',
    );
    _businessNameCtrl = TextEditingController();
    _outletNameCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPlans());
  }

  @override
  void dispose() {
    _ownerNameCtrl.dispose();
    _businessNameCtrl.dispose();
    _outletNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final res = await _api.dio.get('/plans');
      if (res.data['success'] == true) {
        final list = (res.data['data'] as List?) ?? [];
        setState(() {
          _plans = list;
          final popular = list.firstWhere(
            (p) => p['isPopular'] == true,
            orElse: () => list.isNotEmpty ? list.first : null,
          );
          if (popular != null) {
            _selectedPlanId = popular['id']?.toString();
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _loadError = 'Gagal memuat daftar paket langganan.';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Tidak dapat terhubung ke server untuk memuat paket.';
        _isLoading = false;
      });
    }
  }

  void _exitWithoutSubscribing() {
    if (widget.isFromSettings || Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // Jangan pernah biarkan tembus ke HomeNavScreen jika belum berlangganan aktif
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Text('Akses Terkunci', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Untuk mengoperasikan kasir POS & WhatsApp AI, bisnis Anda membutuhkan paket langganan aktif.\n\nApakah Anda ingin keluar ke layar Login?',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tetap di Sini', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await ref.read(authProvider.notifier).logout();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SsoLoginScreen()),
                    (route) => false,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Keluar ke Login'),
            ),
          ],
        ),
      );
    }
  }

  void _goNextStep() {
    if (_currentStep == 0) {
      if (!_step1FormKey.currentState!.validate()) return;
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_selectedPlanId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Silakan pilih salah satu paket langganan'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
      setState(() => _currentStep = 2);
    }
  }

  void _goPrevStep() {
    final minStep = widget.isFromSettings ? 1 : 0;
    if (_currentStep > minStep) {
      setState(() => _currentStep -= 1);
    } else {
      _exitWithoutSubscribing();
    }
  }

  Future<void> _pickPaymentProof() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (photo != null && mounted) {
        setState(() => _paymentProofImage = photo);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bukti transfer berhasil dipilih'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih gambar: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _openMapPickerModal() {
    LatLng tempLocation = _outletLocation;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMapState) => Container(
          height: MediaQuery.of(ctx).size.height * 0.82,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pin Lokasi Outlet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Ketuk peta untuk menentukan titik koordinat outlet',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _outletLocation,
                          initialZoom: 15.0,
                          onTap: (tapPosition, point) {
                            setMapState(() => tempLocation = point);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.multibiz.multibiz_mobile',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: tempLocation,
                                width: 48,
                                height: 48,
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  size: 44,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.my_location_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${tempLocation.latitude.toStringAsFixed(5)}, ${tempLocation.longitude.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Simpan Titik Lokasi'),
                  onPressed: () {
                    setState(() => _outletLocation = tempLocation);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activateAndContinue() async {
    if (_selectedPlanId == null) return;
    setState(() => _isSubmitting = true);

    try {
      final activeBiz = ref.read(authProvider).activeBusiness;
      if (activeBiz != null) {
        if (!widget.isFromSettings) {
          await _api.dio.post('/businesses/${activeBiz.id}/onboarding', data: {
            'ownerFullName': _ownerNameCtrl.text.trim(),
            'businessName': _businessNameCtrl.text.trim(),
            'outletName': _outletNameCtrl.text.trim(),
            'phoneNumber': _phoneCtrl.text.trim(),
            'address':
                '${_addressCtrl.text.trim()}${_cityCtrl.text.trim().isNotEmpty ? ', ${_cityCtrl.text.trim()}' : ''}',
          });
        }

        await _api.dio.post(
          '/businesses/${activeBiz.id}/subscription/subscribe',
          data: {
            'planId': _selectedPlanId,
            'billingCycle': 'MONTHLY',
            'paymentMethod': _selectedPaymentMethod,
          },
        );

        await ref.read(authProvider.notifier).checkSession();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usaha & paket langganan berhasil diaktifkan'),
          backgroundColor: AppColors.success,
        ),
      );

      if (widget.isFromSettings || Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeNavScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengaktifkan langganan: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Map<String, dynamic>? get _currentSelectedPlan {
    try {
      return _plans.firstWhere((p) => p['id']?.toString() == _selectedPlanId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Kembali',
          onPressed: _goPrevStep,
        ),
        title: const Text('Paket & Berlangganan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            tooltip: 'Keluar Akun',
            onPressed: _exitWithoutSubscribing,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStepIndicatorBar(),
          Expanded(
            child: _currentStep == 0
                ? _buildStep1DataDiri()
                : _currentStep == 1
                    ? _buildStep2PilihPaket()
                    : _buildStep3Pembayaran(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  Widget _buildStepIndicatorBar() {
    final steps = widget.isFromSettings
        ? ['Pilih Paket', 'Bayar']
        : ['Data Diri', 'Pilih Paket', 'Bayar'];
    final effectiveStep = widget.isFromSettings
        ? (_currentStep - 1).clamp(0, 1)
        : _currentStep;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (idx) {
          if (idx.isOdd) {
            final lineIndex = idx ~/ 2;
            final isDone = effectiveStep > lineIndex;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: isDone ? AppColors.primary : AppColors.border,
              ),
            );
          }
          final stepIndex = idx ~/ 2;
          final isDone = effectiveStep > stepIndex;
          final isActive = effectiveStep == stepIndex;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.success
                      : (isActive ? AppColors.primary : AppColors.surfaceSubtle),
                  shape: BoxShape.circle,
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                    : Text(
                        '${stepIndex + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isActive ? Colors.white : AppColors.textMuted,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                steps[stepIndex],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: (isActive || isDone) ? FontWeight.w800 : FontWeight.w600,
                  color: isDone
                      ? AppColors.success
                      : (isActive ? AppColors.primary : AppColors.textMuted),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ─── Halaman 1: Isi Data Diri & Usaha ───────────────────────────────────────

  Widget _buildStep1DataDiri() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _step1FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lengkapi Data Pemilik & Usaha',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Akun terdaftar: ${widget.ownerEmail}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary,
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _ownerNameCtrl.text.isNotEmpty
                                    ? _ownerNameCtrl.text
                                    : 'Akun Google',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.ownerEmail,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _businessNameCtrl,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Username / nama usaha wajib diisi' : null,
                    decoration: const InputDecoration(
                      labelText: 'Username / Nama Usaha *',
                      hintText: 'Masukkan username atau nama usaha laundry',
                      prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _outletNameCtrl,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Nama cabang wajib diisi' : null,
                    decoration: const InputDecoration(
                      labelText: 'Nama Cabang Utama *',
                      hintText: 'Contoh: Cabang Pusat',
                      prefixIcon: Icon(Icons.location_city_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor Telepon / WhatsApp',
                      hintText: '0812xxxxxxxx',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Alamat Lengkap Outlet',
                      hintText: 'Nama jalan, nomor bangunan, patokan',
                      prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kota / Kabupaten',
                      hintText: 'Contoh: Bandung',
                      prefixIcon: Icon(Icons.map_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openMapPickerModal,
                      icon: const Icon(Icons.pin_drop_outlined, size: 18),
                      label: Text(
                        'Pin Peta (${_outletLocation.latitude.toStringAsFixed(4)}, ${_outletLocation.longitude.toStringAsFixed(4)})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  // ─── Halaman 2: Pilih Paket Langganan ───────────────────────────────────────

  Widget _buildStep2PilihPaket() {
    if (_isLoading) {
      return const LoadingListPlaceholder(itemCount: 3);
    }
    if (_loadError != null && _plans.isEmpty) {
      return ErrorStateWidget(message: _loadError!, onRetry: _fetchPlans);
    }
    if (_plans.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.workspace_premium_outlined,
        title: 'Belum Ada Paket Tersedia',
        subtitle: 'Hubungi admin atau coba muat ulang daftar paket.',
        actionLabel: 'Muat Ulang',
        onAction: _fetchPlans,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _plans.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, idx) {
        if (idx == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Paket Sesuai Kebutuhan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Anda dapat mengganti atau membatalkan paket kapan saja.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        final plan = _plans[idx - 1];
        final isSelected = plan['id']?.toString() == _selectedPlanId;
        final isPopular = plan['isPopular'] == true;
        final price =
            double.tryParse(plan['priceMonthly']?.toString() ?? '0') ?? 0;
        final features = (plan['features'] as List<dynamic>?) ?? [];

        return Material(
          color: isSelected ? const Color(0xFFF0F9FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => setState(() => _selectedPlanId = plan['id']?.toString()),
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: isSelected ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.borderDark,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (plan['name'] ?? 'Paket').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'REKOMENDASI',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (plan['description'] != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      plan['description'].toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _currencyFmt.format(price),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '/ bulan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: features.map((f) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            f.toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Halaman 3: Pembayaran & Aktivasi ───────────────────────────────────────

  Widget _buildStep3Pembayaran() {
    final selectedPlan = _currentSelectedPlan;
    final price = selectedPlan != null
        ? (double.tryParse(selectedPlan['priceMonthly']?.toString() ?? '0') ?? 0)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Konfirmasi & Pembayaran',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Ringkasan Paket & Usaha
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
                _summaryRow('Usaha', _businessNameCtrl.text.trim()),
                const SizedBox(height: 6),
                _summaryRow('Cabang Utama', _outletNameCtrl.text.trim()),
                const SizedBox(height: 6),
                _summaryRow(
                  'Paket Dipilih',
                  (selectedPlan?['name'] ?? '-').toString(),
                ),
                const Divider(height: 20),
                _summaryRow(
                  'Total Tagihan / Bulan',
                  _currencyFmt.format(price),
                  isHighlight: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pilih Metode Pembayaran
          const Text(
            'Pilih Metode Pembayaran',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPayMethodChip('BCA', 'Transfer BCA'),
              const SizedBox(width: 8),
              _buildPayMethodChip('MANDIRI', 'Mandiri'),
              const SizedBox(width: 8),
              _buildPayMethodChip('QRIS', 'QRIS'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              _selectedPaymentMethod == 'QRIS'
                  ? 'Scan QRIS mitraCS.ai setelah konfirmasi, lalu unggah tangkapan layar bukti bayar.'
                  : 'Transfer sesuai nominal tagihan ke rekening $_selectedPaymentMethod PT MitraCS Digital Indonesia, lalu unggah bukti transfer.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Upload Bukti
          InkWell(
            onTap: _pickPaymentProof,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _paymentProofImage != null
                    ? AppColors.successLight
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _paymentProofImage != null
                      ? AppColors.success
                      : AppColors.borderDark,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _paymentProofImage != null
                        ? Icons.check_circle_rounded
                        : Icons.upload_file_rounded,
                    color: _paymentProofImage != null
                        ? AppColors.success
                        : AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _paymentProofImage != null
                              ? 'Bukti Transfer Terpilih'
                              : 'Unggah Bukti Pembayaran (Opsional)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _paymentProofImage != null
                              ? _paymentProofImage!.name
                              : 'Ketuk untuk memilih foto dari galeri',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
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

  Widget _summaryRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isHighlight ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isHighlight ? 16 : 13,
              fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w700,
              color: isHighlight ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayMethodChip(String key, String label) {
    final isSelected = _selectedPaymentMethod == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedPaymentMethod = key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Bottom Action Bar per Halaman ──────────────────────────────────────────

  Widget _buildBottomActionBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _isSubmitting ? null : _goPrevStep,
                child: Text(_currentStep == 0 ? 'Kembali' : 'Sebelumnya'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : (_currentStep < 2 ? _goNextStep : _activateAndContinue),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _currentStep == 0
                              ? 'Lanjut: Pilih Paket'
                              : (_currentStep == 1
                                  ? 'Lanjut: Pembayaran'
                                  : 'Aktifkan Paket'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
