import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/friend_profile.dart';
export '../../models/friend_profile.dart';
import '../../models/remembered_item.dart';
export '../../models/remembered_item.dart';

/// Persistent key-value storage for user preferences.
///
/// Always initialise with [StorageService.initialize] before use.
class StorageService {
  // ── Default values ────────────────────────────────────────────────────────
  static const String defaultAssistantName = 'Lux';
  static const double defaultSpeechRate = 0.5;
  static const double defaultSpeechPitch = 1.0;
  static const bool defaultHapticsEnabled = true;
  static const String defaultAppLanguage = 'en';
  static const String defaultEmergencyContact = '112';
  static const bool defaultObstacleAlertsEnabled = true;
  static const bool defaultSonarCuesEnabled = true;
  static const bool defaultAutoTorchEnabled = true;
  static const bool defaultDirectionalHapticsEnabled = true;
  static const String defaultGeminiApiKey = '';
  static const bool defaultUseGeminiLive = true;

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _kAssistantName = 'assistant_name';
  static const _kSpeechRate = 'speech_rate';
  static const _kSpeechPitch = 'speech_pitch';
  static const _kHapticsEnabled = 'haptics_enabled';
  static const _kAppLanguage = 'app_language';
  static const _kEmergencyContact = 'emergency_contact';
  static const _kSavedItems = 'saved_items';
  static const _kObstacleAlertsEnabled = 'obstacle_alerts_default_enabled';
  static const _kCachedDestinations = 'cached_destinations';
  static const _kSonarCuesEnabled = 'sonar_cues_enabled';
  static const _kAutoTorchEnabled = 'auto_torch_enabled';
  static const _kDirectionalHaptics = 'directional_haptics_enabled';
  static const _kFavoritePlaces = 'favorite_places';
  static const _kHasCompletedOnboarding = 'has_completed_onboarding';
  static const _kGeminiApiKey = 'gemini_api_key';
  static const _kUseGeminiLive = 'use_gemini_live';
  static const String _kSavedFriends = 'saved_friends';
  static const String _kRememberedItems = 'remembered_items';
  static const String _kUsePhoneCamera = 'use_phone_camera';

  final SharedPreferences _prefs;

  StorageService._(this._prefs);

  /// Creates and returns an initialised [StorageService].
  static Future<StorageService> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService._(prefs);
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  String get assistantName =>
      _prefs.getString(_kAssistantName) ?? defaultAssistantName;

  double get speechRate =>
      _prefs.getDouble(_kSpeechRate) ?? defaultSpeechRate;

  double get speechSpeed => speechRate;

  double get speechPitch =>
      _prefs.getDouble(_kSpeechPitch) ?? defaultSpeechPitch;

  bool get hapticsEnabled =>
      _prefs.getBool(_kHapticsEnabled) ?? defaultHapticsEnabled;

  /// Returns the stored language code ('en' or 'kn').
  String get appLanguage =>
      _prefs.getString(_kAppLanguage) ?? defaultAppLanguage;

  String get emergencyContact =>
      _prefs.getString(_kEmergencyContact) ?? defaultEmergencyContact;

  bool get hasCompletedOnboarding =>
      _prefs.getBool(_kHasCompletedOnboarding) ?? false;

  Future<void> setCompletedOnboarding(bool val) =>
      _prefs.setBool(_kHasCompletedOnboarding, val);

  bool get obstacleAlertsDefaultEnabled =>
      _prefs.getBool(_kObstacleAlertsEnabled) ?? defaultObstacleAlertsEnabled;

  bool get sonarCuesEnabled =>
      _prefs.getBool(_kSonarCuesEnabled) ?? defaultSonarCuesEnabled;

  bool get autoTorchEnabled =>
      _prefs.getBool(_kAutoTorchEnabled) ?? defaultAutoTorchEnabled;

  bool get directionalHapticsEnabled =>
      _prefs.getBool(_kDirectionalHaptics) ?? defaultDirectionalHapticsEnabled;

