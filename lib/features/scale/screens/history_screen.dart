import 'package:flutter/material.dart';

import '../models/coffee_session.dart';
import '../services/session_storage.dart';
import 'session_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<CoffeeSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await SessionStorage.loadSessions();
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _delete(String id) async {
    await SessionStorage.deleteSession(id);
    await _load();
  }

  String _titleFor(CoffeeSession session) {
    if (session.beanName != null && session.beanName!.isNotEmpty) {
      return session.beanName!;
    }
    return 'Untitled Session';
  }

  String _subtitleFor(CoffeeSession session) {
    final date = session.createdAt;
    final dateText =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final roast = (session.roastLevel == null || session.roastLevel!.isEmpty)
        ? '-'
        : session.roastLevel!;
    return '$dateText | Roast: $roast | ${session.maxWeight.toStringAsFixed(1)} g';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Sessions'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
          ? const Center(
        child: Text(
          'No saved sessions yet',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      )
          : ListView.builder(
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(_titleFor(session)),
              subtitle: Text(_subtitleFor(session)),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(sessionId: session.id),
                  ),
                );
                await _load();
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _delete(session.id),
              ),
            ),
          );
        },
      ),
    );
  }
}