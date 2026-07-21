import 'package:equatable/equatable.dart';
import '../models/artwork.dart';

enum MapStatus { initial, loading, loaded, error }

class MapState extends Equatable {
  final List<Artwork> allArtworks;
  final Artwork? selectedArtwork;
  final MapStatus status;
  final String? errorMessage;

  const MapState({
    this.allArtworks = const [],
    this.selectedArtwork,
    this.status = MapStatus.initial,
    this.errorMessage,
  });

  MapState copyWith({
    List<Artwork>? allArtworks,
    Artwork? selectedArtwork,
    MapStatus? status,
    String? errorMessage,
    bool clearSelectedArtwork = false,
  }) {
    return MapState(
      allArtworks: allArtworks ?? this.allArtworks,
      selectedArtwork: clearSelectedArtwork ? null : selectedArtwork ?? this.selectedArtwork,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [allArtworks, selectedArtwork, status, errorMessage];
}
