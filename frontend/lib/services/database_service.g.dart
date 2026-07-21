// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_service.dart';

// ignore_for_file: type=lint
class $ArtworksTable extends Artworks
    with TableInfo<$ArtworksTable, ArtworkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtworksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localImagePathMeta = const VerificationMeta(
    'localImagePath',
  );
  @override
  late final GeneratedColumn<String> localImagePath = GeneratedColumn<String>(
    'local_image_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localImagePath,
    thumbnailPath,
    latitude,
    longitude,
    timestamp,
    notes,
    tags,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artworks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArtworkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_image_path')) {
      context.handle(
        _localImagePathMeta,
        localImagePath.isAcceptableOrUnknown(
          data['local_image_path']!,
          _localImagePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localImagePathMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArtworkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArtworkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_image_path'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      ),
    );
  }

  @override
  $ArtworksTable createAlias(String alias) {
    return $ArtworksTable(attachedDatabase, alias);
  }
}

class ArtworkRow extends DataClass implements Insertable<ArtworkRow> {
  final int id;
  final String localImagePath;
  final String? thumbnailPath;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? notes;
  final String? tags;
  const ArtworkRow({
    required this.id,
    required this.localImagePath,
    this.thumbnailPath,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.notes,
    this.tags,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_image_path'] = Variable<String>(localImagePath);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || tags != null) {
      map['tags'] = Variable<String>(tags);
    }
    return map;
  }

  ArtworksCompanion toCompanion(bool nullToAbsent) {
    return ArtworksCompanion(
      id: Value(id),
      localImagePath: Value(localImagePath),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      latitude: Value(latitude),
      longitude: Value(longitude),
      timestamp: Value(timestamp),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      tags: tags == null && nullToAbsent ? const Value.absent() : Value(tags),
    );
  }

