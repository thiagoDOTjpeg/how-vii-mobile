import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../config/api_config.dart';
import '../models/position_model.dart';
import '../models/zone_model.dart';
import '../services/user_api_service.dart';

class _DisplayZone {
  final String id;
  final String title;
  final ZoneModel zone;
  final LatLng displayPoint;
  final bool hasVisualOffset;

  const _DisplayZone({
    required this.id,
    required this.title,
    required this.zone,
    required this.displayPoint,
    required this.hasVisualOffset,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UserApiService _apiService = UserApiService();
  final MapController _mapController = MapController();
  final Distance _distanceCalc = const Distance();

  StreamSubscription<Position>? _gpsSubscription;

  int _currentTabIndex = 0;

  List<ZoneModel> _safeZones = [];
  List<ZoneModel> _dangerZones = [];
  bool _isLoading = false;
  bool _isUpdatingLocation = false;
  bool _isFetchingGps = false;
  bool _hasRealGpsLock = false;
  String? _errorMessage;
  String? _gpsStatusText;

  String _selectedFilter = 'all';
  String _googleMapLayer = 'm';
  bool _spreadOverlappingZones = false;
  bool _anchorZonesNearUserGps = false;
  String? _selectedZoneId;

  LatLng _userLocation = const LatLng(-23.5505, -46.6333);
  LatLng? _realGpsLocation;

  final List<String> _apiLogs = [];

  @override
  void initState() {
    super.initState();
    _fetchAllZones();
    _initRealGpsLocation(centerMap: true);
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    super.dispose();
  }

  void _addLog(String entry) {
    final now = TimeOfDay.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _apiLogs.insert(0, '[$timeStr] $entry');
      if (_apiLogs.length > 30) {
        _apiLogs.removeLast();
      }
    });
  }