  String get geminiApiKey {
    final stored = _prefs.getString(_kGeminiApiKey);
    if (stored != null &&
        stored.trim().isNotEmpty &&
        stored.trim() != 'YOUR_API_KEY' &&
        stored.trim() != 'API_KEY' &&
        stored.trim() != 'your_gemini_api_key_here') {
      return stored.trim();
    }
    return defaultGeminiApiKey;
  }

  bool get useGeminiLive =>
      _prefs.getBool(_kUseGeminiLive) ?? defaultUseGeminiLive;

  bool get usePhoneCamera =>
      _prefs.getBool(_kUsePhoneCamera) ?? false;

  List<Map<String, String>> get savedItems {
    final raw = _prefs.getStringList(_kSavedItems) ?? [];
    return raw.map((item) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        return {'name': item, 'date': ''};
      }
    }).toList();
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  Future<void> setAssistantName(String name) =>
      _prefs.setString(_kAssistantName, name);

  Future<void> setSpeechRate(double rate) =>
      _prefs.setDouble(_kSpeechRate, rate);

  Future<void> setSpeechPitch(double pitch) =>
      _prefs.setDouble(_kSpeechPitch, pitch);

  Future<void> setHapticsEnabled(bool enabled) =>
      _prefs.setBool(_kHapticsEnabled, enabled);

  Future<void> setAppLanguage(String code) =>
      _prefs.setString(_kAppLanguage, code);

  Future<void> setEmergencyContact(String contact) =>
      _prefs.setString(_kEmergencyContact, contact);

  Future<void> setObstacleAlertsDefaultEnabled(bool enabled) =>
      _prefs.setBool(_kObstacleAlertsEnabled, enabled);

  Future<void> setSonarCuesEnabled(bool enabled) =>
      _prefs.setBool(_kSonarCuesEnabled, enabled);

  Future<void> setAutoTorchEnabled(bool enabled) =>
      _prefs.setBool(_kAutoTorchEnabled, enabled);

  Future<void> setDirectionalHapticsEnabled(bool enabled) =>
      _prefs.setBool(_kDirectionalHaptics, enabled);

  Future<void> setGeminiApiKey(String key) =>
      _prefs.setString(_kGeminiApiKey, key.trim());

  Future<void> setUseGeminiLive(bool enabled) =>
      _prefs.setBool(_kUseGeminiLive, enabled);

  Future<void> setUsePhoneCamera(bool enabled) =>
      _prefs.setBool(_kUsePhoneCamera, enabled);

  Future<void> addSavedItem(String name, {String? notes}) async {
    final current = savedItems;
    current.add({
      'name': name,
      'date': DateTime.now().toIso8601String(),
      'notes': notes ?? '',
    });
    final raw = current.map((m) => jsonEncode(m)).toList();
    await _prefs.setStringList(_kSavedItems, raw);
  }

  Future<void> removeSavedItem(String name) async {
    final current = savedItems.where((i) => i['name']?.toLowerCase() != name.toLowerCase()).toList();
    final raw = current.map((m) => jsonEncode(m)).toList();
    await _prefs.setStringList(_kSavedItems, raw);
  }

  Future<void> clearAllSavedItems() =>
      _prefs.remove(_kSavedItems);

  // ── Saved Friends / Facial Profiles ─────────────────────────────────────

  List<FriendProfile> getSavedFriends() {
    final raw = _prefs.getStringList(_kSavedFriends) ?? [];
    return raw.map((item) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return FriendProfile.fromJson(decoded);
      } catch (_) {
        return null;
      }
    }).whereType<FriendProfile>().toList();
  }

  Future<void> saveFriend(FriendProfile friend) async {
    final current = getSavedFriends();
    current.removeWhere((f) => f.id == friend.id || f.name.toLowerCase() == friend.name.toLowerCase());
    current.add(friend);
    final encoded = current.map((f) => jsonEncode(f.toJson())).toList();
    await _prefs.setStringList(_kSavedFriends, encoded);
  }

  Future<void> deleteFriend(String id) async {
    final current = getSavedFriends();
    current.removeWhere((f) => f.id == id);
    final encoded = current.map((f) => jsonEncode(f.toJson())).toList();
    await _prefs.setStringList(_kSavedFriends, encoded);
  }

  // ── Persistent Spatial Object Memory ─────────────────────────────────────

  List<RememberedItem> getRememberedItems() {
    final raw = _prefs.getStringList(_kRememberedItems) ?? [];
    return raw.map((item) {
      try {
        final decoded = jsonDecode(item) as Map<String, dynamic>;
        return RememberedItem.fromJson(decoded);
      } catch (_) {
        return null;
      }
    }).whereType<RememberedItem>().toList();
  }

  Future<void> saveRememberedItem(String itemName, String locationDescription) async {
    final cleanItem = itemName.trim();
    final cleanLocation = locationDescription.trim();
    if (cleanItem.isEmpty) return;

    final current = getRememberedItems();
    current.removeWhere((i) => i.itemName.toLowerCase() == cleanItem.toLowerCase());
    current.insert(
      0,
      RememberedItem(
        'item_${DateTime.now().microsecondsSinceEpoch}',
        cleanItem,
        cleanLocation,
        DateTime.now(),
      ),
    );
    final encoded = current.map((i) => jsonEncode(i.toJson())).toList();
    await _prefs.setStringList(_kRememberedItems, encoded);
  }

  RememberedItem? findRememberedItem(String itemName) {
    String q = itemName.trim().toLowerCase();
    if (q.startsWith('my ')) q = q.substring(3).trim();
    if (q.startsWith('the ')) q = q.substring(4).trim();
    if (q.startsWith('ನನ್ನ ')) q = q.substring(5).trim();
    if (q.isEmpty) return null;

    final items = getRememberedItems();
    // 1. Exact match
    for (final item in items) {
      String n = item.itemName.toLowerCase().trim();
      if (n.startsWith('my ')) n = n.substring(3).trim();
      if (n.startsWith('the ')) n = n.substring(4).trim();
      if (n.startsWith('ನನ್ನ ')) n = n.substring(5).trim();
      if (n == q) return item;
    }
    // 2. Substring contains match
    for (final item in items) {
      String n = item.itemName.toLowerCase().trim();
      if (n.startsWith('my ')) n = n.substring(3).trim();
      if (n.startsWith('the ')) n = n.substring(4).trim();
      if (n.startsWith('ನನ್ನ ')) n = n.substring(5).trim();
      if (n.contains(q) || q.contains(n)) return item;
    }
    return null;
  }

  Future<void> deleteRememberedItem(String id) async {
    final current = getRememberedItems();
    current.removeWhere((i) => i.id == id);
    final encoded = current.map((i) => jsonEncode(i.toJson())).toList();
    await _prefs.setStringList(_kRememberedItems, encoded);
  }

  // ── Destination Geocoding Cache ──────────────────────────────────────────

  List<Map<String, dynamic>> get recentDestinations {
    final raw = _prefs.getStringList(_kCachedDestinations) ?? [];
    return raw.map((item) {
      try {
        return jsonDecode(item) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((m) => m.isNotEmpty && m['query'] != null).toList();
  }

  Map<String, dynamic>? getCachedDestination(String query) {
    final q = query.trim().toLowerCase();
    for (final item in recentDestinations) {
      if ((item['query']?.toString().toLowerCase() ?? '') == q) {
        return item;
      }
    }
    return null;
  }

  Future<void> cacheGeocodedDestination({
    required String query,
    required double lat,
    required double lng,
    required String displayName,
  }) async {
    final current = recentDestinations
        .where((item) => (item['query']?.toString().toLowerCase() ?? '') != query.trim().toLowerCase())
        .toList();

    current.insert(0, {
      'query': query.trim(),
      'lat': lat,
      'lon': lng,
      'display_name': displayName,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Keep up to 25 recent locations
    final trimmed = current.take(25).map((m) => jsonEncode(m)).toList();
    await _prefs.setStringList(_kCachedDestinations, trimmed);
  }

  Future<void> clearDestinationCache() =>
      _prefs.remove(_kCachedDestinations);

  // ── Favorite Places (Home, Work, Frequent Bookmarks) ──────────────────────

  List<Map<String, dynamic>> get favoritePlaces {
    final raw = _prefs.getStringList(_kFavoritePlaces) ?? [];
    return raw.map((item) {
      try {
        return jsonDecode(item) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((m) => m.isNotEmpty && m['name'] != null).toList();
  }

  Map<String, dynamic>? getFavoritePlace(String nameOrTag) {
    final q = nameOrTag.trim().toLowerCase();
    for (final place in favoritePlaces) {
      final n = (place['name']?.toString() ?? '').toLowerCase();
      final tag = (place['tag']?.toString() ?? '').toLowerCase();
      if (n == q || tag == q) return place;
      if ((q == 'home' || q == 'house' || q == 'ಮನೆ') &&
          (tag == 'home' || n.contains('home') || n.contains('ಮನೆ'))) {
        return place;
      }
      if ((q == 'work' || q == 'office' || q == 'ಕಚೇರಿ' || q == 'ಆಫೀಸ್') &&
          (tag == 'work' || n.contains('work') || n.contains('office') || n.contains('ಕಚೇರಿ'))) {
        return place;
      }
    }
    return null;
  }

  Future<void> saveFavoritePlace({
    String? tag,
    String? name,
    required double lat,
    double? lng,
    double? lon,
    String address = '',
  }) async {
    final effectiveTag = (tag ?? name ?? 'place').toLowerCase();
    final effectiveName = name ?? tag ?? 'Place';
    final effectiveLng = lng ?? lon ?? 0.0;
    final current = favoritePlaces
        .where((p) => (p['tag']?.toString().toLowerCase() ?? '') != effectiveTag)
        .toList();
    current.insert(0, {
      'name': effectiveName,
      'tag': effectiveTag,
      'lat': lat,
      'lon': effectiveLng,
      'lng': effectiveLng,
      'address': address,
      'updated_at': DateTime.now().toIso8601String(),
    });
    final raw = current.map((m) => jsonEncode(m)).toList();
    await _prefs.setStringList(_kFavoritePlaces, raw);
  }

  Future<void> removeFavoritePlace(String tag) async {
    final current = favoritePlaces
        .where((p) => (p['tag']?.toString().toLowerCase() ?? '') != tag.toLowerCase())
        .toList();
    final raw = current.map((m) => jsonEncode(m)).toList();
    await _prefs.setStringList(_kFavoritePlaces, raw);
  }

  Future<void> clearFavoritePlaces() async {
    await _prefs.remove(_kFavoritePlaces);
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> resetToDefaults() async {
    await _prefs.setString(_kAssistantName, defaultAssistantName);
    await _prefs.setDouble(_kSpeechRate, defaultSpeechRate);
    await _prefs.setDouble(_kSpeechPitch, defaultSpeechPitch);
    await _prefs.setBool(_kHapticsEnabled, defaultHapticsEnabled);
    await _prefs.setString(_kAppLanguage, defaultAppLanguage);
    await _prefs.setString(_kEmergencyContact, defaultEmergencyContact);
    await _prefs.setBool(_kObstacleAlertsEnabled, defaultObstacleAlertsEnabled);
    await _prefs.setBool(_kSonarCuesEnabled, defaultSonarCuesEnabled);
    await _prefs.setBool(_kAutoTorchEnabled, defaultAutoTorchEnabled);
    await _prefs.setBool(_kDirectionalHaptics, defaultDirectionalHapticsEnabled);
    await _prefs.setString(_kGeminiApiKey, defaultGeminiApiKey);
    await _prefs.setBool(_kUseGeminiLive, defaultUseGeminiLive);
    await _prefs.remove(_kSavedItems);
    await _prefs.remove(_kCachedDestinations);
    await _prefs.remove(_kFavoritePlaces);
    await _prefs.remove(_kSavedFriends);
  }
}
