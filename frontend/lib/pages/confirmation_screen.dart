import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/artwork.dart';
import '../services/database_service.dart';
import '../services/labeling_service.dart';

class ConfirmationScreen extends StatefulWidget {
  final XFile imageFile;
  final Position position;

  const ConfirmationScreen({
    super.key,
    required this.imageFile,
    required this.position,
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  bool _isSaving = false;

  // ML Kit tag suggestions
  List<String> _suggestedTags = [];
  final Set<String> _acceptedTags = {};
  bool _isLabeling = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestedTags();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestedTags() async {
    final tags = await LabelingService().suggestTags(widget.imageFile.path);
    if (mounted) {
      setState(() {
        _suggestedTags = tags;
        _acceptedTags.addAll(tags);
        _isLabeling = false;
      });
    }
  }

  /// Compresses the photo natively (off the UI thread) and writes both the
  /// full-size image and a small thumbnail for map markers.
  Future<({String imagePath, String thumbnailPath})>
      _processAndSaveImage() async {
    final directory = await getApplicationDocumentsDirectory();
    final uuid = const Uuid().v4();
    final imagePath = '${directory.path}/artwork_$uuid.jpg';
    final thumbnailPath = '${directory.path}/artwork_${uuid}_thumb.jpg';

    final image = await FlutterImageCompress.compressAndGetFile(
      widget.imageFile.path,
      imagePath,
      minWidth: 1920,
      minHeight: 1920,
      quality: 75,
    );
    if (image == null) {
      throw Exception('Failed to compress image');
    }

    final thumbnail = await FlutterImageCompress.compressAndGetFile(
      widget.imageFile.path,
      thumbnailPath,
      minWidth: 200,
      minHeight: 200,
      quality: 70,
    );
    if (thumbnail == null) {
      throw Exception('Failed to create thumbnail');
    }

    return (imagePath: imagePath, thumbnailPath: thumbnailPath);
  }

  List<String> _collectTags() {
    final manualTags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty);
    return {..._acceptedTags, ...manualTags}.toList();
  }

  Future<void> _saveArtwork() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final paths = await _processAndSaveImage();

      final tags = _collectTags();
      final artwork = Artwork(
        localImagePath: paths.imagePath,
        thumbnailPath: paths.thumbnailPath,
        latitude: widget.position.latitude,
        longitude: widget.position.longitude,
        timestamp: DateTime.now(),
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        tags: tags.isNotEmpty ? tags : null,
      );

      await DatabaseService.instance.saveArtwork(artwork);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      _showError('Failed to save artwork: $e');
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location =
        LatLng(widget.position.latitude, widget.position.longitude);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed:
                        _isSaving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Spacer(),
                  Text(
                    'Confirm Artwork',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // Balance the back button
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image preview
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.file(
                          File(widget.imageFile.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Location info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 20,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Location',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.position.latitude.toStringAsFixed(6)}, ${widget.position.longitude.toStringAsFixed(6)}',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Mini map
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 120,
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: location,
                                  initialZoom: 16.0,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.none,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'com.geoghost.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: location,
                                        width: 40,
                                        height: 40,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.red,
                                          size: 36,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Notes input
                    Text(
                      'Notes (Optional)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Add any notes about this artwork...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Tags input
                    Text(
                      'Tags (Optional)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Suggested tags from on-device image labeling
                    if (_isLabeling)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Analyzing photo...',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    else if (_suggestedTags.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _suggestedTags.map((tag) {
                          final selected = _acceptedTags.contains(tag);
                          return FilterChip(
                            label: Text(tag),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _acceptedTags.add(tag);
                                } else {
                                  _acceptedTags.remove(tag);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],

                    TextField(
                      controller: _tagsController,
                      decoration: InputDecoration(
                        hintText:
                            'graffiti, mural, street art (separate with commas)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveArtwork,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Saving...'),
                                ],
                              )
                            : const Text(
                                'Save Artwork',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
