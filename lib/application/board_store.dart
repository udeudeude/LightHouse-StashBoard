import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/board_state.dart';

class BoardStore {
  static const _boardKey = 'lighthouse-current-board-v1';

  Future<BoardState> load() async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_boardKey);
    if (raw == null) return BoardState.empty();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BoardState.fromJson(decoded.cast<String, Object?>());
    } on Object {
      return BoardState.empty();
    }
  }

  Future<void> save(BoardState state) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_boardKey, jsonEncode(state.toJson()));
  }

  Future<void> clear() async {
    final prefs = SharedPreferencesAsync();
    await prefs.remove(_boardKey);
  }
}
