import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/sembast_cache.dart';
import 'package:preconnect/pages/ui_kit.dart';

Future<void> showAiChatBottomSheet(
  BuildContext context, {
  String? initialMessage,
}) {
  final resetCounter = ValueNotifier<int>(0);
  return showBracuBottomSheet<void>(
    context,
    title: 'Ask PreConnect',
    subtitle: 'Get help from Hosted AI',
    maxHeightFactor: 0.84,
    actions: [
      ValueListenableBuilder<int>(
        valueListenable: resetCounter,
        builder: (context, value, child) => IconButton(
          onPressed: () async {
            final shouldClear = await showBracuConfirmationDialog(
              context,
              icon: Icons.delete_outline_rounded,
              title: 'Delete chat?',
              message: 'This will remove all saved AI chat messages on this device.',
              confirmLabel: 'Delete',
              confirmColor: BracuPalette.danger,
            );
            if (!shouldClear) return;
            await _AiChatLocalStore.clear();
            resetCounter.value++;
          },
          icon: Icon(
            Icons.delete_outline_rounded,
            color: BracuPalette.textSecondary(context),
          ),
          tooltip: 'Delete chat',
        ),
      ),
    ],
    builder: (sheetContext, textPrimary, textSecondary) =>
        AiChatPanel(
          initialMessage: initialMessage,
          resetListenable: resetCounter,
        ),
  );
}

class _AiChatLocalStore {
  _AiChatLocalStore._();

  static const String _cacheKey = 'ai_chat_messages_v1';

  static Future<List<Map<String, dynamic>>> load() async {
    final raw = await SembastCache().getJsonList(_cacheKey);
    if (raw == null) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  static Future<void> save(List<_ChatMessage> messages) async {
    await SembastCache().setJson(
      _cacheKey,
      messages
          .map(
            (message) => {
              'role': message.role.name,
              'text': message.text,
            },
          )
          .toList(),
    );
  }

  static Future<void> clear() => SembastCache().remove(_cacheKey);
}

class AiChatEntryCard extends StatefulWidget {
  const AiChatEntryCard({super.key});

