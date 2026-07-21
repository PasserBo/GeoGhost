import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/artwork.dart';

part 'database_service.g.dart';

@DataClassName('ArtworkRow')
class Artworks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localImagePath => text()();
  TextColumn get thumbnailPath => text().nullable()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get notes => text().nullable()();
  // JSON-encoded List<String>
  TextColumn get tags => text().nullable()();
}

@DriftDatabase(tables: [Artworks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'geoghost'));

  @override
  int get schemaVersion => 1;
}

class DatabaseService {
  static DatabaseService? _instance;
  AppDatabase? _db;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<void> initialize() async {
    _db ??= AppDatabase();
  }

  AppDatabase get db {
    if (_db == null) {
      throw Exception('DatabaseService not initialized. Call initialize() first.');
    }
    return _db!;
  }

  Future<int> saveArtwork(Artwork artwork) {
    return db.into(db.artworks).insert(
          ArtworksCompanion.insert(
            localImagePath: artwork.localImagePath,
            thumbnailPath: Value(artwork.thumbnailPath),
            latitude: artwork.latitude,
            longitude: artwork.longitude,
            timestamp: artwork.timestamp,
            notes: Value(artwork.notes),
            tags: Value(
              artwork.tags == null ? null : jsonEncode(artwork.tags),
            ),
          ),
        );
  }

  Future<List<Artwork>> getAllArtworks() async {
    final rows = await (db.select(db.artworks)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<Artwork?> getArtworkById(int id) async {
    final row = await (db.select(db.artworks)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<void> deleteArtwork(int id) async {
    await (db.delete(db.artworks)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Artwork>> getArtworksInRadius(
    double centerLat,
    double centerLng,
    double radiusKm,
  ) async {
    // Simple bounding box filter - for MVP
    final latDelta = radiusKm / 111.32;
    final lngDelta = radiusKm / (111.32 * cos(centerLat * pi / 180));

    final rows = await (db.select(db.artworks)
          ..where((t) =>
              t.latitude.isBetweenValues(
                  centerLat - latDelta, centerLat + latDelta) &
              t.longitude.isBetweenValues(
                  centerLng - lngDelta, centerLng + lngDelta)))
        .get();
    return rows.map(_toModel).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Artwork _toModel(ArtworkRow row) {
    return Artwork(
      id: row.id,
      localImagePath: row.localImagePath,
      thumbnailPath: row.thumbnailPath,
      latitude: row.latitude,
      longitude: row.longitude,
      timestamp: row.timestamp,
      notes: row.notes,
      tags: row.tags == null
          ? null
          : (jsonDecode(row.tags!) as List).cast<String>(),
    );
  }
}
