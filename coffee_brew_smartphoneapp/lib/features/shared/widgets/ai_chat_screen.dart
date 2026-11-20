import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/claude_api.dart';

/// AI（Sonnet 5.5）と相談する画面。フレーバーホイールと抽出の詳細画面で使う。
///
/// AI の返事に ```[actionTag] { JSON } ``` の形の提案が含まれていると、その下に
/// [actionLabel] のボタンを出し、押すと [onAction] にその JSON を渡す（レシピの保存など）。
class AiChatScreen extends StatefulWidget {
  final String title;

  /// AI への前提（いま見ている抽出の記録やフレーバーの一覧など）
  final String systemPrompt;

  /// 最初に出す一言
  final String intro;

  /// 入力の例（タップでそのまま送る）
  final List<String> suggestions;

  final String? actionTag;
  final String actionLabel;

  /// 提案を反映する。成功したら画面に出す文を返す（失敗は例外）
  final Future<String> Function(Map<String, dynamic> json)? onAction;

  const AiChatScreen({
    super.key,
    required this.title,
    required this.systemPrompt,
    required this.intro,
    this.suggestions = const [],
    this.actionTag,
    this.actionLabel = '反映する',
    this.onAction,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _Msg {
  final String role; // 'user' | 'assistant' | 'error'
  final String text;
  bool applied = false;
  _Msg(this.role, this.text);
}

class _AiChatScreenState extends State<AiChatScreen> {
  final List<_Msg> _msgs = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  RegExp? get _blockRe => widget.actionTag == null
      ? null
      : RegExp('```${RegExp.escape(widget.actionTag!)}\\s*([\\s\\S]*?)```');

  /// 返事の本文（提案の JSON は除く）と提案
  (String, Map<String, dynamic>?) _split(String text) {
    final re = _blockRe;
    if (re == null) return (text.trim(), null);
    final m = re.firstMatch(text);
    if (m == null) return (text.trim(), null);
    Map<String, dynamic>? json;
    try {
      final v = jsonDecode(m.group(1)!.trim());
      if (v is Map<String, dynamic>) json = v;
    } catch (_) {}
    final body = text.replaceRange(m.start, m.end, '').trim();
    return (body, json);
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg('user', t));
      _sending = true;
    });
    _scrollToEnd();
    try {
      final history = _msgs
          .where((m) => m.role != 'error')
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      final reply = await ClaudeApi.send(
        system: widget.systemPrompt,
        messages: history,
        maxTokens: 1500,
      );
      if (!mounted) return;
      setState(() => _msgs.add(_Msg('assistant', reply)));
    } catch (e) {
      if (!mounted) return;
      // 失敗したときは、送った文を入力欄に戻して送り直せるようにする
      setState(() {
        _msgs.removeLast();
        _msgs.add(_Msg('error', '$e'));
        _input.text = t;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _apply(_Msg m, Map<String, dynamic> json) async {
    final f = widget.onAction;
    if (f == null) return;
    try {
      final done = await f(json);
      if (!mounted) return;
      setState(() => m.applied = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('反映できませんでした: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: AppTheme.display(fontSize: 20, color: BrewColors.espresso)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                children: [
                  _bubble(_Msg('assistant', widget.intro), intro: true),
                  if (!ClaudeApi.hasKey)
                    _note('APIキーが設定されていないため使えません（PC の set_api_key.bat で設定してください）'),
                  for (final m in _msgs) _bubble(m),
                  if (_sending)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('考えています…', style: TextStyle(color: BrewColors.mocha)),
                      ]),
                    ),
                  if (_msgs.isEmpty && widget.suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.suggestions
                          .map((s) => ActionChip(
                                label: Text(s),
                                onPressed: _sending ? null : () => _send(s),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: BrewColors.oat),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'AIに相談する',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(backgroundColor: BrewColors.caramel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: const TextStyle(color: BrewColors.terracotta, fontSize: 13)),
      );

  Widget _bubble(_Msg m, {bool intro = false}) {
    if (m.role == 'error') return _note(m.text);
    final mine = m.role == 'user';
    final (body, action) = mine || intro ? (m.text, null) : _split(m.text);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: mine ? BrewColors.caramel.withValues(alpha: 0.16) : BrewColors.foam,
          border: Border.all(color: BrewColors.oat),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(body,
                style: const TextStyle(fontSize: 14, height: 1.5, color: BrewColors.espresso)),
            if (action != null && widget.onAction != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: m.applied ? null : () => _apply(m, action),
                icon: Icon(m.applied ? Icons.check : Icons.playlist_add),
                label: Text(m.applied ? '反映しました' : widget.actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
