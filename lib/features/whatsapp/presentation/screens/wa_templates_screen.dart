import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/app_state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';

class WaTemplatesScreen extends ConsumerStatefulWidget {
  const WaTemplatesScreen({super.key});

  @override
  ConsumerState<WaTemplatesScreen> createState() => _WaTemplatesScreenState();
}

class _WaTemplatesScreenState extends ConsumerState<WaTemplatesScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  final _createdCtrl = TextEditingController();
  final _readyCtrl = TextEditingController();
  final _reminderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchTemplates());
  }

  @override
  void dispose() {
    _createdCtrl.dispose();
    _readyCtrl.dispose();
    _reminderCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTemplates() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.dio.get('/businesses/${activeBiz.id}/whatsapp/templates');
      if (res.data['success'] == true) {
        final data = res.data['data'] ?? {};
        _createdCtrl.text = (data['orderCreated'] ?? '').toString();
        _readyCtrl.text = (data['orderReady'] ?? '').toString();
        _reminderCtrl.text = (data['paymentReminder'] ?? '').toString();
      }
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['message'] ?? 'Gagal memuat template pesan WhatsApp';
      });
    } catch (_) {
      setState(() => _error = 'Terjadi kesalahan saat memuat template');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTemplates() async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    setState(() => _isSaving = true);
    try {
      final res = await _api.dio.put(
        '/businesses/${activeBiz.id}/whatsapp/templates',
        data: {
          'orderCreated': _createdCtrl.text.trim(),
          'orderReady': _readyCtrl.text.trim(),
          'paymentReminder': _reminderCtrl.text.trim(),
        },
      );
      if (res.data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template WhatsApp disimpan!'), backgroundColor: AppColors.success),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data?['message'] ?? 'Gagal menyimpan template'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _insertVariable(TextEditingController ctrl, String variable) {
    final text = ctrl.text;
    final sel = ctrl.selection;
    final pos = sel.isValid ? sel.start : text.length;
    final updated = text.substring(0, pos) + variable + text.substring(pos);
    ctrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: pos + variable.length),
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
          'Template Pesan WhatsApp',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: (_isLoading || _isSaving) ? null : _saveTemplates,
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingListPlaceholder(itemCount: 3)
          : _error != null
              ? ErrorStateWidget(message: _error!, onRetry: _fetchTemplates)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Gunakan variabel {nama}, {no_nota}, {total}, dan {status} untuk mengisi data pelanggan secara otomatis.',
                        style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTemplateCard(
                      title: 'Nota Baru Dibuat',
                      subtitle: 'Dikirim otomatis saat kasir menyelesaikan transaksi baru.',
                      controller: _createdCtrl,
                      hint: 'Halo {nama}, nota {no_nota} sebesar {total} sedang kami proses.',
                    ),
                    const SizedBox(height: 14),
                    _buildTemplateCard(
                      title: 'Cucian Siap Diambil / Dikirim',
                      subtitle: 'Dikirim otomatis saat status pesanan diubah ke Siap Diambil.',
                      controller: _readyCtrl,
                      hint: 'Halo {nama}, cucian untuk nota {no_nota} sudah selesai dan siap diambil.',
                    ),
                    const SizedBox(height: 14),
                    _buildTemplateCard(
                      title: 'Pengingat Tagihan Belum Lunas',
                      subtitle: 'Digunakan untuk mengingatkan pelanggan yang memilih bayar di akhir.',
                      controller: _reminderCtrl,
                      hint: 'Halo {nama}, pengingat tagihan nota {no_nota} sebesar {total}.',
                    ),
                  ],
                ),
    );
  }

  Widget _buildTemplateCard({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
  }) {
    const vars = ['{nama}', '{no_nota}', '{total}', '{status}'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: vars
                .map((v) => ActionChip(
                      label: Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      backgroundColor: AppColors.surfaceSubtle,
                      onPressed: () => _insertVariable(controller, v),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceSubtle,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}
