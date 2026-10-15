import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/device.dart';
import '../../domain/entities/ipsw_release.dart';

class IpswApiException implements Exception {
  IpswApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'IpswApiException($statusCode): $message';
}

/// Thin client for https://api.ipsw.me/v4/.
class IpswApiClient {
  IpswApiClient({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _base = baseUri ?? Uri.parse('https://api.ipsw.me/v4/');

  final http.Client _client;
  final Uri _base;

  /// `GET /devices` — every known device with its commercial name and boards.
  Future<List<Device>> fetchDevices() async {
    final json = await _get('devices') as List;
    return json.whereType<Map<String, dynamic>>().map(Device.fromJson).toList();
  }

  /// `GET /device/{identifier}?type=ipsw` — all IPSWs for one device.
  Future<List<IpswRelease>> fetchDeviceFirmwares(String identifier) async {
    final json = await _get(
      'device/${Uri.encodeComponent(identifier)}',
      query: {'type': 'ipsw'},
    ) as Map<String, dynamic>;
    final firmwares = json['firmwares'] as List? ?? const [];
    return firmwares
        .whereType<Map<String, dynamic>>()
        .map((f) => IpswRelease.fromJson(f, identifier: identifier))
        .toList();
  }

  /// `GET /ipsw/{version}` — every device's IPSW for one OS version.
  Future<List<IpswRelease>> fetchFirmwaresForVersion(String version) async {
    final json = await _get('ipsw/${Uri.encodeComponent(version)}') as List;
    return json
        .whereType<Map<String, dynamic>>()
        .map(IpswRelease.fromJson)
        .toList();
  }

  /// `GET /model/{model}` — marketing model number (A2403) → identifier.
  Future<String?> fetchIdentifierForModel(String modelNumber) async {
    try {
      final json = await _get(
        'model/${Uri.encodeComponent(modelNumber)}',
      ) as Map<String, dynamic>;
      return json['identifier'] as String?;
    } on IpswApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  void close() => _client.close();

  Future<Object?> _get(String path, {Map<String, String>? query}) async {
    final uri = _base.resolve(path).replace(queryParameters: query);
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw IpswApiException(
        'GET $uri failed: ${response.reasonPhrase}',
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
