import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';

class AppUpdateChecker {
  static bool _hasChecked = false;

  /// Cek versi aplikasi saat pertama kali user masuk ke Home
  static Future<void> checkForUpdate(BuildContext context) async {
    if (_hasChecked) return;
    _hasChecked = true;

    try {
      final apiClient = ApiClient();
      final res = await apiClient.dio.get('/app-version');
      if (res.data['success'] != true) return;

      final data = res.data['data'];
      final latestCode = data['latestVersionCode'] as int? ?? 1;
      final latestName = data['latestVersionName'] as String? ?? '1.0.0';
      final downloadUrl = data['downloadUrl'] as String? ?? 'https://mitracsai.my.id/download/multibiz-latest.apk';
      final releaseNotes = data['releaseNotes'] as String? ?? 'Pembaruan aplikasi mitraCS.ai tersedia.';
      final isForceUpdate = data['forceUpdate'] as bool? ?? false;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (latestCode > currentCode && context.mounted) {
        _showUpdateDialog(
          context,
          currentVersion: packageInfo.version,
          latestVersion: latestName,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
          isForceUpdate: isForceUpdate,
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateChecker] Lewati cek update: $e');
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl,
    required bool isForceUpdate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (dialogCtx) => PopScope(
        canPop: !isForceUpdate,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pembaruan Tersedia 🚀',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Versi $latestVersion sudah siap diunduh (versi Anda: $currentVersion)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    releaseNotes,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (!isForceUpdate) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.borderDark),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Nanti Saja',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final uri = Uri.parse(downloadUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Update Sekarang',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
