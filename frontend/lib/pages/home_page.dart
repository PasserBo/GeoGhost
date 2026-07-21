import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../blocs/map_bloc.dart';
import '../blocs/map_event.dart';
import '../blocs/map_state.dart';
import '../models/artwork.dart';
import '../services/database_service.dart';
import '../widgets/integrated_camera_panel.dart';
import '../widgets/artwork_preview_panel.dart';

const _defaultLocation = LatLng(37.7749, -122.4194); // San Francisco

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MapBloc(
        databaseService: DatabaseService.instance,
      )..add(const LoadArtworks()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  static const double _sheetMinSize = 0.12;
  static const double _sheetMaxSize = 0.9;
  static const double _sheetPreviewSize = 0.45;

  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  LatLng? _currentLocation;
  bool _isLoadingLocation = true;
  String? _locationError;

  /// Sheet position normalized to 0 (closed) .. 1 (fully open); drives the
  /// camera panel's lazy start/stop. A ValueNotifier so drags only rebuild
  /// the panel, not the whole page (the map would repaint every frame).
  final ValueNotifier<double> _panelPosition = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetChanged);
    _initializeLocation();
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    _panelPosition.dispose();
    super.dispose();
  }

  void _onSheetChanged() {
    _panelPosition.value = ((_sheetController.size - _sheetMinSize) /
            (_sheetMaxSize - _sheetMinSize))
        .clamp(0.0, 1.0);
  }

  Future<void> _animateSheetTo(double size) async {
    if (!_sheetController.isAttached) return;
    await _sheetController.animateTo(
      size,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });

      _mapController.move(_currentLocation!, 15.0);
    } catch (e) {
      setState(() {
        _locationError = e.toString();
        _isLoadingLocation = false;
      });
      debugPrint('Error getting location: $e');
    }
  }

  void _onArtworkTapped(BuildContext context, Artwork artwork) {
    context.read<MapBloc>().add(SelectArtwork(artwork));
    _mapController.move(LatLng(artwork.latitude, artwork.longitude),
        _mapController.camera.zoom);
    _animateSheetTo(_sheetPreviewSize);
  }

  void _closeSelection(BuildContext context) {
    context.read<MapBloc>().add(const SelectArtwork(null));
    _animateSheetTo(_sheetMinSize);
  }

  List<Marker> _buildMarkers(BuildContext context, List<Artwork> artworks) {
    return artworks.map((artwork) {
      return Marker(
        point: LatLng(artwork.latitude, artwork.longitude),
        width: 48,
        height: 48,
        child: GestureDetector(
          onTap: () => _onArtworkTapped(context, artwork),
          child: _ArtworkMarker(artwork: artwork),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          BlocBuilder<MapBloc, MapState>(
            builder: (context, state) {
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? _defaultLocation,
                  initialZoom: 15.0,
                  onTap: (tapPosition, latLng) => _closeSelection(context),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.geoghost.app',
                  ),
                  if (_currentLocation != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _currentLocation!,
                          radius: 8,
                          color: Colors.blue.withValues(alpha: 0.8),
                          borderColor: Colors.white,
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: _buildMarkers(context, state.allArtworks),
                  ),
                  const SimpleAttributionWidget(
                    source: Text('OpenStreetMap contributors'),
                  ),
                ],
              );
            },
          ),

          // My-location button, kept above the collapsed sheet
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height * _sheetMinSize + 24,
            child: FloatingActionButton.small(
              heroTag: 'my_location',
              backgroundColor: Colors.white,
              foregroundColor: Colors.grey[800],
              onPressed: () {
                if (_currentLocation != null) {
                  _mapController.move(_currentLocation!, 15.0);
                } else {
                  _initializeLocation();
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          if (_isLoadingLocation) _buildLocationBanner(),
          if (_locationError != null && !_isLoadingLocation)
            _buildLocationErrorBanner(),

          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _sheetMinSize,
            minChildSize: _sheetMinSize,
            maxChildSize: _sheetMaxSize,
            snap: true,
            snapSizes: const [_sheetPreviewSize],
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  height:
                      MediaQuery.of(context).size.height * _sheetMaxSize,
                  child: _buildSheetContent(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSheetContent(BuildContext context) {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        if (state.selectedArtwork != null) {
          return ArtworkPreviewPanel(
            artwork: state.selectedArtwork!,
            onClose: () => _closeSelection(context),
          );
        }
        return ValueListenableBuilder<double>(
          valueListenable: _panelPosition,
          builder: (context, position, _) {
            return IntegratedCameraPanel(
              panelPosition: position,
              onPhotoTaken: () {
                context.read<MapBloc>().add(const LoadArtworks());
                _animateSheetTo(_sheetMinSize);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLocationBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Getting your location...',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationErrorBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.location_off,
                    color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Location Error',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Unable to get your location. Using default location.',
              style: TextStyle(fontSize: 14, color: Colors.orange.shade700),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _initializeLocation,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade700,
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular photo-thumbnail marker; falls back to a paint icon when the
/// thumbnail is missing.
class _ArtworkMarker extends StatelessWidget {
  final Artwork artwork;

  const _ArtworkMarker({required this.artwork});

  @override
  Widget build(BuildContext context) {
    final thumbPath = artwork.thumbnailPath;
    final hasThumb = thumbPath != null && File(thumbPath).existsSync();

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.deepOrange, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: hasThumb
            ? Image.file(
                File(thumbPath),
                fit: BoxFit.cover,
              )
            : const Icon(
                Icons.format_paint,
                color: Colors.deepOrange,
                size: 22,
              ),
      ),
    );
  }
}
