class Artwork {
  final int? id;
  final String localImagePath;
  final String? thumbnailPath;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? notes;
  final List<String>? tags;

  const Artwork({
    this.id,
    required this.localImagePath,
    this.thumbnailPath,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.notes,
    this.tags,
  });
}
