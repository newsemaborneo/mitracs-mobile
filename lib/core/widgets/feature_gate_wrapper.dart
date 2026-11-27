import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/app_policy_provider.dart';
import '../../features/subscription/presentation/screens/owner_onboarding_plan_screen.dart';

class FeatureGateWrapper extends ConsumerWidget {
  final Widget child;
  final bool Function(AppPolicyModel policy) isAllowed;
  final String featureName;

  const FeatureGateWrapper({
    super.key,
    required this.child,
    required this.isAllowed,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policyAsync = ref.watch(appPolicyProvider);

    return policyAsync.when(
      loading: () => child,
      error: (_, __) => child,
      data: (policy) {
        if (isAllowed(policy)) {
          return child;
        }

        // Tampilan Terkunci Modern (Server-Driven View Only)
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: AppColors.warning,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '$featureName Terkunci',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      policy.lockMessage ??
                          'Fitur ini hanya dapat digunakan saat paket langganan usaha aktif.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status: ${policy.subscriptionStatus}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                        label: Text(
                          policy.actionButtonText ?? 'Pilih / Perpanjang Paket',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OwnerOnboardingPlanScreen(
                                ownerEmail: '',
                                isFromSettings: true,
                              ),
                            ),
                          ).then((_) {
                            ref.read(appPolicyProvider.notifier).fetchPolicy();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
