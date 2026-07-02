import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Thin client for the wuvt-replay backend.
class Api {
  Api({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseOverride = baseUrl;

  final http.Client _client;
  final String? _baseOverride; // for tests; normally follows BackendConfig

  /// Resolved per request so a settings change applies without a restart.
  String get _base =>
      (_baseOverride ?? BackendConfig.instance.url).replaceAll(RegExp(r'/+$'), '');

  Future<dynamic> _getJson(String path) async {
    final uri = Uri.parse('$_base$path');
    http.Response resp;
    try {
      resp = await _client.get(uri).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(
        'The backend took too long to respond.',
        detail: 'GET $uri timed out after 30s',
      );
    } on http.ClientException catch (e) {
      // Wraps SocketException & friends: DNS failure, connection refused, ...
      throw ApiException(
        "Can't reach the backend.\nCheck wifi / Tailscale, then retry.",
        detail: e.toString(),
      );
    }
    if (resp.statusCode != 200) {
      throw ApiException(
        'The backend returned an error (${resp.statusCode}).',
        detail: 'GET $uri -> HTTP ${resp.statusCode}',
      );
    }
    try {
      return jsonDecode(resp.body);
    } on FormatException catch (e) {
      throw ApiException(
        'The backend sent an unexpected response.',
        detail: 'GET $uri: ${e.message}',
      );
    }
  }

  Future<List<Dj>> djs() async {
    final data = await _getJson('/djs') as Map<String, dynamic>;
    return ((data['djs'] ?? []) as List)
        .map((e) => Dj.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DjDetail> djDetail(int djId) async {
    final data = await _getJson('/djs/$djId') as Map<String, dynamic>;
    return DjDetail.fromJson(data);
  }

  Future<SetDetail> setDetail(int setId) async {
    final data = await _getJson('/sets/$setId') as Map<String, dynamic>;
    return SetDetail.fromJson(data);
  }

  Future<Health> health() async {
    final data = await _getJson('/health') as Map<String, dynamic>;
    return Health.fromJson(data);
  }
}

/// A request failure with a human-readable [message] (shown prominently) and
/// an optional technical [detail] (shown small, for debugging).
class ApiException implements Exception {
  final String message;
  final String? detail;
  ApiException(this.message, {this.detail});
  @override
  String toString() => message;
}
