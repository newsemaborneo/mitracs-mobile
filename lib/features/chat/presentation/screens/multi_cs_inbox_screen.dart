import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/string_utils.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../../core/widgets/app_state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';
import 'whatsapp_conversation_screen.dart';

class MultiCsInboxScreen extends ConsumerStatefulWidget {
  const MultiCsInboxScreen({super.key});

  @override
  ConsumerState<MultiCsInboxScreen> createState() => _MultiCsInboxScreenState();
}

class _MultiCsInboxScreenState extends ConsumerState<MultiCsInboxScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = false;
  String? _errorMessage;
  String _selectedFilter = 'ALL'; // ALL, WAITING_CS, AI_HANDLING, HUMAN_HANDLING
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearchOpen = false;

  List<dynamic> _conversations = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchConversations());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _fetchConversations(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchConversations({bool silent = false}) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final res = await _api.dio.get('/businesses/${activeBiz.id}/conversations');
      if (res.data['success'] == true && mounted) {
        setState(() {
          _conversations = (res.data['data'] as List?) ?? [];
        });
      }
    } on DioException catch (e) {
      debugPrint('[Inbox] DioException: ${e.response?.data}');
      if (!silent && mounted) {
        setState(() {
          _errorMessage = e.response?.data?['message'] ?? 'Gagal memuat percakapan dari server';
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Terjadi kesalahan saat memuat inbox');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _takeoverChat(Map<String, dynamic> convo) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz != null && convo['id'] != null) {
      try {
        await _api.dio.post(
          '/businesses/${activeBiz.id}/conversations/${convo['id']}/takeover',
        );
      } catch (e) {
        debugPrint('[Inbox] takeover error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      convo['status'] = 'HUMAN_HANDLING';
      convo['unreadCount'] = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.pan_tool_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Obrolan diambil alih CS! AI dinonaktifkan sementara.'),
          ],
        ),
        backgroundColor: const Color(0xFF008069),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _returnToAi(Map<String, dynamic> convo) {
    setState(() {
      convo['status'] = 'AI_HANDLING';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Obrolan dikembalikan ke AI mitraCS otomatis.'),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<dynamic> get _filteredConversations {
    return _conversations.where((c) {
      final matchesSearch = _searchQuery.isEmpty ||
          (c['customerName']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (c['customerPhone']?.toString().contains(_searchQuery) ?? false) ||
          (c['lastMessage']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      if (!matchesSearch) return false;

      if (_selectedFilter == 'ALL') return true;
      if (_selectedFilter == 'WAITING_CS') return c['status'] == 'WAITING_CS';
      if (_selectedFilter == 'AI_HANDLING') return c['status'] == 'AI_HANDLING';
      if (_selectedFilter == 'HUMAN_HANDLING') return c['status'] == 'HUMAN_HANDLING';
      return true;
    }).toList();
  }

  bool _isBulkUpdating = false;

  Future<void> _bulkSwitchMode(String mode) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    if (activeBiz == null || _isBulkUpdating) return;

    setState(() => _isBulkUpdating = true);
    try {
      final res = await _api.dio.post(
        '/businesses/${activeBiz.id}/conversations/bulk-mode',
        data: {'mode': mode},
      );
      if (mounted) {
        final msg = res.data['message']?.toString() ?? 'Berhasil memperbarui mode chat';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
      await _fetchConversations(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah mode: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBulkUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(appRefreshProvider, (_, __) => _fetchConversations());
    ref.listen(authProvider, (prev, next) {
      if (prev?.activeBusiness?.id != next.activeBusiness?.id && next.activeBusiness != null) {
        _fetchConversations();
      }
    });

    // Unified Brand Theme Colors
    const waHeaderGreen = Color(0xFF075E54);
    const waTealGreen = Color(0xFF008069);
    const waLightGreen = Color(0xFF25D366);

    final waitingCount = _conversations.where((c) => c['status'] == 'WAITING_CS').length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: waHeaderGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 16,
        title: _isSearchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Cari pesan atau nama pelanggan...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text(
                'WhatsApp CS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearchOpen ? Icons.close_rounded : Icons.search_rounded, color: Colors.white),
            tooltip: 'Cari',
            onPressed: () {
              setState(() {
                if (_isSearchOpen) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                  _isSearchOpen = false;
                } else {
                  _isSearchOpen = true;
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            tooltip: 'Menu',
            onSelected: (val) {
              if (val == 'REFRESH') {
                _fetchConversations();
              } else if (val == 'TO_HUMAN') {
                _bulkSwitchMode('HUMAN_HANDLING');
              } else if (val == 'TO_AI') {
                _bulkSwitchMode('AI_HANDLING');
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'REFRESH',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF475569)),
                    SizedBox(width: 10),
                    Text('Segarkan Pesan', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'TO_HUMAN',
                child: Row(
                  children: [
                    Icon(Icons.support_agent_rounded, size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 10),
                    Text('Alihkan Semua ke CS', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'TO_AI',
                child: Row(
                  children: [
                    Icon(Icons.smart_toy_rounded, size: 18, color: waTealGreen),
                    SizedBox(width: 10),
                    Text('Alihkan Semua ke AI', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Sub-Bar (WhatsApp Style Filter Pills)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterPill('ALL', 'Semua (${_conversations.length})'),
                  const SizedBox(width: 6),
                  _buildFilterPill(
                    'WAITING_CS',
                    'Butuh CS ($waitingCount)',
                    isAlert: waitingCount > 0,
                  ),
                  const SizedBox(width: 6),
                  _buildFilterPill('AI_HANDLING', 'Bot AI'),
                  const SizedBox(width: 6),
                  _buildFilterPill('HUMAN_HANDLING', 'CS Aktif'),
                ],
              ),
            ),
          ),

          // Chat List View
          Expanded(
            child: _isLoading && _conversations.isEmpty
                ? const LoadingListPlaceholder()
                : _errorMessage != null && _conversations.isEmpty
                    ? ErrorStateWidget(message: _errorMessage!, onRetry: _fetchConversations)
                    : _filteredConversations.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _fetchConversations,
                            color: waTealGreen,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _filteredConversations.length,
                              separatorBuilder: (ctx, idx) => const Divider(
                                height: 1,
                                thickness: 0.6,
                                indent: 82,
                                endIndent: 16,
                                color: Color(0xFFE2E8F0),
                              ),
                              itemBuilder: (ctx, i) {
                                final convo = _filteredConversations[i];
                                return _buildWhatsAppChatTile(convo);
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: waLightGreen,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kirim pesan atau broadcast via WhatsApp'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: const Icon(Icons.chat_rounded, size: 24),
      ),
    );
  }

  Widget _buildFilterPill(String filterKey, String label, {bool isAlert = false}) {
    final isSelected = _selectedFilter == filterKey;
    const waTealGreen = Color(0xFF008069);

    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isAlert ? const Color(0xFFFEF2F2) : const Color(0xFFE8F5E9))
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (isAlert ? const Color(0xFFEF4444) : waTealGreen)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? (isAlert ? const Color(0xFFDC2626) : waTealGreen)
                : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsAppChatTile(Map<String, dynamic> convo) {
    final status = convo['status'] ?? 'AI_HANDLING';
    final isWaiting = status == 'WAITING_CS';
    final isHuman = status == 'HUMAN_HANDLING';
    final unread = convo['unreadCount'] ?? 0;
    const waTealGreen = Color(0xFF008069);
    const waLightGreen = Color(0xFF25D366);

    return Material(
      color: isWaiting ? const Color(0xFFFEF2F2).withOpacity(0.4) : Colors.transparent,
      child: InkWell(
        onTap: () => _openWhatsAppChatDetailModal(convo),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
            // WhatsApp Contact Avatar with Status Indicator
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFFE2E8F0),
                  child: Text(
                    StringUtils.getInitial(convo['customerName']),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF334155)),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isWaiting
                          ? const Color(0xFFEF4444)
                          : isHuman
                              ? const Color(0xFFF59E0B)
                              : waTealGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      isWaiting
                          ? Icons.priority_high_rounded
                          : isHuman
                              ? Icons.person_rounded
                              : Icons.smart_toy_rounded,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Chat Message Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Name & Timestamp
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          convo['customerName'] ?? convo['customerPhone'] ?? 'Pelanggan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        convo['updatedAt'] ?? 'Baru saja',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                          color: unread > 0 ? waLightGreen : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Row 2: Message preview with checkmark & Unread Badge
                  Row(
                    children: [
                      if (status == 'AI_HANDLING') ...[
                        const Icon(Icons.smart_toy_outlined, size: 14, color: waTealGreen),
                        const SizedBox(width: 4),
                      ] else if (isHuman) ...[
                        const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          convo['lastMessage'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0 ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isWaiting)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'BUTUH CS',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFDC2626)),
                          ),
                        )
                      else if (unread > 0)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: waLightGreen,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                    ],
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

  void _openWhatsAppChatDetailModal(Map<String, dynamic> convo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WhatsAppConversationScreen(
          conversation: convo,
          onTakeover: _takeoverChat,
          onReturnToAi: _returnToAi,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tidak ada obrolan WhatsApp',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Obrolan dari pelanggan WhatsApp akan ditampilkan di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
