import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/position_model.dart';
import '../models/zone_model.dart';

class UserApiService {
  final http.Client _client;

  UserApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<ZoneModel>> getSafeZones() async {
    final uri = Uri.parse(ApiConfig.safeZoneEndpoint);
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => ZoneModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (response.statusCode == 404) {
      throw Exception(response.body.isNotEmpty
          ? response.body
          : 'Location Safe not found (404)');
    } else {
      throw Exception(
        'Erro ao buscar zonas seguras (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<ZoneModel>> getDangerZones() async {
    final uri = Uri.parse(ApiConfig.dangerZoneEndpoint);
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => ZoneModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (response.statusCode == 404) {
      throw Exception(response.body.isNotEmpty
          ? response.body
          : 'Location Danger not found (404)');
    } else {
      throw Exception(
        'Erro ao buscar zonas de perigo (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<String> updateUserLocation({PositionModel? position}) async {
    final uri = Uri.parse(ApiConfig.meEndpoint);
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: position != null ? jsonEncode(position.toJson()) : null,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.replaceAll('"', '').trim().isEmpty
          ? 'User location updated successfully'
          : response.body.replaceAll('"', '').trim();
    } else {
      throw Exception(
        'Erro ao atualizar localização (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }
}
