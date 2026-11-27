import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/string_utils.dart';
import '../../../../core/providers/app_refresh_provider.dart';
import '../../../auth/providers/auth_provider.dart';

class WhatsAppConversationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> conversation;
  final Function(Map<String, dynamic>) onTakeover;
  final Function(Map<String, dynamic>) onReturnToAi;

  const WhatsAppConversationScreen({
    super.key,
    required this.conversation,
    required this.onTakeover,
    required this.onReturnToAi,
  });

  @override
  ConsumerState<WhatsAppConversationScreen> createState() => _WhatsAppConversationScreenState();
}

class _WhatsAppConversationScreenState extends ConsumerState<WhatsAppConversationScreen> {
  static const Color waTealGreen = AppColors.primary;
  final ApiClient _api = ApiClient();
  List<dynamic> _messages = [];
  bool _isLoadingMessages = true;
  bool _isSending = false;
  final TextEditingController _replyCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMessages());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchMessages(silent: true),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Anggap pengguna dekat dengan bawah jika jarak ke bawah <= 100px
    final nearBottom = (maxScroll - currentScroll) <= 100;
    if (_isNearBottom != nearBottom) {
      _isNearBottom = nearBottom;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _replyCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    final activeBiz = ref.read(authProvider).activeBusiness;
    final convoId = widget.conversation['id']?.toString();
    if (activeBiz == null || convoId == null) {
      if (!silent && mounted) setState(() => _isLoadingMessages = false);
      return;
    }

    if (!silent) setState(() => _isLoadingMessages = true);
    try {
      final res = await _api.dio.get(
        '/businesses/${activeBiz.id}/conversations/$convoId/messages',
      );
      if (res.data['success'] == true && mounted) {
        final raw = (res.data['data'] as List?) ?? [];
        if (silent && raw.length == _messages.length) return;
        setState(() {
          _messages = raw.map((m) {
            final senderType = (m['senderType'] ?? 'CUSTOMER').toString().toUpperCase();
            final sender = senderType == 'CUSTOMER'
                ? 'customer'
                : (senderType == 'BOT' ? 'bot' : 'agent');
            final createdAt = (m['createdAt'] ?? '').toString();
            final timeStr = createdAt.length >= 16 ? createdAt.substring(11, 16) : '';
            return {
              'sender': sender,
              'text': (m['body'] ?? m['text'] ?? '').toString(),
              'time': timeStr,
            };
          }).toList();
          _isLoadingMessages = false;
        });
        // Hanya scroll otomatis jika pengguna memang sedang berada di bagian bawah
        // atau jika bukan silent polling (misal baru buka halaman pertama kali)
        if (!silent || _isNearBottom) {
          _scrollToBottom();
        }
      }
    } on DioException catch (e) {
      debugPrint('[Chat] fetchMessages error: ${e.response?.data}');
      if (mounted) {
        setState(() => _isLoadingMessages = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data?['message'] ?? 'Gagal memuat riwayat chat'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMessages = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    final activeBiz = ref.read(authProvider).activeBusiness;
    final convoId = widget.conversation['id']?.toString();
    if (activeBiz == null || convoId == null) return;

    setState(() => _isSending = true);
    try {
      final res = await _api.dio.post(
        '/businesses/${activeBiz.id}/conversations/$convoId/reply',
        data: {'message': text},
      );
      if (res.data['success'] == true && mounted) {
        _replyCtrl.clear();
        setState(() {
          _messages.add({
            'sender': 'agent',
            'text': text,
            'time': 'Baru saja',
          });
          widget.conversation['lastMessage'] = text;
          widget.conversation['status'] = 'HUMAN_HANDLING';
        });
        ref.read(appRefreshProvider.notifier).trigger();
        _scrollToBottom();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data?['message'] ?? 'Gagal mengirim pesan WhatsApp'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = widget.conversation['status'] ?? 'AI_HANDLING';
    final currentIsWaiting = currentStatus == 'WAITING_CS';
    final currentIsHuman = currentStatus == 'HUMAN_HANDLING';
    const waHeaderGreen = Color(0xFF075E54);
    const waTealGreen = Color(0xFF008069);
    const waAccentGreen = Color(0xFF25D366);

    return Scaffold(
      backgroundColor: const Color(0xFFEFE7DD), // WhatsApp Authentic Wallpaper Tint
      appBar: AppBar(
        elevation: 1,
        backgroundColor: waHeaderGreen,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 23),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFDFE5E7),
              child: Text(
                StringUtils.getInitial(widget.conversation['customerName']),
                style: const TextStyle(color: Color(0xFF4A5568), fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.conversation['customerName'] ?? widget.conversation['customerPhone'] ?? 'Pelanggan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: currentIsWaiting
                              ? const Color(0xFFEF4444)
                              : currentIsHuman
                                  ? const Color(0xFFF59E0B)
                                  : waAccentGreen,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          currentIsWaiting
                              ? 'Menunggu Tanggapan CS'
                              : currentIsHuman
                                  ? 'CS Kasir Sedang Menangani'
                                  : 'Bot AI Menjawab Otomatis',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w400),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 21),
            tooltip: 'Panggil',
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 21),
            tooltip: 'Menu Obrolan',
            onSelected: (val) {
              if (val == 'TAKEOVER') {
                widget.onTakeover(widget.conversation);
                setState(() => widget.conversation['status'] = 'HUMAN_HANDLING');
              } else if (val == 'RETURN_AI') {
                widget.onReturnToAi(widget.conversation);
                setState(() => widget.conversation['status'] = 'AI_HANDLING');
              } else if (val == 'REFRESH') {
                _fetchMessages();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: (currentIsWaiting || !currentIsHuman) ? 'TAKEOVER' : 'RETURN_AI',
                child: Row(
                  children: [
                    Icon(
                      (currentIsWaiting || !currentIsHuman) ? Icons.support_agent_rounded : Icons.smart_toy_rounded,
                      size: 18,
                      color: (currentIsWaiting || !currentIsHuman) ? const Color(0xFFD97706) : waTealGreen,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      (currentIsWaiting || !currentIsHuman) ? 'Ambil Alih Obrolan (CS)' : 'Kembalikan ke Bot AI',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'REFRESH',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF64748B)),
                    SizedBox(width: 10),
                    Text('Segarkan Pesan', style: TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Takeover / Handback Banner Ringkas (WhatsApp Notice Bubble style)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: currentIsWaiting
                  ? const Color(0xFFFEE2E2)
                  : currentIsHuman
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFE0F2FE),
              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(
                  currentIsWaiting
                      ? Icons.priority_high_rounded
                      : currentIsHuman
                          ? Icons.support_agent_rounded
                          : Icons.smart_toy_rounded,
                  size: 16,
                  color: currentIsWaiting
                      ? const Color(0xFFDC2626)
                      : currentIsHuman
                          ? const Color(0xFFD97706)
                          : waTealGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentIsWaiting
                        ? 'Pelanggan butuh bantuan CS'
                        : currentIsHuman
                            ? 'Mode CS Manual aktif'
                            : 'Bot AI menjawab 24/7',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (currentIsWaiting || !currentIsHuman) {
                        widget.onTakeover(widget.conversation);
                        widget.conversation['status'] = 'HUMAN_HANDLING';
                      } else {
                        widget.onReturnToAi(widget.conversation);
                        widget.conversation['status'] = 'AI_HANDLING';
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (currentIsWaiting || !currentIsHuman)
                          ? const Color(0xFFDC2626)
                          : waTealGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      (currentIsWaiting || !currentIsHuman) ? 'Ambil Alih' : 'Ke AI',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages List View
          Expanded(
            child: _isLoadingMessages
                ? const Center(child: CircularProgressIndicator(color: waTealGreen))
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada riwayat pesan.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final msg = _messages[i];
                final isCust = msg['sender'] == 'customer';
                final isBot = msg['sender'] == 'bot';

                return Align(
                  alignment: isCust ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    decoration: BoxDecoration(
                      color: isCust
                          ? Colors.white
                          : (isBot ? const Color(0xFFE7FFDB) : const Color(0xFFDCF8C6)),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(10),
                        topRight: const Radius.circular(10),
                        bottomLeft: isCust ? Radius.zero : const Radius.circular(10),
                        bottomRight: isCust ? const Radius.circular(10) : Radius.zero,
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isCust)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isBot ? Icons.smart_toy_rounded : Icons.person_rounded, size: 11, color: waTealGreen),
                                const SizedBox(width: 3),
                                Text(
                                  isBot ? 'mitraCS AI' : 'CS Kasir',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: waTealGreen),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          msg['text'] ?? '',
                          style: const TextStyle(fontSize: 14.5, color: Color(0xFF111B21), height: 1.3),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              msg['time'] ?? '10:00',
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF667781)),
                            ),
                            if (!isCust) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF53BDEB)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom WhatsApp Message Input Bar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              color: Colors.transparent,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.sentiment_satisfied_alt_rounded, color: Color(0xFF8696A0), size: 22),
                            onPressed: () {},
                          ),
                          Expanded(
                            child: TextField(
                              controller: _replyCtrl,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                              decoration: const InputDecoration(
                                hintText: 'Ketik pesan...',
                                hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 15),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF8696A0), size: 22),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF8696A0), size: 22),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: waTealGreen,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