  @override
  State<AiChatEntryCard> createState() => _AiChatEntryCardState();
}

class _AiChatEntryCardState extends State<AiChatEntryCard> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = _fieldKey.currentContext;
      if (context == null || !mounted) return;
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.22,
      );
    });
  }

  Future<void> _open() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await showAiChatBottomSheet(
      context,
      initialMessage: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final iconColor = const Color(0xFF7C56FF);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: KeyedSubtree(
          key: _fieldKey,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) {
              if (_hasText) _open();
            },
            decoration: InputDecoration(
              hintText: 'Ask anything academic...',
              hintStyle: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              isCollapsed: true,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  onTap: _hasText ? _open : null,
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      _hasText
                          ? Icons.send_rounded
                          : Icons.auto_awesome_rounded,
                      color: _hasText ? iconColor : iconColor,
                      size: 17,
                    ),
                  ),
                ),
              ),
            ),
            textAlignVertical: TextAlignVertical.bottom,
            style: TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class AiChatPanel extends StatefulWidget {
  const AiChatPanel({
    super.key,
    this.initialMessage,
    this.resetListenable,
  });

  final String? initialMessage;
  final ValueListenable<int>? resetListenable;

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  bool _isSending = false;
  bool _didSendInitialMessage = false;
  int? _selectedMessageIndex;

  @override
  void initState() {
    super.initState();
    widget.resetListenable?.addListener(_handleResetRequested);
    _restoreMessages();
  }

  @override
  void dispose() {
    widget.resetListenable?.removeListener(_handleResetRequested);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreMessages() async {
    final raw = await _AiChatLocalStore.load();
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(
          raw
              .map(_ChatMessage.fromJson)
              .where((message) => message.text.trim().isNotEmpty),
        );
    });
    final initialMessage = widget.initialMessage?.trim();
    if (!_didSendInitialMessage &&
        initialMessage != null &&
        initialMessage.isNotEmpty) {
      _didSendInitialMessage = true;
      _send(initialMessage);
      return;
    }
    _scrollToBottom();
  }

  Future<void> _persistMessages() async {
    await _AiChatLocalStore.save(_messages);
  }

  void _handleResetRequested() {
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _selectedMessageIndex = null;
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _isSending) return;
    final history = _messages
        .where((message) => message.role != _ChatRole.system)
        .map((message) => {
              'role': message.role == _ChatRole.assistant
                  ? 'assistant'
                  : 'user',
              'content': message.text,
            })
        .toList();
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: _ChatRole.user, text: text));
      _isSending = true;
      _selectedMessageIndex = null;
    });
    await _persistMessages();
    _scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.aiChatBase}${ApiConfig.aiChatPath}'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'message': text,
              'history': history,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('AI service returned ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = '${data['reply'] ?? ''}'.trim();
      if (reply.isEmpty) {
        throw Exception('Empty AI reply');
      }
      setState(() {
        _messages.add(_ChatMessage(role: _ChatRole.assistant, text: reply));
        _selectedMessageIndex = null;
      });
      await _persistMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _ChatMessage(
            role: _ChatRole.assistant,
            text: 'Sorry, AI chat is unavailable right now. Please try again.',
          ),
        );
        _selectedMessageIndex = null;
      });
      await _persistMessages();
      if (mounted) {
        showAppSnackBar(context, 'Unable to get AI response');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Expanded(
            child: BracuCard(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (_isSending && index == _messages.length) {
                      return const _TypingBubble();
                    }
                    final message = _messages[index];
                    return _MessageBubble(
                      message: message,
                      showCopyAction: _selectedMessageIndex == index,
                      onToggleSelected: () {
                        setState(() {
                          _selectedMessageIndex =
                              _selectedMessageIndex == index ? null : index;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          BracuCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_isSending,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ask anything academic...',
                        hintStyle: TextStyle(
                          color: BracuPalette.textSecondary(context),
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        color: BracuPalette.textPrimary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _isSending ? null : _send,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _isSending
                            ? Icons.hourglass_top_rounded
                            : Icons.send_rounded,
                        size: 18,
                        color: BracuPalette.textPrimary(
                          context,
                        ).withValues(alpha: _isSending ? 0.4 : 0.92),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: TextStyle(
                color: BracuPalette.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              children: [
                const TextSpan(text: 'Chats stay on this device. '),
                TextSpan(
                  text: 'Support PreConnect AI.',
                  style: const TextStyle(
                    color: BracuPalette.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => showBracuFundingSupportSheet(context),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

enum _ChatRole { user, assistant, system }

class _ChatMessage {
  const _ChatMessage({required this.role, required this.text});

  final _ChatRole role;
  final String text;

  factory _ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawRole = '${json['role'] ?? ''}'.trim();
    final role = _ChatRole.values.cast<_ChatRole?>().firstWhere(
          (value) => value?.name == rawRole,
          orElse: () => _ChatRole.assistant,
        )!;
    return _ChatMessage(
      role: role,
      text: '${json['text'] ?? ''}',
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showCopyAction,
    required this.onToggleSelected,
  });

  final _ChatMessage message;
  final bool showCopyAction;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _ChatRole.user;
    final bubbleColor = isUser
        ? BracuPalette.primary
        : BracuPalette.card(context).withValues(alpha: 0.84);
    final textColor = isUser ? Colors.white : BracuPalette.textPrimary(context);
    final borderColor = isUser
        ? BracuPalette.primary
        : BracuPalette.textSecondary(context).withValues(alpha: 0.16);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: InkWell(
          onTap: onToggleSelected,
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isUser && showCopyAction)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => copyToClipboard(context, message.text),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: Icon(
                        Icons.content_copy_rounded,
                        size: 14,
                        color: BracuPalette.textSecondary(context).withValues(
                          alpha: 0.68,
                        ),
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  child: _ChatFormattedText(
                    text: message.text,
                    color: textColor,
                    isUser: isUser,
                  ),
                ),
              ),
              if (!isUser && showCopyAction)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: InkWell(
                    onTap: () => copyToClipboard(context, message.text),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: Icon(
                        Icons.content_copy_rounded,
                        size: 14,
                        color: BracuPalette.textSecondary(context).withValues(
                          alpha: 0.68,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatFormattedText extends StatelessWidget {
  const _ChatFormattedText({
    required this.text,
    required this.color,
    required this.isUser,
  });

  final String text;
  final Color color;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: color,
      fontSize: 13,
      fontWeight: isUser ? FontWeight.w600 : FontWeight.w400,
      height: 1.4,
    );
    return Text(_normalize(text), style: baseStyle);
  }

  String _normalize(String value) {
    final lines = value.split('\n').map((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('* ')) {
        return '${line.substring(0, line.length - trimmed.length)}• ${trimmed.substring(2)}';
      }
      return line;
    }).toList();
    return lines.join('\n').replaceAll('**', '');
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = BracuPalette.textSecondary(context).withValues(alpha: 0.92);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: BracuPalette.card(context).withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: BracuPalette.textSecondary(context).withValues(alpha: 0.16),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = ((progress + index * 0.18) % 1.0);
                final active = phase < 0.5;
                final scale = active ? 0.72 + (phase / 0.5) * 0.5 : 1.22 - ((phase - 0.5) / 0.5) * 0.5;
                final opacity = active ? 0.34 + (phase / 0.5) * 0.66 : 1.0 - ((phase - 0.5) / 0.5) * 0.5;
                return Padding(
                  padding: EdgeInsets.only(right: index == 2 ? 0 : 5),
                  child: Opacity(
                    opacity: opacity.clamp(0.28, 1.0),
                    child: Transform.scale(
                      scale: scale.clamp(0.72, 1.22),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
