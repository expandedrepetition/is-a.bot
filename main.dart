import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const GlassAIApp());
}

const _bg = Color(0xFF080B18);
const _panel = Color(0xFF151A30);
const _cyan = Color(0xFF63E7FF);
const _purple = Color(0xFF9D8CFF);

class GlassAIApp extends StatelessWidget {
  const GlassAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Glass AI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _cyan,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool fromUser;
  final bool isError;

  const ChatMessage(this.text, {required this.fromUser, this.isError = false});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [
    const ChatMessage(
      'أهلاً! أنا مساعدك الذكي. اكتب سؤالك وسأساعدك بالبرمجة، التعلّم، والأفكار.',
      fromUser: false,
    ),
  ];

  // For quick local testing, enter your NEW Groq API key in the settings dialog.
  // Do not ship a real API key inside a public APK. Use a backend proxy for production.
  String _apiKey = '';
  String _model = 'llama-3.3-70b-versatile';
  bool _sending = false;

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || _sending) return;

    setState(() {
      _messages.add(ChatMessage(prompt, fromUser: true));
      _input.clear();
      _sending = true;
    });
    _jumpToBottom();

    if (_apiKey.trim().isEmpty) {
      setState(() {
        _messages.add(const ChatMessage(
          'حتى تتصل بالنموذج، افتح قائمة الإعدادات وأضف مفتاح Groq API جديداً. '
          'للنشر العام، لا تضع المفتاح داخل التطبيق؛ استخدم خادماً وسيطاً آمناً.',
          fromUser: false,
          isError: true,
        ));
        _sending = false;
      });
      _jumpToBottom();
      return;
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
      final request = await client.postUrl(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_apiKey.trim()}');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'system',
            'content': 'أجب باللغة التي يستخدمها المستخدم. كن واضحاً ومفيداً.'
          },
          ..._messages.where((m) => !m.isError).map((m) => {
                'role': m.fromUser ? 'user' : 'assistant',
                'content': m.text,
              }),
        ],
        'temperature': 0.7,
        'stream': false,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String detail = 'HTTP ${response.statusCode}';
        try {
          detail = jsonDecode(body)['error']?['message']?.toString() ?? detail;
        } catch (_) {}
        throw Exception(detail);
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final answer = decoded['choices']?[0]?['message']?['content']?.toString();
      if (answer == null || answer.trim().isEmpty) {
        throw Exception('لم يرجع النموذج نصاً.');
      }

      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(answer.trim(), fromUser: false)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(
            'تعذّر الاتصال: ${e.toString().replaceFirst('Exception: ', '')}\n'
            'تحقّق من الإنترنت ومفتاح API واسم النموذج.',
            fromUser: false,
            isError: true,
          )));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToBottom();
      }
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showSettings() async {
    final keyController = TextEditingController(text: _apiKey);
    final models = <String>[
      'llama-3.3-70b-versatile',
      'openai/gpt-oss-120b',
      'openai/gpt-oss-20b',
    ];
    String selectedModel = _model;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171D34),
          title: const Text('إعدادات المساعد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مفتاح Groq API',
                    style: TextStyle(color: _cyan, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'أدخل مفتاحاً جديداً',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'للتجربة المحلية فقط. لا تنشر APK يحتوي على مفتاح سري.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 18),
                const Text('النموذج',
                    style: TextStyle(color: _cyan, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: models.contains(selectedModel) ? selectedModel : models.first,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedModel = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _apiKey = keyController.text.trim();
                  _model = selectedModel;
                });
                Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    keyController.dispose();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            const _GlowBackground(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                    child: _glass(
                      radius: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [_cyan, _purple]),
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: _cyan.withOpacity(0.2),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.auto_awesome_rounded,
                                color: _bg, size: 25),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Glass AI',
                                    style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2)),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    _OnlineDot(),
                                    SizedBox(width: 6),
                                    Text('مساعدك الذكي',
                                        style: TextStyle(
                                            color: Colors.white60, fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'الإعدادات',
                            onPressed: _showSettings,
                            icon: const Icon(Icons.tune_rounded, color: _cyan),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const _TypingIndicator();
                        }
                        final message = _messages[index];
                        return _MessageBubble(message: message);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: _glass(
                      radius: 26,
                      padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'اكتب رسالتك هنا...',
                                hintStyle: TextStyle(color: Colors.white38),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [_cyan, _purple]),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: _purple.withOpacity(0.22),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: _sending ? null : _send,
                              icon: Icon(
                                _sending ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded,
                                color: _bg,
                              ),
                              tooltip: 'إرسال',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'تحقّق من المعلومات المهمة قبل الاعتماد عليها',
                      style: TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _glass({
  required Widget child,
  double radius = 20,
  EdgeInsetsGeometry padding = const EdgeInsets.all(14),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.065),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.13), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _GlowBackground extends StatelessWidget {
  const _GlowBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF11152D), _bg, Color(0xFF0A1020)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -70,
              child: _orb(240, _purple.withOpacity(0.15)),
            ),
            Positioned(
              top: 260,
              left: -120,
              child: _orb(250, _cyan.withOpacity(0.10)),
            ),
            Positioned(
              bottom: -150,
              right: 60,
              child: _orb(300, const Color(0xFF4D3FA8).withOpacity(0.13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orb(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 30)],
        ),
      );
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF62E9B2),
          shape: BoxShape.circle,
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    final tint = user ? _purple : _cyan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: user ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!user) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_cyan, _purple]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: _bg, size: 18),
            ),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: BoxDecoration(
                color: message.isError
                    ? const Color(0xFF4B2638).withOpacity(0.72)
                    : (user
                        ? const Color(0xFF7770B9).withOpacity(0.22)
                        : Colors.white.withOpacity(0.065)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(user ? 20 : 6),
                  bottomRight: Radius.circular(user ? 6 : 20),
                ),
                border: Border.all(
                  color: (message.isError ? Colors.redAccent : tint).withOpacity(0.28),
                ),
              ),
              child: SelectableText(
                message.text,
                style: const TextStyle(fontSize: 15, height: 1.55, color: Colors.white),
              ),
            ),
          ),
          if (user) ...[
            const SizedBox(width: 9),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _purple.withOpacity(0.4)),
              ),
              child: const Icon(Icons.person_rounded, color: _purple, size: 19),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: _glass(
        radius: 18,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
            ),
            SizedBox(width: 10),
            Text('يفكّر...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
