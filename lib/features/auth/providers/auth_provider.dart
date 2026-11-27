import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:multibiz_mobile/core/network/api_client.dart';
import 'package:multibiz_mobile/features/auth/data/auth_model.dart';
import 'package:dio/dio.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final bool needsOnboarding;
  final UserModel? user;
  final List<BusinessModel> businesses;
  final BusinessModel? activeBusiness;
  final String? errorMessage;

  AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.needsOnboarding = false,
    this.user,
    this.businesses = const [],
    this.activeBusiness,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? needsOnboarding,
    UserModel? user,
    List<BusinessModel>? businesses,
    BusinessModel? activeBusiness,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      user: user ?? this.user,
      businesses: businesses ?? this.businesses,
      activeBusiness: activeBusiness ?? this.activeBusiness,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  AuthState build() {
    checkSession();
    return AuthState();
  }

  Future<bool> _checkNeedsOnboarding(UserModel user, BusinessModel? activeBiz) async {
    if (user.isPlatformSuperAdmin || activeBiz == null) return false;
    try {
      final subRes = await _apiClient.dio.get('/businesses/${activeBiz.id}/subscription');
      if (subRes.data['success'] == true && subRes.data['data'] == null) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> checkSession() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token != null) {
      state = state.copyWith(isLoading: true);
      try {
        final res = await _apiClient.dio.get('/auth/me');
        if (res.data['success'] == true) {
          final user = UserModel.fromJson(res.data['data']);
          final bizRes = await _apiClient.dio.get('/businesses');
          final List<BusinessModel> list = (bizRes.data['data'] as List)
              .map((b) => BusinessModel.fromJson(b))
              .toList();

          final activeBiz = list.isNotEmpty ? list.first : null;
          if (activeBiz != null) {
            await _storage.write(key: 'active_business_id', value: activeBiz.id);
          }

          final needsOnboarding = await _checkNeedsOnboarding(user, activeBiz);

          state = state.copyWith(
            isLoading: false,
            isAuthenticated: true,
            needsOnboarding: needsOnboarding,
            user: user,
            businesses: list,
            activeBusiness: activeBiz,
          );
        } else {
          state = state.copyWith(isLoading: false);
        }
      } catch (_) {
        await _storage.deleteAll();
        state = state.copyWith(isLoading: false, isAuthenticated: false, needsOnboarding: false);
      }
    }
  }

  Future<bool> loginWithGoogleSSO({
    String? idToken,
    String? simulatedEmail,
    String? fullName,
    String? avatarUrl,
    String? businessName,
    String? category,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final tokenToSend = idToken ?? 'sim_${simulatedEmail?.split('@').first ?? 'owner_laundry'}';

      final res = await _apiClient.dio.post('/auth/google-sso', data: {
        'idToken': tokenToSend,
        if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
        'businessName': businessName ?? 'Barokah Clean Laundry',
        'category': category ?? 'LAUNDRY',
        'initialOutletName': 'Cabang Utama (Pusat)',
      });

      if (res.data['success'] == true) {
        final data = res.data['data'];
        final token = data['token'];
        await _storage.write(key: 'jwt_token', value: token);

        final user = UserModel.fromJson(data['user']);
        List<BusinessModel> bizList = [];
        BusinessModel? activeBiz;

        if (data['isNewUser'] == true) {
          activeBiz = BusinessModel.fromJson(data['business']);
          bizList = [activeBiz];
        } else {
          bizList = (data['memberships'] as List)
              .map((m) => BusinessModel.fromJson({
                    'role': m['role'],
                    ...m['business'],
                  }))
              .toList();
          activeBiz = bizList.isNotEmpty ? bizList.first : null;
        }

        if (activeBiz != null) {
          await _storage.write(key: 'active_business_id', value: activeBiz.id);
        }

        final needsOnboarding = await _checkNeedsOnboarding(user, activeBiz);

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          needsOnboarding: needsOnboarding,
          user: user,
          businesses: bizList,
          activeBusiness: activeBiz,
        );
        return true;
      }
      return false;
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.response?.data?['message'] ?? 'Gagal masuk dengan Google SSO',
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Terjadi kesalahan sistem',
      );
      return false;
    }
  }

  void switchBusiness(BusinessModel business) async {
    await _storage.write(key: 'active_business_id', value: business.id);
    state = state.copyWith(activeBusiness: business);
  }

  Future<void> refreshProfile() async {
    try {
      final res = await _apiClient.dio.get('/auth/me');
      if (res.data['success'] == true && res.data['data'] != null) {
        state = state.copyWith(user: UserModel.fromJson(res.data['data']));
      }

      final bizRes = await _apiClient.dio.get('/businesses');
      if (bizRes.data['success'] == true && bizRes.data['data'] is List) {
        final List<BusinessModel> list = (bizRes.data['data'] as List)
            .map((b) => BusinessModel.fromJson(b))
            .toList();

        final currentActiveId = state.activeBusiness?.id;
        final updatedActive = list.firstWhere(
          (b) => b.id == currentActiveId,
          orElse: () => list.isNotEmpty ? list.first : state.activeBusiness!,
        );

        state = state.copyWith(
          businesses: list,
          activeBusiness: updatedActive,
        );
      }
    } catch (_) {}
  }

  void updateActiveBusiness(BusinessModel updated) {
    final updatedList = state.businesses.map((b) => b.id == updated.id ? updated : b).toList();
    state = state.copyWith(
      activeBusiness: updated,
      businesses: updatedList,
    );
  }

  Future<String?> updateProfile({
    required String fullName,
    required String email,
    String? avatarUrl,
  }) async {
    try {
      final res = await _apiClient.dio.patch(
        '/auth/me',
        data: {
          'fullName': fullName.trim(),
          'email': email.trim(),
          'avatarUrl': (avatarUrl ?? '').trim(),
        },
      );
      if (res.data['success'] == true) {
        final data = res.data['data'];
        if (data['token'] != null) {
          await _storage.write(key: 'jwt_token', value: data['token']);
        }
        if (data['user'] != null) {
          state = state.copyWith(user: UserModel.fromJson(data['user']));
        }
        return null;
      }
      return res.data['message']?.toString() ?? 'Gagal memperbarui profil';
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? e.response?.data['message'] : null;
      if (msg is List && msg.isNotEmpty) return msg.first.toString();
      return msg?.toString() ?? e.message ?? 'Gagal memperbarui profil';
    } catch (e) {
      return 'Gagal memperbarui profil: $e';
    }
  }

  Future<String?> deleteProfile() async {
    try {
      final res = await _apiClient.dio.delete('/auth/me');
      if (res.data['success'] == true) {
        await logout();
        return null;
      }
      return res.data['message']?.toString() ?? 'Gagal menghapus profil';
    } on DioException catch (e) {
      return e.response?.data?['message']?.toString() ?? 'Gagal menghapus profil';
    } catch (_) {
      return 'Terjadi kesalahan saat menghapus profil';
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