  factory ArtworkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArtworkRow(
      id: serializer.fromJson<int>(json['id']),
      localImagePath: serializer.fromJson<String>(json['localImagePath']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      notes: serializer.fromJson<String?>(json['notes']),
      tags: serializer.fromJson<String?>(json['tags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localImagePath': serializer.toJson<String>(localImagePath),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'notes': serializer.toJson<String?>(notes),
      'tags': serializer.toJson<String?>(tags),
    };
  }

  ArtworkRow copyWith({
    int? id,
    String? localImagePath,
    Value<String?> thumbnailPath = const Value.absent(),
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    Value<String?> notes = const Value.absent(),
    Value<String?> tags = const Value.absent(),
  }) => ArtworkRow(
    id: id ?? this.id,
    localImagePath: localImagePath ?? this.localImagePath,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    timestamp: timestamp ?? this.timestamp,
    notes: notes.present ? notes.value : this.notes,
    tags: tags.present ? tags.value : this.tags,
  );
  ArtworkRow copyWithCompanion(ArtworksCompanion data) {
    return ArtworkRow(
      id: data.id.present ? data.id.value : this.id,
      localImagePath: data.localImagePath.present
          ? data.localImagePath.value
          : this.localImagePath,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      notes: data.notes.present ? data.notes.value : this.notes,
      tags: data.tags.present ? data.tags.value : this.tags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArtworkRow(')
          ..write('id: $id, ')
          ..write('localImagePath: $localImagePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('timestamp: $timestamp, ')
          ..write('notes: $notes, ')
          ..write('tags: $tags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    localImagePath,
    thumbnailPath,
    latitude,
    longitude,
    timestamp,
    notes,
    tags,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArtworkRow &&
          other.id == this.id &&
          other.localImagePath == this.localImagePath &&
          other.thumbnailPath == this.thumbnailPath &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.timestamp == this.timestamp &&
          other.notes == this.notes &&
          other.tags == this.tags);
}

class ArtworksCompanion extends UpdateCompanion<ArtworkRow> {
  final Value<int> id;
  final Value<String> localImagePath;
  final Value<String?> thumbnailPath;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<DateTime> timestamp;
  final Value<String?> notes;
  final Value<String?> tags;
  const ArtworksCompanion({
    this.id = const Value.absent(),
    this.localImagePath = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.notes = const Value.absent(),
    this.tags = const Value.absent(),
  });
  ArtworksCompanion.insert({
    this.id = const Value.absent(),
    required String localImagePath,
    this.thumbnailPath = const Value.absent(),
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    this.notes = const Value.absent(),
    this.tags = const Value.absent(),
  }) : localImagePath = Value(localImagePath),
       latitude = Value(latitude),
       longitude = Value(longitude),
       timestamp = Value(timestamp);
  static Insertable<ArtworkRow> custom({
    Expression<int>? id,
    Expression<String>? localImagePath,
    Expression<String>? thumbnailPath,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<DateTime>? timestamp,
    Expression<String>? notes,
    Expression<String>? tags,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localImagePath != null) 'local_image_path': localImagePath,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (timestamp != null) 'timestamp': timestamp,
      if (notes != null) 'notes': notes,
      if (tags != null) 'tags': tags,
    });
  }

  ArtworksCompanion copyWith({
    Value<int>? id,
    Value<String>? localImagePath,
    Value<String?>? thumbnailPath,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<DateTime>? timestamp,
    Value<String?>? notes,
    Value<String?>? tags,
  }) {
    return ArtworksCompanion(
      id: id ?? this.id,
      localImagePath: localImagePath ?? this.localImagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localImagePath.present) {
      map['local_image_path'] = Variable<String>(localImagePath.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtworksCompanion(')
          ..write('id: $id, ')
          ..write('localImagePath: $localImagePath, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('timestamp: $timestamp, ')
          ..write('notes: $notes, ')
          ..write('tags: $tags')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ArtworksTable artworks = $ArtworksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [artworks];
}

typedef $$ArtworksTableCreateCompanionBuilder =
    ArtworksCompanion Function({
      Value<int> id,
      required String localImagePath,
      Value<String?> thumbnailPath,
      required double latitude,
      required double longitude,
      required DateTime timestamp,
      Value<String?> notes,
      Value<String?> tags,
    });
typedef $$ArtworksTableUpdateCompanionBuilder =
    ArtworksCompanion Function({
      Value<int> id,
      Value<String> localImagePath,
      Value<String?> thumbnailPath,
      Value<double> latitude,
      Value<double> longitude,
      Value<DateTime> timestamp,
      Value<String?> notes,
      Value<String?> tags,
    });

class $$ArtworksTableFilterComposer
    extends Composer<_$AppDatabase, $ArtworksTable> {
  $$ArtworksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArtworksTableOrderingComposer
    extends Composer<_$AppDatabase, $ArtworksTable> {
  $$ArtworksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArtworksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArtworksTable> {
  $$ArtworksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);
}

class $$ArtworksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArtworksTable,
          ArtworkRow,
          $$ArtworksTableFilterComposer,
          $$ArtworksTableOrderingComposer,
          $$ArtworksTableAnnotationComposer,
          $$ArtworksTableCreateCompanionBuilder,
          $$ArtworksTableUpdateCompanionBuilder,
          (
            ArtworkRow,
            BaseReferences<_$AppDatabase, $ArtworksTable, ArtworkRow>,
          ),
          ArtworkRow,
          PrefetchHooks Function()
        > {
  $$ArtworksTableTableManager(_$AppDatabase db, $ArtworksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtworksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtworksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtworksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> localImagePath = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> tags = const Value.absent(),
              }) => ArtworksCompanion(
                id: id,
                localImagePath: localImagePath,
                thumbnailPath: thumbnailPath,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                notes: notes,
                tags: tags,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String localImagePath,
                Value<String?> thumbnailPath = const Value.absent(),
                required double latitude,
                required double longitude,
                required DateTime timestamp,
                Value<String?> notes = const Value.absent(),
                Value<String?> tags = const Value.absent(),
              }) => ArtworksCompanion.insert(
                id: id,
                localImagePath: localImagePath,
                thumbnailPath: thumbnailPath,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                notes: notes,
                tags: tags,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArtworksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArtworksTable,
      ArtworkRow,
      $$ArtworksTableFilterComposer,
      $$ArtworksTableOrderingComposer,
      $$ArtworksTableAnnotationComposer,
      $$ArtworksTableCreateCompanionBuilder,
      $$ArtworksTableUpdateCompanionBuilder,
      (ArtworkRow, BaseReferences<_$AppDatabase, $ArtworksTable, ArtworkRow>),
      ArtworkRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ArtworksTableTableManager get artworks =>
      $$ArtworksTableTableManager(_db, _db.artworks);
}
