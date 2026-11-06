class PositionModel {
  final double latitude;
  final double longitude;

  const PositionModel({
    required this.latitude,
    required this.longitude,
  });

  factory PositionModel.fromJson(Map<String, dynamic> json) {
    return PositionModel(
      latitude: (json['_latitude'] ?? json['latitude'] ?? 0).toDouble(),
      longitude: (json['_longitude'] ?? json['longitude'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_latitude': latitude,
      '_longitude': longitude,
    };
  }

  @override
  String toString() =>
      'PositionModel(lat: ${latitude.toStringAsFixed(4)}, lng: ${longitude.toStringAsFixed(4)})';
}
