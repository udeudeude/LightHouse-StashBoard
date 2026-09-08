import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/board_state.dart';

class StoredBoardSummary {
  const StoredBoardSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
}

class BoardStore {
  static const _boardKey = 'lighthouse-current-board-v2';
  static const _backupKey = 'lighthouse-current-board-backup-v2';
  static const _legacyBoardKey = 'lighthouse-current-board-v1';
  static const _libraryKey = 'lighthouse-board-library-v2';

  Future<BoardState> load() async {
    final prefs = SharedPreferencesAsync();
    for (final key in [_boardKey, _backupKey, _legacyBoardKey]) {
      final raw = await prefs.getString(key);
      if (raw == null) continue;
      final decoded = _decodeBoard(raw);
      if (decoded != null) return decoded;
    }
    return BoardState.empty();
  }

  Future<void> save(BoardState state) async {
    final prefs = SharedPreferencesAsync();
    final previous = await prefs.getString(_boardKey);
    if (previous != null) {
      await prefs.setString(_backupKey, previous);
    }
    await prefs.setString(_boardKey, jsonEncode(state.toJson()));
  }

  Future<List<StoredBoardSummary>> listSavedBoards() async {
    final library = await _readLibrary();
    final summaries = <StoredBoardSummary>[];
    for (final entry in library.entries) {
      final record = (entry.value as Map).cast<String, Object?>();
      final state = _stateFromRecord(record);
      final updatedAt =
          DateTime.tryParse(record['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (state != null) {
        summaries.add(
          StoredBoardSummary(
            id: entry.key,
            title: state.title,
            updatedAt: updatedAt,
          ),
        );
      }
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<String> saveNamed(BoardState state, {String? id}) async {
    final prefs = SharedPreferencesAsync();
    final library = await _readLibrary();
    final boardId = id ?? 'board-${DateTime.now().microsecondsSinceEpoch}';
    library[boardId] = {
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'state': state.toJson(),
    };
    await prefs.setString(_libraryKey, jsonEncode(library));
    return boardId;
  }

  Future<BoardState?> loadNamed(String id) async {
    final library = await _readLibrary();
    final raw = library[id];
    if (raw is! Map) return null;
    return _stateFromRecord(raw.cast<String, Object?>());
  }

  Future<void> deleteNamed(String id) async {
    final prefs = SharedPreferencesAsync();
    final library = await _readLibrary();
    library.remove(id);
    await prefs.setString(_libraryKey, jsonEncode(library));
  }

  Future<void> clear() async {
    final prefs = SharedPreferencesAsync();
    await prefs.remove(_boardKey);
    await prefs.remove(_backupKey);
    await prefs.remove(_legacyBoardKey);
  }

  BoardState? importJson(String raw) => _decodeBoard(raw);

  String exportJson(BoardState state) =>
      const JsonEncoder.withIndent('  ').convert(state.toJson());

  BoardState? _decodeBoard(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BoardState.fromJson(decoded.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>> _readLibrary() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_libraryKey);
    if (raw == null) return <String, Object?>{};
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } on Object {
      return <String, Object?>{};
    }
  }

  BoardState? _stateFromRecord(Map<String, Object?> record) {
    final rawState = record['state'];
    if (rawState is! Map) return null;
    try {
      return BoardState.fromJson(rawState.cast<String, Object?>());
    } on Object {
      return null;
    }
  }
}
