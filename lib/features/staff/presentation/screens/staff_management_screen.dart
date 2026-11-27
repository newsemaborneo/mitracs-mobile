import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/app_state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMembers());
  }

  Future<void> _fetchMembers() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.dio.get('/businesses/${activeBiz.id}/members');
      if (res.data['success'] == true) {
        final raw = (res.data['data'] as List?) ?? [];
        setState(() {
          _members = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['message'] ?? 'Gagal memuat daftar staf dari server';
      });
    } catch (_) {
      setState(() => _error = 'Terjadi kesalahan saat memuat staf');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeMember(String memberId, String name) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    try {
      final res = await _api.dio.delete('/businesses/${activeBiz.id}/members/$memberId');
      if (res.data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Akses $name berhasil dihapus'), backgroundColor: AppColors.success),
        );
        await _fetchMembers();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data?['message'] ?? 'Gagal menghapus staf'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _openAddStaffModal() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String selectedRole = 'CASHIER';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tambah Akun Staf / Kasir',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama staf wajib diisi' : null,
                  decoration: InputDecoration(
                    labelText: 'Nama Lengkap',
                    hintText: 'Masukkan nama staf',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                    if (!v.contains('@')) return 'Format email tidak valid';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Email Login',
                    hintText: 'email@domain.com',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: true,
                  validator: (v) => (v == null || v.length < 6) ? 'Kata sandi minimal 6 karakter' : null,
                  decoration: InputDecoration(
                    labelText: 'Kata Sandi Awal',
                    hintText: 'Minimal 6 karakter',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  onChanged: (v) => setModalState(() => selectedRole = v!),
                  decoration: InputDecoration(
                    labelText: 'Peran / Hak Akses',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'CASHIER', child: Text('Kasir (POS & Pesanan)')),
                    DropdownMenuItem(value: 'CS_OPERATOR', child: Text('Operator CS (Inbox WhatsApp)')),
                    DropdownMenuItem(value: 'MANAGER', child: Text('Manajer Outlet')),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                '/businesses/${activeBiz.id}/members',
                                data: {
                                  'fullName': nameCtrl.text.trim(),
                                  'email': emailCtrl.text.trim(),
                                  'password': passwordCtrl.text.trim(),
                                  'role': selectedRole,
                                },
                              );
                              if (res.data['success'] == true && ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Staf berhasil ditambahkan'), backgroundColor: AppColors.success),
                                );
                                _fetchMembers();
                              }
                            } on DioException catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.response?.data?['message'] ?? 'Gagal menambahkan staf'),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                            } finally {
                              if (ctx.mounted) setModalState(() => isSaving = false);
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Simpan Akun Staf', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Kelola Staf & Kasir',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: _isLoading ? null : _fetchMembers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _openAddStaffModal,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: const Text('Tambah Staf', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _isLoading && _members.isEmpty
          ? const LoadingListPlaceholder()
          : _error != null && _members.isEmpty
              ? ErrorStateWidget(message: _error!, onRetry: _fetchMembers)
              : _members.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.people_outline_rounded,
                      title: 'Belum Ada Staf Terdaftar',
                      subtitle: 'Tambahkan akun kasir atau operator CS agar mereka dapat masuk menggunakan email masing-masing.',
                      actionLabel: 'Tambah Staf Sekarang',
                      onAction: _openAddStaffModal,
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchMembers,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: _members.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final m = _members[i];
                          final user = m['user'] is Map ? m['user'] : m;
                          final name = (user['fullName'] ?? m['fullName'] ?? 'Staf').toString();
                          final email = (user['email'] ?? m['email'] ?? '-').toString();
                          final role = (m['role'] ?? 'CASHIER').toString();
                          final isOwner = role.toUpperCase() == 'OWNER';

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(0.1),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                                ),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              subtitle: Text('$email ($role)', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              trailing: isOwner
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('Owner', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                      tooltip: 'Hapus Akses',
                                      onPressed: () => _removeMember(m['id'].toString(), name),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
