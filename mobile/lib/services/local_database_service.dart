// services/local_database_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  static Database? _database;
  int? _currentUserId;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ============================================================
  // INITIALISER LE SERVICE AVEC L'ID UTILISATEUR
  // ============================================================
  void setUserId(int userId) {
    _currentUserId = userId;
  }

  int get userId {
    if (_currentUserId == null) {
      throw Exception("UserId non défini. Appelez setUserId() d'abord.");
    }
    return _currentUserId!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'tomscan.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        server_id INTEGER,
        sujet TEXT NOT NULL,
        date_creation TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        question TEXT NOT NULL,
        reponse TEXT NOT NULL,
        date_message TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_history_user_date ON history(user_id, date DESC)');
    await db.execute(
        'CREATE INDEX idx_conversations_user ON conversations(user_id, updated_at DESC)');
    await db.execute(
        'CREATE INDEX idx_messages_conversation ON messages(conversation_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // Ajouter la colonne user_id à history
      try {
        await db.execute(
            'ALTER TABLE history ADD COLUMN user_id INTEGER DEFAULT 0');
      } catch (e) {
        // La colonne existe peut-être déjà
      }
      // Supprimer les anciennes données (sans user_id)
      await db.delete('history', where: 'user_id = 0 OR user_id IS NULL');

      // Ajouter la colonne user_id à conversations
      try {
        await db.execute(
            'ALTER TABLE conversations ADD COLUMN user_id INTEGER DEFAULT 0');
      } catch (e) {
        // La colonne existe peut-être déjà
      }
      await db.delete('conversations', where: 'user_id = 0 OR user_id IS NULL');
    }
  }

  // ============================================================
  // MÉTHODES POUR L'HISTORIQUE
  // ============================================================

  Future<void> saveHistoryItem(
      String type, String date, Map<String, dynamic> data) async {
    final db = await database;
    final userId = this.userId;
    await db.insert(
      'history',
      {
        'user_id': userId,
        'type': type,
        'date': date,
        'data': jsonEncode(data),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _limitHistoryEntries();
  }

  Future<List<Map<String, dynamic>>> getHistoryItems(
      {int limit = 50, int offset = 0}) async {
    final db = await database;
    final userId = this.userId;
    return await db.query(
      'history',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> getHistoryCount() async {
    final db = await database;
    final userId = this.userId;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM history WHERE user_id = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, dynamic>?> getHistoryItemByServerId(int serverId) async {
    final db = await database;
    final userId = this.userId;
    final items = await db.query(
      'history',
      where: 'user_id = ? AND data LIKE ?',
      whereArgs: [userId, '%"id":$serverId%'],
    );
    if (items.isEmpty) return null;
    return items.first;
  }

  Future<void> clearHistory() async {
    final db = await database;
    final userId = this.userId;
    await db.delete('history', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> deleteHistoryItem(int id) async {
    final db = await database;
    final userId = this.userId;
    await db.delete(
      'history',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<void> deleteHistoryItemByServerId(int serverId) async {
    final db = await database;
    final userId = this.userId;
    await db.delete(
      'history',
      where: 'user_id = ? AND data LIKE ?',
      whereArgs: [userId, '%"id":$serverId%'],
    );
  }

  Future<void> _limitHistoryEntries() async {
    final db = await database;
    final userId = this.userId;
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM history WHERE user_id = ?',
            [userId],
          ),
        ) ??
        0;

    if (count > 200) {
      await db.rawQuery(
        'DELETE FROM history WHERE user_id = ? AND id IN (SELECT id FROM history WHERE user_id = ? ORDER BY created_at ASC LIMIT ?)',
        [userId, userId, count - 200],
      );
    }
  }

  // ============================================================
  // SAUVEGARDE RAPIDE DEPUIS L'ÉCRAN CAMÉRA
  // ============================================================

  Future<void> saveDiagnosticLocally({
    required String imagePath,
    required String maladieNom,
    required double confiance,
    required int idDiagnostic,
    required int idObservation,
    required double latitude,
    required double longitude,
    required String description,
    required String symptomes,
    required String recommandation,
    required String niveauGravite,
    required String parcelleNom,
  }) async {
    final data = {
      'id': idDiagnostic,
      'type': 'photo',
      'maladie_nom': maladieNom,
      'confiance': confiance,
      'image_path': imagePath,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'symptomes': symptomes,
      'recommandation': recommandation,
      'niveau_gravite': niveauGravite,
      'parcelle_nom': parcelleNom,
      'date': DateTime.now().toIso8601String(),
      '_synced': true,
    };

    await saveHistoryItem('photo', DateTime.now().toIso8601String(), data);
  }

  // ============================================================
  // MÉTHODES POUR LES CONVERSATIONS
  // ============================================================

  Future<int> saveConversation({
    int? serverId,
    required String sujet,
    required String dateCreation,
  }) async {
    final db = await database;
    final userId = this.userId;
    final id = await db.insert(
      'conversations',
      {
        'user_id': userId,
        'server_id': serverId,
        'sujet': sujet,
        'date_creation': dateCreation,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<void> updateConversation(int id) async {
    final db = await database;
    final userId = this.userId;
    await db.update(
      'conversations',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final db = await database;
    final userId = this.userId;
    return await db.query(
      'conversations',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
  }

  Future<void> deleteConversation(int id) async {
    final db = await database;
    final userId = this.userId;
    await db.delete(
      'conversations',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  // ============================================================
  // MÉTHODES POUR LES MESSAGES
  // ============================================================

  Future<int> saveMessage({
    required int conversationId,
    required String question,
    required String reponse,
    required String dateMessage,
  }) async {
    final db = await database;
    final id = await db.insert(
      'messages',
      {
        'conversation_id': conversationId,
        'question': question,
        'reponse': reponse,
        'date_message': dateMessage,
      },
    );
    await updateConversation(conversationId);
    return id;
  }

  Future<List<Map<String, dynamic>>> getMessages(int conversationId) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'date_message ASC',
    );
  }

  Future<void> clearMessages(int conversationId) async {
    final db = await database;
    await db.delete('messages',
        where: 'conversation_id = ?', whereArgs: [conversationId]);
  }
}
