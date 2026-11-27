import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/catalog_model.dart';
import '../../providers/catalog_provider.dart';
import 'category_form_screen.dart';
import 'service_form_screen.dart';

class CatalogManagementScreen extends ConsumerStatefulWidget {
  const CatalogManagementScreen({super.key});

  @override
  ConsumerState<CatalogManagementScreen> createState() =>
      _CatalogManagementScreenState();
}

class _CatalogManagementScreenState
    extends ConsumerState<CatalogManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(catalogProvider.notifier).fetchCatalog();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Manajemen Katalog Layanan',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Kategori'),
            Tab(text: 'Layanan / Produk'),
          ],
        ),
        actions: [
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
              tooltip: 'Refresh',
              onPressed: () => ref.read(catalogProvider.notifier).fetchCatalog(),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CategoryTab(state: state),
          _ServiceTab(state: state),
        ],
      ),
    );
  }
}

// ─── Tab Kategori ─────────────────────────────────────────────────────────────

class _CategoryTab extends ConsumerWidget {
  final CatalogState state;
  const _CategoryTab({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading && state.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (state.error != null && state.categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(state.error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.read(catalogProvider.notifier).fetchCatalog(),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tombol tambah
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Tambah Kategori Baru'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoryFormScreen()),
              ),
            ),
          ),
        ),
        // Daftar
        if (state.categories.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.category_rounded, size: 48, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Belum ada kategori layanan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tambahkan kategori seperti "Kiloan",\n"Satuan", "Express", dll.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(catalogProvider.notifier).fetchCatalog(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: state.categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _CategoryCard(cat: state.categories[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  final ServiceCategory cat;
  const _CategoryCard({required this.cat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = cat.colorHex != null
        ? Color(int.parse('FF${cat.colorHex!.replaceAll('#', '')}', radix: 16))
        : AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cat.isActive ? color.withOpacity(0.3) : AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.category_rounded, color: color, size: 22),
        ),
        title: Text(
          cat.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: cat.isActive ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
        subtitle: Text(
          '${cat.services.length} layanan${!cat.isActive ? ' • Nonaktif' : ''}',
          style: TextStyle(
            fontSize: 11,
            color: cat.isActive ? AppColors.textSecondary : AppColors.textMuted,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: cat.isActive,
              activeColor: AppColors.primary,
              onChanged: (val) => ref.read(catalogProvider.notifier).updateCategory(
                cat.id,
                {'isActive': val},
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.textSecondary),
              tooltip: 'Edit',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CategoryFormScreen(existing: cat)),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
              tooltip: 'Hapus',
              onPressed: () => _confirmDelete(context, ref, cat),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ServiceCategory cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Kategori?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Kategori "${cat.name}" dan semua layanannya akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ref.read(catalogProvider.notifier).deleteCategory(cat.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Kategori dihapus.' : 'Gagal menghapus kategori.'),
                    backgroundColor: ok ? AppColors.success : AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

// ─── Tab Layanan/Produk ───────────────────────────────────────────────────────

class _ServiceTab extends ConsumerStatefulWidget {
  final CatalogState state;
  const _ServiceTab({required this.state});

  @override
  ConsumerState<_ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends ConsumerState<_ServiceTab> {
  String? _selectedCatId;

  @override
  void didUpdateWidget(_ServiceTab old) {
    super.didUpdateWidget(old);
    // Reset jika kategori yang dipilih hilang
    if (_selectedCatId != null &&
        !widget.state.categories.any((c) => c.id == _selectedCatId)) {
      _selectedCatId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.state.categories;
    final selectedCat = cats.isEmpty
        ? null
        : cats.firstWhere(
            (c) => c.id == (_selectedCatId ?? cats.first.id),
            orElse: () => cats.first,
          );
    final services = selectedCat?.services ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter kategori
        if (cats.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: cats.map((cat) {
                  final isSel = (selectedCat?.id == cat.id);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat.name),
                      selected: isSel,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSel ? Colors.white : AppColors.textSecondary,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceSubtle,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: isSel ? AppColors.primary : AppColors.border),
                      ),
                      onSelected: (_) => setState(() => _selectedCatId = cat.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        // Tombol tambah
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                selectedCat != null
                    ? 'Tambah Layanan ke "${selectedCat.name}"'
                    : 'Tambah Layanan (buat kategori dulu)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedCat != null ? AppColors.accent : AppColors.border,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: selectedCat == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceFormScreen(categoryId: selectedCat.id),
                        ),
                      ),
            ),
          ),
        ),
        // Daftar layanan
        if (cats.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'Buat kategori dulu\nsebelum menambah layanan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else if (services.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_rounded, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Belum ada layanan di "${selectedCat?.name}"',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Klik tombol di atas untuk menambahkan.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(catalogProvider.notifier).fetchCatalog(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ServiceCard(svc: services[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  final ServiceItem svc;
  const _ServiceCard({required this.svc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = RegExp(r'(\d)(?=(\d{3})+(?!\d))');
    final priceStr = svc.price.toInt().toString().replaceAllMapped(fmt, (m) => '${m[1]}.');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: svc.isActive ? AppColors.border : AppColors.border.withOpacity(0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(
          svc.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: svc.isActive ? AppColors.textPrimary : AppColors.textMuted,
            decoration: svc.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          'Rp $priceStr / ${svc.unit}  •  Est. ${svc.estHours}jam${svc.description != null ? '\n${svc.description}' : ''}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        isThreeLine: svc.description != null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: svc.isActive,
              activeColor: AppColors.primary,
              onChanged: (_) => ref.read(catalogProvider.notifier).toggleServiceActive(svc),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.textSecondary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceFormScreen(categoryId: svc.categoryId, existing: svc),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Layanan?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('"${svc.name}" akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ref.read(catalogProvider.notifier).deleteService(svc.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Layanan dihapus.' : 'Gagal menghapus.'),
                    backgroundColor: ok ? AppColors.success : AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
