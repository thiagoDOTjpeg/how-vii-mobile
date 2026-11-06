import 'package:flutter_test/flutter_test.dart';
import 'package:how_vii_mobile/models/position_model.dart';
import 'package:how_vii_mobile/models/zone_model.dart';

void main() {
  group('ZoneModel & PositionModel Serialization Tests (api_mobile)', () {
    test('Deve desserializar corretamente o JSON do backend C# api_mobile', () {
      final backendJson = {
        '_type_zone': 'safe',
        '_position': {
          '_latitude': 48.8566,
          '_longitude': 2.3522,
        },
        '_level_zone': 1,
        '_radius': 1000,
      };

      final zone = ZoneModel.fromJson(backendJson);

      expect(zone.typeZone, 'safe');
      expect(zone.isSafe, isTrue);
      expect(zone.isDanger, isFalse);
      expect(zone.position.latitude, 48.8566);
      expect(zone.position.longitude, 2.3522);
      expect(zone.levelZone, 1);
      expect(zone.radius, 1000.0);
    });

    test('Deve serializar PositionModel para o formato esperado pela API', () {
      const pos = PositionModel(latitude: 48.8566, longitude: 2.3522);
      final json = pos.toJson();

      expect(json['_latitude'], 48.8566);
      expect(json['_longitude'], 2.3522);
    });
  });
}

