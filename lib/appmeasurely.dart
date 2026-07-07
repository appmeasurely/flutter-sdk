library appmeasurely;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// AppMeasurely Flutter SDK
/// Mobile attribution and analytics tracking
///
/// Usage:
///   await AppMeasurely.init('YOUR_APP_KEY');

class AppMeasurely with WidgetsBindingObserver {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final AppMeasurely _instance = AppMeasurely._internal();
  factory AppMeasurely() => _instance;
  AppMeasurely._internal();

  // ── Constants ──────────────────────────────────────────────────────────────
  static const String _endpoint =
      'https://uqvknwgcpptxnbmsubkc.supabase.co/functions/v1/track-mobile';
  static const String _sdkVersion = '1.0.0';
  static const String _deviceIdKey = 'am_device_id';
  static const String _launchedKey = 'am_launched';
  static const int _maxQueueSize = 100;
  static const int _flushIntervalSeconds = 30;

  // ── State ──────────────────────────────────────────────────────────────────
  String? _appKey;
  bool _debugMode = false;
  bool _initialized = false;
  final List<Map<String, dynamic>> _queue = [];
  bool _sending = false;
  String? _sessionId;
  DateTime? _sessionStart;
  Map<String, dynamic> _userProperties = {};
  Timer? _flushTimer;

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Initialize the SDK — call this in main() before runApp()
  static Future<void> init(String appKey, {bool debug = false}) async {
    _instance._appKey = appKey;
    _instance._debugMode = debug;
    _instance._initialized = true;

    // Register lifecycle observer
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(_instance);

    // Track install or app open
    await _instance._trackInstallOrOpen();

    // Start session
    await _instance._startSession();

    // Start periodic flush
    _instance._flushTimer = Timer.periodic(
      Duration(seconds: _flushIntervalSeconds),
      (_) => _instance._flush(),
    );

    _instance._log('Initialized. App key: ${appKey.substring(0, 8)}...');
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSession();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _endSession();
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Track a custom event
  static Future<void> trackEvent(String eventName,
      {Map<String, dynamic>? properties}) async {
    if (!_instance._initialized) return;
    final payload = await _instance._buildBasePayload(eventName);
    final merged = {..._instance._userProperties, ...?properties};
    if (merged.isNotEmpty) payload['properties'] = merged;
    await _instance._enqueue(payload);
  }

  /// Track revenue
  static Future<void> trackRevenue(
    double amount, {
    String currency = 'USD',
    String eventName = 'purchase',
    Map<String, dynamic>? properties,
  }) async {
    if (!_instance._initialized) return;
    final payload = await _instance._buildBasePayload(eventName);
    payload['revenue'] = amount;
    payload['currency'] = currency;
    if (properties != null && properties.isNotEmpty) {
      payload['properties'] = properties;
    }
    await _instance._enqueue(payload);
  }

  /// Set a user property
  static void setUserProperty(String key, dynamic value) {
    _instance._userProperties[key] = value;
  }

  /// Manually flush the event queue
  static void flush() => _instance._flush();

  /// Stop tracking
  static void stop() {
    _instance._initialized = false;
    _instance._flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_instance);
  }

  // ── Private Methods ────────────────────────────────────────────────────────

  Future<void> _trackInstallOrOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirst = !prefs.containsKey(_launchedKey);
    final payload = await _buildBasePayload(isFirst ? 'install' : 'app_open');
    payload['is_first_launch'] = isFirst;
    if (isFirst) await prefs.setBool(_launchedKey, true);
    await _enqueue(payload);
  }

  Future<void> _startSession() async {
    if (_sessionId != null) return;
    _sessionId = _generateId();
    _sessionStart = DateTime.now();
    final payload = await _buildBasePayload('session_start');
    payload['session_id'] = _sessionId;
    await _enqueue(payload);
  }

  Future<void> _endSession() async {
    if (_sessionId == null || _sessionStart == null) return;
    final duration = DateTime.now().difference(_sessionStart!).inSeconds;
    final payload = await _buildBasePayload('session_end');
    payload['session_id'] = _sessionId;
    payload['session_duration'] = duration;
    await _enqueue(payload);
    _sessionId = null;
    _sessionStart = null;
  }

  Future<Map<String, dynamic>> _buildBasePayload(String eventName) async {
    final deviceId = await _getDeviceId();
    final deviceInfo = await _getDeviceInfo();

    return {
      'app_key': _appKey,
      'event_name': eventName,
      'device_id': deviceId,
      'device_type': Platform.isIOS ? 'ios' : 'android',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'sdk_version': _sdkVersion,
      ...deviceInfo,
    };
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceIdKey);
    if (id != null) return id;
    id = _generateId();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    final info = <String, dynamic>{};
    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();
      info['app_version'] = packageInfo.version;

      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        info['os_version'] = android.version.release;
        info['device_model'] = '${android.manufacturer} ${android.model}';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        info['os_version'] = ios.systemVersion;
        info['device_model'] = ios.utsname.machine;
      }
    } catch (e) {
      _log('Error getting device info: $e');
    }
    return info;
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    if (_queue.length >= _maxQueueSize) _queue.removeAt(0);
    _queue.add(payload);
    _log('Queued: ${payload['event_name']}');
    _flush();
  }

  void _flush() async {
    if (_sending || _queue.isEmpty) return;
    _sending = true;

    final payload = _queue.first;
    final success = await _sendWithRetry(payload, 3);

    if (success) {
      _queue.removeAt(0);
      _sending = false;
      if (_queue.isNotEmpty) _flush();
    } else {
      _sending = false;
      await Future.delayed(const Duration(seconds: 2));
      _flush();
    }
  }

  Future<bool> _sendWithRetry(Map<String, dynamic> payload, int retriesLeft) async {
    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'apikey': _appKey!,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      _log('Sent: ${payload['event_name']} → ${response.statusCode}');

      if (response.statusCode == 429) return false;
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _log('Send error: $e');
      if (retriesLeft > 0) {
        await Future.delayed(const Duration(seconds: 2));
        return _sendWithRetry(payload, retriesLeft - 1);
      }
      return false;
    }
  }

  String _generateId() =>
      'am_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_'
      '${(DateTime.now().microsecond * 1000).toRadixString(36)}';

  void _log(String message) {
    if (_debugMode) print('[AppMeasurely] $message');
  }
}
