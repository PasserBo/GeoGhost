import 'package:equatable/equatable.dart';
import '../models/artwork.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

class LoadArtworks extends MapEvent {
  const LoadArtworks();
}

class SelectArtwork extends MapEvent {
  final Artwork? artwork;

  const SelectArtwork(this.artwork);

  @override
  List<Object?> get props => [artwork];
}
