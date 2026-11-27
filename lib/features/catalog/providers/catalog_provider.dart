import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import 'package:multibiz_mobile/features/auth/providers/auth_provider.dart';
import '../data/catalog_model.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class CatalogState {
  final bool isLoading;
  final bool isSaving;
  final List<ServiceCategory> categories;
  final String? error;

  const CatalogState({
    this.isLoading = false,
    this.isSaving = false,
    this.categories = const [],
    this.error,
  });

  CatalogState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<ServiceCategory>? categories,
    String? error,
  }) {
    return CatalogState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      categories: categories ?? this.categories,
      error: error,
    );
  }

  List<ServiceItem> get allActiveServices =>
      categories.expand((c) => c.services.where((s) => s.isActive)).toList();
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class CatalogNotifier extends Notifier<CatalogState> {
  final ApiClient _api = ApiClient();

  @override
  CatalogState build() {
    return const CatalogState();
  }

  String? get _bizId => ref.read(authProvider).activeBusiness?.id;

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> fetchCatalog() async {
    if (_bizId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _api.dio.get('/businesses/$_bizId/catalog/categories');
      if (res.data['success'] == true) {
        final list = (res.data['data'] as List)
            .map((c) => ServiceCategory.fromJson(c))
            .toList();
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        state = state.copyWith(isLoading: false, categories: list);
      }
    } on DioException catch (e) {
      debugPrint('[Catalog] fetch error: ${e.response?.data}');
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['message'] ?? 'Gagal memuat katalog',
      );
    } catch (e) {
      debugPrint('[Catalog] fetch unexpected: $e');
      state = state.copyWith(isLoading: false, error: 'Terjadi kesalahan');
    }
  }

  // ── Kategori CRUD ──────────────────────────────────────────────────────────

  Future<bool> addCategory(Map<String, dynamic> data) async {
    if (_bizId == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.dio.post('/businesses/$_bizId/catalog/categories', data: data);
      if (res.data['success'] == true) {
        await fetchCatalog();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Catalog] addCategory error: $e');
      state = state.copyWith(isSaving: false);
      return false;
    }
  }

  Future<bool> updateCategory(String catId, Map<String, dynamic> data) async {
    if (_bizId == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.dio.put('/businesses/$_bizId/catalog/categories/$catId', data: data);
      if (res.data['success'] == true) {
        await fetchCatalog();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Catalog] updateCategory error: $e');
      state = state.copyWith(isSaving: false);
      return false;
    }
  }

  Future<bool> deleteCategory(String catId) async {
    if (_bizId == null) return false;
    try {
      final res = await _api.dio.delete('/businesses/$_bizId/catalog/categories/$catId');
      if (res.data['success'] == true) {
        await fetchCatalog();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Catalog] deleteCategory error: $e');
      return false;
    }
  }

  // ── Layanan/Produk CRUD ────────────────────────────────────────────────────

  Future<bool> addService(Map<String, dynamic> data) async {
    if (_bizId == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.dio.post('/businesses/$_bizId/catalog/services', data: data);
      if (res.data['success'] == true) {
        await fetchCatalog();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Catalog] addService error: $e');
      state = state.copyWith(isSaving: false);
      return false;
    }
  }

  Future<bool> updateService(String svcId, Map<String, dynamic> data) async {
    if (_bizId == null) return false;
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.dio.put('/businesses/$_bizId/catalog/services/$svcId', data: data);
      if (res.data['success'] == true) {
        await fetchCatalog();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Catalog] updateService error: $e');
      state = state.copyWith(isSaving: false);
      return false;
    }
  }

  Future<bool> deleteService(String svcId) async {
    if (_bizId == null) return false;
    try {
      final res = await _api.dio.delete('/businesses/$_bizId/catalog/services/$svcId');
      if (res.data['success'] == true) {
        await fetchCatalog();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Catalog] deleteService error: $e');
      return false;
    }
  }

  Future<bool> toggleServiceActive(ServiceItem svc) async {
    return updateService(svc.id, {'isActive': !svc.isActive});
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final catalogProvider = NotifierProvider<CatalogNotifier, CatalogState>(() {
  return CatalogNotifier();
});
