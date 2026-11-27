import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../../core/widgets/app_state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../chat/presentation/screens/whatsapp_conversation_screen.dart';

class CustomersManagementScreen extends ConsumerStatefulWidget {
  const CustomersManagementScreen({super.key});

  @override
  ConsumerState<CustomersManagementScreen> createState() =>
      _CustomersManagementScreenState();
}

class _CustomersManagementScreenState
    extends ConsumerState<CustomersManagementScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCustomers());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers([String query = '']) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.dio.get(
        '/businesses/${activeBiz.id}/laundry/customers',
        queryParameters: {if (query.trim().isNotEmpty) 'q': query.trim()},
      );
      if (res.data['success'] == true) {
        final raw = (res.data['data'] as List?) ?? [];
        setState(() {
          _customers = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['message'] ?? 'Gagal memuat daftar pelanggan';
      });
    } catch (_) {
      setState(() => _error = 'Terjadi kesalahan saat memuat pelanggan');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openCustomerWhatsAppChat(Map<String, dynamic> customer) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;
    final phone = (customer['phoneNumber'] ?? '').toString();
    final digits = phone.replaceAll(RegExp(r'\D'), '');

    try {
      final res = await _api.dio.get('/businesses/${activeBiz.id}/conversations');
      if (res.data['success'] == true && mounted) {
        final convos = (res.data['data'] as List?) ?? [];
        final match = convos.cast<Map<String, dynamic>>().firstWhere(
          (c) {
            final cp = (c['customerPhone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            return cp.isNotEmpty && (cp == digits || cp.endsWith(digits) || digits.endsWith(cp));
          },
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppConversationScreen(
                conversation: match,
                onTakeover: (_) {},
                onReturnToAi: (_) {},
              ),
            ),
          );
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Percakapan WhatsApp belum tersedia untuk pelanggan ini.'),
            backgroundColor: AppColors.textSecondary,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membuka chat WhatsApp'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _openAddCustomerModal() {
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SingleChildScrollView(
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
                        'Tambah Pelanggan Baru',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                  decoration: InputDecoration(
                    labelText: 'Nama Pelanggan',
                    hintText: 'Masukkan nama lengkap',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().length < 8)
                      ? 'Nomor WhatsApp minimal 8 digit'
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Nomor WhatsApp',
                    hintText: '0812xxxxxxxx',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Alamat (Opsional)',
                    hintText: 'Alamat lengkap untuk antar-jemput',
                    filled: true,
                    fillColor: AppColors.surfaceSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                              if (res.data['success'] == true && ctx.mounted) {
                                Navigator.pop(ctx);
                                ref.read(appRefreshProvider.notifier).trigger();
                                _fetchCustomers(_searchCtrl.text);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pelanggan ditambahkan ke daftar & Inbox WA'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } on DioException catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.response?.data?['message'] ?? 'Gagal menyimpan pelanggan',
                                    ),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                            } finally {
                              if (ctx.mounted) setModalState(() => isSaving = false);
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Simpan Pelanggan', style: TextStyle(fontWeight: FontWeight.w700)),
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
          'Daftar Pelanggan',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: _isLoading ? null : () => _fetchCustomers(_searchCtrl.text),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _openAddCustomerModal,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: const Text('Tambah Pelanggan', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => _fetchCustomers(v),
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor WhatsApp...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceSubtle,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading && _customers.isEmpty
                ? const LoadingListPlaceholder()
                : _error != null && _customers.isEmpty
                    ? ErrorStateWidget(
                        message: _error!,
                        onRetry: () => _fetchCustomers(_searchCtrl.text),
                      )
                    : _customers.isEmpty
                        ? EmptyStateWidget(
                            icon: Icons.people_outline_rounded,
                            title: 'Belum Ada Pelanggan',
                            subtitle: 'Pelanggan baru yang didaftarkan otomatis masuk ke daftar ini dan Inbox WhatsApp.',
                            actionLabel: 'Tambah Pelanggan',
                            onAction: _openAddCustomerModal,
                          )
                        : RefreshIndicator(
                            onRefresh: () => _fetchCustomers(_searchCtrl.text),
                            color: AppColors.primary,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                              itemCount: _customers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final c = _customers[i];
                                final name = (c['name'] ?? 'Pelanggan').toString();
                                final phone = (c['phoneNumber'] ?? '-').toString();
                                final addr = (c['address'] ?? '').toString();
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primary.withOpacity(0.1),
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      addr.isNotEmpty ? '$phone\n$addr' : phone,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                    isThreeLine: addr.isNotEmpty,
                                    onTap: () => _openCustomerWhatsAppChat(c),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.mark_chat_read_outlined, size: 20, color: Color(0xFF008069)),
                                      tooltip: 'Buka Chat WhatsApp',
                                      onPressed: () => _openCustomerWhatsAppChat(c),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
