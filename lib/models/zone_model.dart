import 'position_model.dart';

class ZoneModel {
  final String typeZone;
  final PositionModel position;
  final int levelZone;
  final double radius;

  const ZoneModel({
    required this.typeZone,
    required this.position,
    required this.levelZone,
    required this.radius,
  });

  bool get isSafe => typeZone.toLowerCase() == 'safe';
  bool get isDanger => typeZone.toLowerCase() == 'danger';

  factory ZoneModel.fromJson(Map<String, dynamic> json) {
    final posJson = json['_position'] ?? json['position'];
    return ZoneModel(
      typeZone: (json['_type_zone'] ?? json['typeZone'] ?? 'No type').toString(),
      position: posJson is Map<String, dynamic>
          ? PositionModel.fromJson(posJson)
          : const PositionModel(latitude: 0, longitude: 0),
      levelZone: (json['_level_zone'] ?? json['levelZone'] ?? 0) is int
          ? (json['_level_zone'] ?? json['levelZone'] ?? 0) as int
          : ((json['_level_zone'] ?? json['levelZone'] ?? 0) as num).toInt(),
      radius: (json['_radius'] ?? json['radius'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_type_zone': typeZone,
      '_position': position.toJson(),
      '_level_zone': levelZone,
      '_radius': radius,
    };
  }
}
