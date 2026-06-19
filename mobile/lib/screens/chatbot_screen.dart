// screens/chatbot_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme.dart';
import '../config.dart';
import '../services/auth_service.dart'; // ← AJOUT

class ChatbotScreen extends StatefulWidget {
  final String? initialQuestion;

  const ChatbotScreen({super.key, this.initialQuestion});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final Dio _dio = Dio();
  List<Conversation> _conversations = [];
  Conversation? _selectedConversation;
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _isInitializing = true;

  // ID de l'utilisateur connecté
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    _userId = await AuthService().getUserId();
    _loadConversations().then((_) {
      setState(() => _isInitializing = false);
      if (widget.initialQuestion != null &&
          widget.initialQuestion!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sendInitialQuestion(widget.initialQuestion!);
        });
      }
    });
  }

  void _sendInitialQuestion(String question) {
    _messageController.text = question;
    _sendMessage();
  }

  Future<void> _loadConversations() async {
    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/conversations?user_id=${_userId ?? 1}',
      );
      if (response.statusCode == 200) {
        final data = response.data as List;
        setState(() {
          _conversations = data
              .map((c) => Conversation(
                    id: c['id_conversation'],
                    sujet: c['sujet'] ?? 'Nouvelle conversation',
                    dateCreation: c['date_creation'],
                  ))
              .toList();
        });
        if (_conversations.isNotEmpty && _selectedConversation == null) {
          _selectConversation(_conversations.first);
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement conversations: $e');
    }
  }

  Future<void> _createNewConversation() async {
    final sujet = await _showNewConversationDialog();
    if (sujet == null) return;
    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/conversations?user_id=${_userId ?? 1}',
        data: {'sujet': sujet},
      );
      if (response.statusCode == 200) {
        final newConv = Conversation(
          id: response.data['id'],
          sujet: response.data['sujet'],
          dateCreation: DateTime.now().toIso8601String(),
        );
        setState(() {
          _conversations.insert(0, newConv);
        });
        _selectConversation(newConv);
      }
    } catch (e) {
      debugPrint('Erreur création conversation: $e');
    }
  }

  Future<String?> _showNewConversationDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.chat, color: AppTheme.primary),
            const SizedBox(width: 10),
            const Text(
              'Nouvelle conversation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Sujet (optionnel)',
            hintStyle: TextStyle(color: AppTheme.textLight),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textMedium,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Créer'),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Future<void> _selectConversation(Conversation conv) async {
    setState(() {
      _selectedConversation = conv;
      _messages = [];
      _isSending = false;
    });
    try {
      final response = await _dio
          .get('${AppConfig.baseUrl}/conversations/${conv.id}/messages');
      if (response.statusCode == 200) {
        final data = response.data as List;
        setState(() {
          _messages = data
              .expand((m) => [
                    {'isUser': true, 'text': m['question']},
                    {'isUser': false, 'text': m['reponse']}
                  ])
              .toList();
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Erreur chargement messages: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _cleanUserText(String text) {
    return text.replaceAll(RegExp(r'[*_#~`]'), '');
  }

  Future<void> _sendMessage() async {
    final question = _messageController.text.trim();
    if (question.isEmpty || _selectedConversation == null || _isSending) return;

    setState(() {
      _messages.add({'isUser': true, 'text': _cleanUserText(question)});
      _messageController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/conversations/${_selectedConversation!.id}/messages',
        data: {'question': question},
      );
      if (response.statusCode == 200) {
        setState(() {
          _messages.add({'isUser': false, 'text': response.data['reponse']});
          _isSending = false;
        });
        _scrollToBottom();
      } else {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }
    } on DioException catch (e) {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.message}'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _selectedConversation?.sujet ?? 'Assistant TomScan',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textDark,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            onPressed: _createNewConversation,
            color: AppTheme.primary,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppTheme.cardBg,
        child: Column(
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.primary,
              ),
              child: const Center(
                child: Text(
                  'Conversations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final isSelected = conv.id == _selectedConversation?.id;
                  return ListTile(
                    leading: Icon(
                      Icons.chat_bubble_outline,
                      color: isSelected ? AppTheme.primary : AppTheme.textLight,
                    ),
                    title: Text(
                      conv.sujet,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.textDark
                            : AppTheme.textMedium,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: AppTheme.primary)
                        : null,
                    selected: isSelected,
                    selectedTileColor: AppTheme.primaryLight.withOpacity(0.08),
                    onTap: () {
                      Navigator.pop(context);
                      _selectConversation(conv);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Liste des messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isSending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isSending) {
                  return _buildTypingIndicator();
                }
                final msg = _messages[index];
                final isUser = msg['isUser'] as bool;
                final text = msg['text'] as String;

                if (isUser) {
                  return _buildUserMessage(text);
                } else {
                  return _buildAssistantMessage(text);
                }
              },
            ),
          ),
          // Zone de saisie
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildUserMessage(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: MarkdownBody(
          data: text,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              fontSize: 14,
              color: AppTheme.textDark,
              height: 1.5,
            ),
            strong: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
            em: const TextStyle(
              fontStyle: FontStyle.italic,
              color: AppTheme.textDark,
            ),
            listBullet: TextStyle(
              fontSize: 14,
              color: AppTheme.textDark,
            ),
            blockquote: TextStyle(
              fontSize: 14,
              color: AppTheme.textMedium,
            ),
            code: TextStyle(
              fontSize: 13,
              backgroundColor: AppTheme.background,
              color: AppTheme.textDark,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Assistant écrit...',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Posez votre question...',
                hintStyle: TextStyle(color: AppTheme.textLight),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: AppTheme.background,
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: _isSending ? AppTheme.textLight : AppTheme.primary,
            radius: 24,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class Conversation {
  final int id;
  final String sujet;
  final String dateCreation;
  Conversation({
    required this.id,
    required this.sujet,
    required this.dateCreation,
  });
}
