import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../dashboard/presentation/screens/home_nav_screen.dart';
import '../../../subscription/presentation/screens/owner_onboarding_plan_screen.dart';
import '../../providers/auth_provider.dart';
import '../widgets/google_sign_in_web_helper.dart';

bool _isGoogleSignInInitialized = false;

class SsoLoginScreen extends ConsumerStatefulWidget {
  const SsoLoginScreen({super.key});

  @override
  ConsumerState<SsoLoginScreen> createState() => _SsoLoginScreenState();
}

class _SsoLoginScreenState extends ConsumerState<SsoLoginScreen> with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final _emailFormKey = GlobalKey<FormState>();

  late TabController _tabController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _serverErrorMessage;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initGoogleSignIn();
  }

  Future<void> _initGoogleSignIn() async {
    if (_isGoogleSignInInitialized) {
      debugPrint('[SSO] GoogleSignIn sudah terinisialisasi sebelumnya.');
      _listenAuthEvents();
      return;
    }

    try {
      debugPrint('[SSO] Inisialisasi GoogleSignIn...');
      if (kIsWeb) {
        await GoogleSignIn.instance.initialize(
          clientId: '108460638721-6cv6u92f82h2r57knc24ulr2ds988494.apps.googleusercontent.com',
        );
      } else {
        await GoogleSignIn.instance.initialize(
          clientId: '108460638721-c1vr28i1rcrp1a7uqam5n9brdgjm846t.apps.googleusercontent.com',
          serverClientId: '108460638721-6cv6u92f82h2r57knc24ulr2ds988494.apps.googleusercontent.com',
        );
      }
      _isGoogleSignInInitialized = true;
      debugPrint('[SSO] Inisialisasi GoogleSignIn Berhasil.');
      _listenAuthEvents();
    } catch (e, stack) {
      debugPrint('[SSO] Error Inisialisasi Google: $e\n$stack');
    }
  }

  void _listenAuthEvents() {
    _authSubscription?.cancel();
    _authSubscription = GoogleSignIn.instance.authenticationEvents.listen((event) async {
      debugPrint('[SSO] Auth Event Diterima: $event');
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final account = event.user;
        debugPrint('[SSO] Akun Google: ${account.email} (${account.displayName})');
        final idToken = account.authentication.idToken;
        await _authenticateWithBackend(
          idToken: idToken,
          email: account.email,
          fullName: account.displayName,
          avatarUrl: account.photoUrl,
        );
      }
    });
  }

  Future<void> _authenticateWithBackend({
    String? idToken,
    required String email,
    String? fullName,
    String? avatarUrl,
  }) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final success = await ref.read(authProvider.notifier).loginWithGoogleSSO(
        idToken: idToken,
        simulatedEmail: email,
        fullName: fullName,
        avatarUrl: avatarUrl,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Owner Login: $email',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        final authState = ref.read(authProvider);
        if (authState.needsOnboarding && authState.user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OwnerOnboardingPlanScreen(
                ownerEmail: authState.user!.email,
                defaultBusinessName: authState.activeBusiness?.name,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const HomeNavScreen(),
            ),
          );
        }
      } else if (mounted) {
        final errMsg = ref.read(authProvider).errorMessage ?? 'Gagal autentikasi ke database';
        setState(() => _serverErrorMessage = errMsg);
      }
    } catch (e) {
      if (mounted) setState(() => _serverErrorMessage = 'Terjadi kesalahan sistem: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleMobileGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _serverErrorMessage = null;
    });
    try {
      debugPrint('[SSO] Menjalankan GoogleSignIn.instance.authenticate()...');
      final account = await GoogleSignIn.instance.authenticate();
      debugPrint('[SSO] Google authenticate berhasil! Email: ${account.email}, Name: ${account.displayName}');
      final idToken = account.authentication.idToken;
      await _authenticateWithBackend(
        idToken: idToken,
        email: account.email,
        fullName: account.displayName,
        avatarUrl: account.photoUrl,
      );
    } catch (e, stack) {
      debugPrint('[SSO] Info login Google Mobile: $e\n$stack');
      if (!mounted) return;

      setState(() {
        _serverErrorMessage = 'Gagal login Google SSO: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Gagal login Google: $e'),
              ),
            ],
          ),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEmailPasswordLogin() async {
    setState(() => _serverErrorMessage = null);

    if (!_emailFormKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      final res = await _api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (res.data['success'] == true) {
        final token = res.data['data']['token'];

        // Simpan token ke storage
        await _api.storage.write(key: 'jwt_token', value: token);

        // Update authProvider agar isAuthenticated = true dan main.dart otomatis pindah
        await ref.read(authProvider.notifier).checkSession();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Berhasil masuk sebagai $email',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeNavScreen()),
        );
      } else {
        // Backend mengembalikan success: false
        setState(() => _serverErrorMessage = res.data['message'] ?? 'Email atau kata sandi tidak sesuai.');
      }
    } on DioException catch (e) {
      debugPrint('[Login] DioException: ${e.response?.statusCode} — ${e.response?.data}');
      if (mounted) {
        setState(() {
          _serverErrorMessage = e.response?.data?['message'] ?? 'Email atau kata sandi tidak sesuai.';
        });
      }
    } catch (e) {
      debugPrint('[Login] Error tidak terduga: $e');
      if (mounted) {
        setState(() => _serverErrorMessage = 'Terjadi kesalahan sistem. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Background ambient lights
          Positioned(
            top: -120,
            left: -100,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Center Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Official Logo Banner (Besar & Jernih dengan background transparan/putih)
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Image.asset(
                        'assets/images/mitracs_logo.png',
                        height: 90,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => const Text(
                          'mitraCS.ai',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Smart Laundry POS & AI Customer Service',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 20),

                    // Modern Sliding Role Selector Tab
                    Container(
                      height: 46,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: const Color(0xFF64748B),
                        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        tabs: const [
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.workspace_premium_rounded, size: 16),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Owner',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.badge_rounded, size: 16),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Staf / Kasir',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Server error alert banner if any
                    if (_serverErrorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _serverErrorMessage!,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB91C1C)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Slide Views: Owner (Google SSO) vs Staf (Email & Password)
                    SizedBox(
                      height: 330,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          SingleChildScrollView(child: _buildOwnerSsoSlide()),
                          SingleChildScrollView(child: _buildStaffEmailSlide()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // SLIDE 1: Owner Laundry (Google SSO)
  Widget _buildOwnerSsoSlide() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Column(
            children: const [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Portal Juragan / Owner',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF15803D)),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                'Masuk satu klik untuk kelola outlet & kasir laundry.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF166534)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Google SSO Button
        if (kIsWeb)
          renderWebGoogleSignIn()
        else
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _isLoading ? null : _handleMobileGoogleSignIn,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/google_logo.png',
                      height: 20,
                      width: 20,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Masuk dengan Akun Google',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Akun baru otomatis didaftarkan sebagai Owner usaha.',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  // SLIDE 2: Staf & Admin (Email & Password)
  Widget _buildStaffEmailSlide() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Email wajib diisi';
              }
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(value.trim())) {
                return 'Format email tidak valid';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: 'nama@domain.com',
              labelText: 'Email Akun Staf',
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              prefixIcon: const Icon(Icons.email_outlined, size: 20, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              errorStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.4)),
            ),
          ),
          const SizedBox(height: 12),

          // Password
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Kata sandi wajib diisi';
              }
              if (value.length < 6) {
                return 'Kata sandi minimal 6 karakter';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: '••••••••',
              labelText: 'Kata Sandi (Password)',
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              errorStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.4)),
            ),
          ),
          const SizedBox(height: 18),

          // Submit
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _handleEmailPasswordLogin,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Masuk ke Sistem',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Gunakan akun kasir/CS yang didaftarkan oleh Owner atau Super Admin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }
}