  Future<void> _initRealGpsLocation({bool centerMap = true}) async {
    setState(() {
      _isFetchingGps = true;
      _gpsStatusText = 'Solicitando permissão de GPS...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsStatusText = 'Serviço de localização desativado no dispositivo.';
          _isFetchingGps = false;
        });
        _addLog('GPS → Serviço de localização desativado.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsStatusText = 'Permissão de localização negada pelo usuário.';
            _isFetchingGps = false;
          });
          _addLog('GPS → Permissão negada pelo navegador/dispositivo.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsStatusText =
              'Permissão de GPS bloqueada permanentemente no navegador.';
          _isFetchingGps = false;
        });
        _addLog('GPS → Permissão bloqueada permanentemente.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      final realLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _realGpsLocation = realLatLng;
        _userLocation = realLatLng;
        _hasRealGpsLock = true;
        _gpsStatusText =
            'GPS Real Ativo (±${position.accuracy.toStringAsFixed(0)}m)';
      });

      _addLog(
        'GPS REAL OBTIDO → (${realLatLng.latitude.toStringAsFixed(5)}, ${realLatLng.longitude.toStringAsFixed(5)})',
      );

      if (centerMap) {
        Future.delayed(const Duration(milliseconds: 150), () {
          try {
            _mapController.move(realLatLng, 13.5);
          } catch (_) {}
        });
      }

      await _handleUpdateUserLocation(
        newLocation: realLatLng,
        showSnackbar: true,
      );

      await _gpsSubscription?.cancel();
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((Position pos) {
        if (!mounted) return;
        final updated = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _realGpsLocation = updated;
          _userLocation = updated;
          _hasRealGpsLock = true;
          _gpsStatusText = 'GPS Real Ativo (±${pos.accuracy.toStringAsFixed(0)}m)';
        });
        _handleUpdateUserLocation(newLocation: updated, showSnackbar: false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsStatusText = 'Não foi possível obter o GPS real: $e';
      });
      _addLog('Aviso GPS → $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingGps = false;
        });
      }
    }
  }

  Future<void> _fetchAllZones() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _addLog('GET /api/me/safe/zone & GET /api/me/danger/zone...');

    try {
      final results = await Future.wait([
        _apiService.getSafeZones(),
        _apiService.getDangerZones(),
      ]);

      if (!mounted) return;
      setState(() {
        _safeZones = results[0];
        _dangerZones = results[1];
        if (!_hasRealGpsLock && _safeZones.isNotEmpty) {
          _userLocation = LatLng(
            _safeZones.first.position.latitude,
            _safeZones.first.position.longitude,
          );
        }
      });
      _addLog(
        '200 OK → ${_safeZones.length} zonas seguras e ${_dangerZones.length} zonas de perigo carregadas.',
      );
    } catch (e) {
      if (!mounted) return;
      final cleanErr = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = cleanErr;
      });
      _addLog('ERRO → $cleanErr');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleUpdateUserLocation({
    LatLng? newLocation,
    bool showSnackbar = true,
    bool isManualSimulation = false,
  }) async {
    if (newLocation != null) {
      setState(() {
        _userLocation = newLocation;
        if (isManualSimulation) {
          _gpsStatusText = 'Posição ajustada manualmente no mapa';
        }
      });
    }

    setState(() {
      _isUpdatingLocation = true;
    });

    final posModel = PositionModel(
      latitude: _userLocation.latitude,
      longitude: _userLocation.longitude,
    );

    _addLog(
      'POST /api/me → (${posModel.latitude.toStringAsFixed(5)}, ${posModel.longitude.toStringAsFixed(5)})',
    );

    try {
      final message = await _apiService.updateUserLocation(position: posModel);
      if (!mounted) return;
      _addLog('200 OK → "$message"');
      if (showSnackbar) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$message (${posModel.latitude.toStringAsFixed(4)}, ${posModel.longitude.toStringAsFixed(4)})',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _addLog('ERRO POST /api/me → $e');
      if (showSnackbar) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar localização: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingLocation = false;
        });
      }
    }
  }

  List<_DisplayZone> get _displayZones {
    final List<_DisplayZone> list = [];
    final LatLng? gpsAnchor =
        (_anchorZonesNearUserGps && _realGpsLocation != null)
            ? _realGpsLocation
            : null;

    for (int i = 0; i < _safeZones.length; i++) {
      final z = _safeZones[i];
      final baseLat = gpsAnchor?.latitude ?? z.position.latitude;
      final baseLng = gpsAnchor?.longitude ?? z.position.longitude;

      LatLng point = LatLng(baseLat, baseLng);
      bool offsetApplied = gpsAnchor != null;

      if (_spreadOverlappingZones && i > 0) {
        final angle = (i * 2 * math.pi) / _safeZones.length;
        point = LatLng(
          baseLat + 0.014 * math.cos(angle),
          baseLng + 0.018 * math.sin(angle),
        );
        offsetApplied = true;
      }

      list.add(
        _DisplayZone(
          id: 'safe_$i',
          title: 'Zona Segura #${i + 1}',
          zone: z,
          displayPoint: point,
          hasVisualOffset: offsetApplied,
        ),
      );
    }

    for (int i = 0; i < _dangerZones.length; i++) {
      final z = _dangerZones[i];
      final baseLat = gpsAnchor?.latitude ?? z.position.latitude;
      final baseLng = gpsAnchor?.longitude ?? z.position.longitude;

      LatLng point = LatLng(baseLat, baseLng);
      bool offsetApplied = gpsAnchor != null;

      if (_spreadOverlappingZones) {
        final angle = ((i + 0.5) * 2 * math.pi) / _dangerZones.length;
        point = LatLng(
          baseLat + 0.028 * math.cos(angle),
          baseLng + 0.034 * math.sin(angle),
        );
        offsetApplied = true;
      }

      list.add(
        _DisplayZone(
          id: 'danger_$i',
          title: 'Zona de Perigo #${i + 1}',
          zone: z,
          displayPoint: point,
          hasVisualOffset: offsetApplied,
        ),
      );
    }

    if (_selectedFilter == 'safe') {
      return list.where((d) => d.zone.isSafe).toList();
    }
    if (_selectedFilter == 'danger') {
      return list.where((d) => d.zone.isDanger).toList();
    }
    return list;
  }

  ({String label, Color color, IconData icon}) get _userSafetyStatus {
    final all = _displayZones;
    for (final d in all.where((z) => z.zone.isDanger)) {
      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        _userLocation,
        d.displayPoint,
      );
      if (meters <= d.zone.radius) {
        return (
          label:
              'ALERTA: Você está dentro da ${d.title} (${meters.toStringAsFixed(0)}m do centro)',
          color: const Color(0xFFDC2626),
          icon: Icons.warning_amber_rounded,
        );
      }
    }

    for (final d in all.where((z) => z.zone.isSafe)) {
      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        _userLocation,
        d.displayPoint,
      );
      if (meters <= d.zone.radius) {
        return (
          label:
              'PROTEGIDO: Você está na ${d.title} (${meters.toStringAsFixed(0)}m do centro)',
          color: const Color(0xFF059669),
          icon: Icons.verified_user_rounded,
        );
      }
    }

    return (
      label: 'Fora de zonas demarcadas • Monitorando via GPS em tempo real',
      color: const Color(0xFF2563EB),
      icon: Icons.radar_rounded,
    );
  }

  void _focusOnZone(_DisplayZone item) {
    setState(() {
      _selectedZoneId = item.id;
      _currentTabIndex = 0;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        _mapController.move(item.displayPoint, 14.2);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _errorMessage != null && _currentTabIndex != 2
            ? _buildErrorView()
            : IndexedStack(
                index: _currentTabIndex,
                children: [
                  _buildRadarMapTab(),
                  _buildZonesDirectoryTab(),
                  _buildApiAndPositionTab(),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _currentTabIndex = idx;
          });
        },
        backgroundColor: Colors.white,
        elevation: 3,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Mapa Radar',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('${_safeZones.length + _dangerZones.length}'),
              child: const Icon(Icons.shield_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${_safeZones.length + _dangerZones.length}'),
              child: const Icon(Icons.shield_rounded),
            ),
            label: 'Zonas (${_safeZones.length + _dangerZones.length})',
          ),
          const NavigationDestination(
            icon: Icon(Icons.gps_fixed_outlined),
            selectedIcon: Icon(Icons.gps_fixed_rounded),
            label: 'GPS & API',
          ),
        ],
      ),
    );
  }

  Widget _buildRadarMapTab() {
    final zones = _displayZones;
    final safety = _userSafetyStatus;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _userLocation,
            initialZoom: 13.5,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://mt1.google.com/vt/lyrs=$_googleMapLayer&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.example.how_vii_mobile',
            ),
            CircleLayer(
              circles: zones.map((item) {
                final isSafe = item.zone.isSafe;
                final isSelected = item.id == _selectedZoneId;
                final baseColor =
                    isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444);
                return CircleMarker(
                  point: item.displayPoint,
                  radius: item.zone.radius,
                  useRadiusInMeter: true,
                  color: baseColor.withValues(alpha: isSelected ? 0.35 : 0.18),
                  borderColor: isSelected
                      ? const Color(0xFF0F172A)
                      : (isSafe
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626)),
                  borderStrokeWidth: isSelected ? 3.5 : 2.0,
                );
              }).toList(),
            ),
            MarkerLayer(
              markers: [
                ...zones.map((item) {
                  final isSafe = item.zone.isSafe;
                  final isSelected = item.id == _selectedZoneId;
                  final color = isSafe
                      ? const Color(0xFF059669)
                      : const Color(0xFFDC2626);
                  return Marker(
                    point: item.displayPoint,
                    width: isSelected ? 52 : 42,
                    height: isSelected ? 52 : 42,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedZoneId = item.id;
                        });
                        _mapController.move(
                          item.displayPoint,
                          _mapController.camera.zoom,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? color : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                          border: Border.all(
                            color: isSelected ? Colors.white : color,
                            width: 2.5,
                          ),
                        ),
                        child: Icon(
                          isSafe
                              ? Icons.verified_user_rounded
                              : Icons.gpp_maybe_rounded,
                          color: isSelected ? Colors.white : color,
                          size: isSelected ? 26 : 22,
                        ),
                      ),
                    ),
                  );
                }),
                Marker(
                  point: _userLocation,
                  width: 84,
                  height: 68,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _hasRealGpsLock ? 'VOCÊ (GPS)' : 'VOCÊ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _hasRealGpsLock
                                ? const Color(0xFF10B981)
                                : Colors.amber.shade700,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _gpsStatusText ??
                                'SafeRadar • Conectado (${ApiConfig.baseUrl})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Recarregar Zonas da API',
                          onPressed: _isLoading ? null : _fetchAllZones,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _isFetchingGps
                              ? null
                              : () => _initRealGpsLocation(centerMap: true),
                          icon: _isFetchingGps
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.gps_fixed_rounded, size: 15),
                          label: const Text(
                            'Meu GPS',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        PopupMenuButton<String>(
                          tooltip: 'Tipo de Mapa Google',
                          initialValue: _googleMapLayer,
                          onSelected: (val) =>
                              setState(() => _googleMapLayer = val),
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 'm',
                              child: Text('🗺️ Google Ruas (Padrão)'),
                            ),
                            PopupMenuItem(
                              value: 'y',
                              child:
                                  Text('🛰️ Google Híbrido (Satélite + Ruas)'),
                            ),
                            PopupMenuItem(
                              value: 's',
                              child: Text('🌎 Google Satélite Puro'),
                            ),
                            PopupMenuItem(
                              value: 'p',
                              child: Text('⛰️ Google Terreno / Relevo'),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.layers_outlined, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Mapa',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: safety.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: safety.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(safety.icon, color: safety.color, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              safety.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: safety.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterPill(
                      value: 'all',
                      label:
                          'Todas (${_safeZones.length + _dangerZones.length})',
                      icon: Icons.apps_rounded,
                      activeColor: const Color(0xFF0F172A),
                    ),
                    const SizedBox(width: 6),
                    _buildFilterPill(
                      value: 'safe',
                      label: 'Seguras (${_safeZones.length})',
                      icon: Icons.verified_user_rounded,
                      activeColor: const Color(0xFF059669),
                    ),
                    const SizedBox(width: 6),
                    _buildFilterPill(
                      value: 'danger',
                      label: 'Perigo (${_dangerZones.length})',
                      icon: Icons.warning_amber_rounded,
                      activeColor: const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _anchorZonesNearUserGps,
                      onSelected: (val) {
                        setState(() {
                          _anchorZonesNearUserGps = val;
                        });
                        if (val && _realGpsLocation != null) {
                          _mapController.move(_realGpsLocation!, 13.5);
                        } else if (!val && _safeZones.isNotEmpty) {
                          _mapController.move(
                            LatLng(
                              _safeZones.first.position.latitude,
                              _safeZones.first.position.longitude,
                            ),
                            13.0,
                          );
                        }
                      },
                      avatar: const Icon(Icons.place_outlined, size: 16),
                      label: const Text(
                        'Zonas no meu GPS',
                        style: TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFDCFCE7),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      selected: _spreadOverlappingZones,
                      onSelected: (val) {
                        setState(() {
                          _spreadOverlappingZones = val;
                        });
                      },
                      avatar: const Icon(Icons.scatter_plot_outlined, size: 16),
                      label: const Text(
                        'Separar sobrepostas',
                        style: TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFDBEAFE),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: 168,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMapIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Aproximar',
                onTap: () {
                  final cam = _mapController.camera;
                  _mapController.move(cam.center, cam.zoom + 1);
                },
              ),
              const SizedBox(height: 6),
              _buildMapIconButton(
                icon: Icons.remove_rounded,
                tooltip: 'Afastar',
                onTap: () {
                  final cam = _mapController.camera;
                  _mapController.move(cam.center, cam.zoom - 1);
                },
              ),
              const SizedBox(height: 6),
              _buildMapIconButton(
                icon: Icons.gps_fixed_rounded,
                tooltip: 'Obter Minha Localização GPS Real',
                color: const Color(0xFF2563EB),
                onTap: () => _initRealGpsLocation(centerMap: true),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          height: 142,
          child: zones.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: zones.length,
                  itemBuilder: (context, index) {
                    final item = zones[index];
                    final isSafe = item.zone.isSafe;
                    final isSelected = item.id == _selectedZoneId;
                    final color = isSafe
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626);
                    final distMeters = _distanceCalc.as(
                      LengthUnit.Meter,
                      _userLocation,
                      item.displayPoint,
                    );

                    return GestureDetector(
                      onTap: () => _focusOnZone(item),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 270,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? color : const Color(0xFFE2E8F0),
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isSafe
                                        ? Icons.verified_user_rounded
                                        : Icons.gpp_maybe_rounded,
                                    color: color,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Nível ${item.zone.levelZone} • Raio ${item.zone.radius.toStringAsFixed(0)}m',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    distMeters >= 1000
                                        ? '${(distMeters / 1000).toStringAsFixed(1)} km'
                                        : '${distMeters.toStringAsFixed(0)} m',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Coord: (${item.displayPoint.latitude.toStringAsFixed(4)}, ${item.displayPoint.longitude.toStringAsFixed(4)})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _focusOnZone(item),
                                  icon: const Icon(
                                    Icons.center_focus_strong_rounded,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    'Centralizar',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterPill({
    required String value,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : activeColor,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      backgroundColor: Colors.white,
      selectedColor: activeColor,
      showCheckmark: false,
    );
  }

  Widget _buildMapIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = const Color(0xFF0F172A),
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildZonesDirectoryTab() {
    final zones = _displayZones;
    return RefreshIndicator(
      onRefresh: _fetchAllZones,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Painel de Zonas Mapeadas',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dados sincronizados dos endpoints GET /api/me/safe/zone e GET /api/me/danger/zone',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Zonas Seguras',
                  value: '${_safeZones.length}',
                  subtitle: 'Raio 1000m',
                  color: const Color(0xFF059669),
                  icon: Icons.verified_user_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'Zonas de Perigo',
                  value: '${_dangerZones.length}',
                  subtitle: 'Alerta Nível 1',
                  color: const Color(0xFFDC2626),
                  icon: Icons.gpp_maybe_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...zones.map((item) {
            final isSafe = item.zone.isSafe;
            final color =
                isSafe ? const Color(0xFF059669) : const Color(0xFFDC2626);
            final distMeters = _distanceCalc.as(
              LengthUnit.Meter,
              _userLocation,
              item.displayPoint,
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isSafe
                            ? Icons.verified_user_rounded
                            : Icons.warning_amber_rounded,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Nível ${item.zone.levelZone}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Coordenada no Mapa: ${item.displayPoint.latitude.toStringAsFixed(4)}, ${item.displayPoint.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'Raio: ${item.zone.radius.toStringAsFixed(0)}m • Distância até você: ${distMeters.toStringAsFixed(0)}m',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _focusOnZone(item),
                      icon: const Icon(Icons.map_rounded, size: 16),
                      label: const Text('Mapa'),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiAndPositionTab() {
    final urlController = TextEditingController(text: ApiConfig.baseUrl);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'GPS Real & Conexão Backend',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Capture sua localização real pelo GPS do dispositivo/navegador e envie para POST /api/me',
          style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _hasRealGpsLock
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_not_fixed_rounded,
                      color: _hasRealGpsLock
                          ? const Color(0xFF059669)
                          : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hasRealGpsLock
                            ? 'Localização GPS Real Ativa'
                            : 'Localização do Usuário (POST /api/me)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_gpsStatusText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _gpsStatusText!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text(
                            'LATITUDE (_latitude)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userLocation.latitude.toStringAsFixed(5),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: const Color(0xFFE2E8F0),
                      ),
                      Column(
                        children: [
                          const Text(
                            'LONGITUDE (_longitude)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userLocation.longitude.toStringAsFixed(5),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isFetchingGps
                            ? null
                            : () => _initRealGpsLocation(centerMap: true),
                        icon: const Icon(Icons.gps_fixed_rounded),
                        label: const Text('Capturar Meu GPS Real'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isUpdatingLocation
                            ? null
                            : () => _handleUpdateUserLocation(),
                        icon: _isUpdatingLocation
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text('Enviar POST /api/me'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dns_rounded, color: Color(0xFF0F172A)),
                    SizedBox(width: 8),
                    Text(
                      'Endereço do Backend (api_mobile)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'http://localhost:5239',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.link_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      ApiConfig.setBaseUrl(urlController.text);
                      _fetchAllZones();
                    },
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Salvar e Sincronizar com a API'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal_rounded, color: Color(0xFF0F172A)),
                        SizedBox(width: 8),
                        Text(
                          'Console de Requisições & GPS',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => setState(() => _apiLogs.clear()),
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _apiLogs.isEmpty
                      ? const Text(
                          'Nenhuma requisição registrada.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _apiLogs
                              .map(
                                (log) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      color: log.contains('ERRO')
                                          ? const Color(0xFFFCA5A5)
                                          : (log.contains('200 OK') ||
                                                  log.contains('GPS REAL'))
                                              ? const Color(0xFF6EE7B7)
                                              : Colors.white,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Servidor api_mobile Indisponível',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Não foi possível conectar em ${ApiConfig.baseUrl}\n($_errorMessage)',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _fetchAllZones,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar Novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
