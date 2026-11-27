import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/catalog_model.dart';
import '../../providers/catalog_provider.dart';

class CategoryFormScreen extends ConsumerStatefulWidget {
  final ServiceCategory? existing;
  const CategoryFormScreen({super.key, this.existing});

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  String _selectedColor = '#0284C7';
  bool _isActive = true;

  // Pilihan warna preset
  final List<Map<String, String>> _colorOptions = [
    {'label': 'Biru', 'hex': '#0284C7'},
    {'label': 'Hijau', 'hex': '#16A34A'},
    {'label': 'Oranye', 'hex': '#EA580C'},
    {'label': 'Ungu', 'hex': '#7C3AED'},
    {'label': 'Merah', 'hex': '#DC2626'},
    {'label': 'Teal', 'hex': '#0D9488'},
    {'label': 'Navy', 'hex': '#0F3B5F'},
    {'label': 'Kuning', 'hex': '#D97706'},
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _selectedColor = widget.existing?.colorHex ?? '#0284C7';
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'name': _nameCtrl.text.trim(),
      'colorHex': _selectedColor,
      'isActive': _isActive,
    };

    final notifier = ref.read(catalogProvider.notifier);
    final ok = widget.existing == null
        ? await notifier.addCategory(data)
        : await notifier.updateCategory(widget.existing!.id, data);

    if (mounted) {
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existing == null ? 'Kategori berhasil ditambahkan!' : 'Kategori diperbarui!'),
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

    // Preview warna yang dipilih
    final previewColor = Color(
      int.parse('FF${_selectedColor.replaceAll('#', '')}', radix: 16),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isEdit ? 'Edit Kategori' : 'Tambah Kategori',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
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
              // Preview card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: previewColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: previewColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: previewColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.category_rounded, color: previewColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameCtrl.text.isEmpty ? 'Nama Kategori' : _nameCtrl.text,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: previewColor),
                        ),
                        const Text('Preview tampilan di POS', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nama
              const Text('Nama Kategori *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                decoration: InputDecoration(
                  hintText: 'contoh: Kiloan, Satuan, Express, Bedding...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),

              // Warna
              const Text('Warna Kategori', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colorOptions.map((opt) {
                  final c = Color(int.parse('FF${opt['hex']!.replaceAll('#', '')}', radix: 16));
                  final isSel = _selectedColor == opt['hex'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = opt['hex']!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSel ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSel
                            ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]
                            : [],
                      ),
                      child: isSel
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

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
                          Text('Aktifkan Kategori', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                          SizedBox(height: 2),
                          Text('Kategori nonaktif tidak tampil di POS Kasir', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
            ],
          ),
        ),
      ),
    );
  }
}
