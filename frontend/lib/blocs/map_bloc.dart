import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/database_service.dart';
import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final DatabaseService _databaseService;

  MapBloc({required DatabaseService databaseService})
      : _databaseService = databaseService,
        super(const MapState()) {
    on<LoadArtworks>(_onLoadArtworks);
    on<SelectArtwork>(_onSelectArtwork);
  }

  Future<void> _onLoadArtworks(
    LoadArtworks event,
    Emitter<MapState> emit,
  ) async {
    emit(state.copyWith(status: MapStatus.loading));

    try {
      final artworks = await _databaseService.getAllArtworks();
      emit(state.copyWith(
        status: MapStatus.loaded,
        allArtworks: artworks,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: MapStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onSelectArtwork(
    SelectArtwork event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(
      selectedArtwork: event.artwork,
      clearSelectedArtwork: event.artwork == null,
    ));
  }
}
