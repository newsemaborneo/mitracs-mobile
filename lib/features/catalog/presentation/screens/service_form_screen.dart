import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/catalog_model.dart';
import '../../providers/catalog_provider.dart';

class ServiceFormScreen extends ConsumerStatefulWidget {
  final String categoryId;
  final ServiceItem? existing;

  const ServiceFormScreen({super.key, required this.categoryId, this.existing});

  @override
  ConsumerState<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends ConsumerState<ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _estHoursCtrl;
  String _selectedUnit = 'kg';
  bool _isActive = true;

  final List<Map<String, String>> _units = [
    {'value': 'kg', 'label': 'Kilogram (kg)'},
    {'value': 'pcs', 'label': 'Satuan (pcs)'},
    {'value': 'meter', 'label': 'Meter (m)'},
    {'value': 'porsi', 'label': 'Porsi'},
    {'value': 'item', 'label': 'Item'},
    {'value': 'paket', 'label': 'Paket'},
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl = TextEditingController(text: e != null ? e.price.toInt().toString() : '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _estHoursCtrl = TextEditingController(text: e != null ? e.estHours.toString() : '24');
    _selectedUnit = e?.unit ?? 'kg';
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _estHoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'categoryId': widget.categoryId,
      'name': _nameCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text) ?? 0,
      'unit': _selectedUnit,
      'estHours': int.tryParse(_estHoursCtrl.text) ?? 24,
      'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'isActive': _isActive,
    };

    final notifier = ref.read(catalogProvider.notifier);
    final ok = widget.existing == null
        ? await notifier.addService(data)
        : await notifier.updateService(widget.existing!.id, data);

    if (mounted) {
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existing == null ? 'Layanan berhasil ditambahkan!' : 'Layanan diperbarui!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan. Coba lagi.'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(catalogProvider).isSaving;
    final isEdit = widget.existing != null;

    // Dapatkan nama kategori
    final cats = ref.watch(catalogProvider).categories;
    final catName = cats.firstWhere(
      (c) => c.id == widget.categoryId,
      orElse: () => ServiceCategory(id: '', name: 'Kategori'),
    ).name;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit Layanan' : 'Tambah Layanan',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            Text(
              'Kategori: $catName',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: isSaving ? null : _save,
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nama Layanan
              _buildLabel('Nama Layanan *'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama layanan wajib diisi' : null,
                decoration: _inputDeco('contoh: Cuci Kering Setrika Reguler'),
              ),
              const SizedBox(height: 18),

              // Harga & Satuan (berdampingan)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Harga (Rp) *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _priceCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Harga wajib diisi';
                            if ((double.tryParse(v) ?? 0) <= 0) return 'Harga harus > 0';
                            return null;
                          },
                          decoration: _inputDeco('7000'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Satuan *'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedUnit,
                          isExpanded: true,
                          onChanged: (v) => setState(() => _selectedUnit = v!),
                          decoration: _inputDeco(''),
                          items: _units
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u['value'],
                                  child: Text(
                                    u['label']!,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Estimasi Waktu
              _buildLabel('Estimasi Selesai (jam)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _estHoursCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDeco('24 (jam)'),
              ),
              const SizedBox(height: 18),

              // Deskripsi
              _buildLabel('Deskripsi (opsional)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: _inputDeco('Contoh: Termasuk pelembut dan pewangi premium'),
              ),
              const SizedBox(height: 20),

              // Status aktif
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tampilkan di POS Kasir', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                          SizedBox(height: 2),
                          Text('Layanan nonaktif tersembunyi dari kasir', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isActive,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ],
                ),
              ),

              // Preview harga
              if (_priceCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.price_check_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Rp ${_priceCtrl.text} / $_selectedUnit',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.danger)),
    );
  }
}
