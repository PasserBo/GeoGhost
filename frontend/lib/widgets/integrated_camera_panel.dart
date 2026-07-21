import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../pages/confirmation_screen.dart';

/// Camera panel shown in the bottom sheet.
///
/// The camera is only initialized while the panel is open past
/// [_cameraThreshold] and is fully disposed when it slides back down, so the
/// device doesn't heat up while the user is just browsing the map.
class IntegratedCameraPanel extends StatefulWidget {
  final double panelPosition;
  final Function(bool)? onCameraStateChanged;
  final VoidCallback? onPhotoTaken;

  const IntegratedCameraPanel({
    super.key,
    required this.panelPosition,
    this.onCameraStateChanged,
    this.onPhotoTaken,
  });

  @override
  State<IntegratedCameraPanel> createState() => _IntegratedCameraPanelState();
}

class _IntegratedCameraPanelState extends State<IntegratedCameraPanel>
    with WidgetsBindingObserver {
  static const double _cameraThreshold = 0.2;

  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isPermissionGranted = false;
  bool _isRequestingPermissions = false;
  bool _isInitializingCamera = false;
  String? _permissionError;
  bool _showCameraPreview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showCameraPreview = widget.panelPosition > _cameraThreshold;
    // Only ask for permissions up front; the camera itself starts lazily
    // when the panel is opened.
    _requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseCamera();
    super.dispose();
  }

  @override
  void didUpdateWidget(IntegratedCameraPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldShowCamera = widget.panelPosition > _cameraThreshold;
    if (shouldShowCamera != _showCameraPreview) {
      setState(() {
        _showCameraPreview = shouldShowCamera;
      });
      widget.onCameraStateChanged?.call(shouldShowCamera);

      if (shouldShowCamera) {
        _initializeCamera();
      } else {
        _disposeCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_showCameraPreview) {
        _initializeCamera();
      }
    }
  }

  /// Releases the camera without touching widget state; safe to call from
  /// dispose().
  void _releaseCamera() {
    final controller = _controller;
    _controller = null;
    _isCameraInitialized = false;
    controller?.dispose();
  }

  void _disposeCamera() {
    setState(_releaseCamera);
  }

  Future<void> _requestPermissions() async {
    if (_isRequestingPermissions) return;

    setState(() {
      _isRequestingPermissions = true;
      _permissionError = null;
    });

    try {
      final cameraStatus = await Permission.camera.request();
      final locationStatus = await Permission.location.request();

      if (cameraStatus.isGranted && locationStatus.isGranted) {
        setState(() {
          _isPermissionGranted = true;
        });
        // If the user opened the panel while the permission dialogs were up,
        // start the camera now.
        if (_showCameraPreview) {
          _initializeCamera();
        }
      } else {
        String error = 'Required permissions:\n';
        if (!cameraStatus.isGranted) {
          error += '• Camera access needed to take photos\n';
        }
        if (!locationStatus.isGranted) {
          error += '• Location access needed to tag artwork location';
        }

        setState(() {
          _isPermissionGranted = false;
          _permissionError = error;
        });
      }
    } catch (e) {
      setState(() {
        _isPermissionGranted = false;
        _permissionError = 'Failed to request permissions: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermissions = false;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (!_isPermissionGranted ||
        _isInitializingCamera ||
        _isCameraInitialized) {
      return;
    }

    setState(() {
      _isInitializingCamera = true;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _permissionError = 'No cameras available on this device';
          _isInitializingCamera = false;
        });
        return;
      }

      // Medium resolution keeps the preview cheap; final photo quality is
      // still plenty for a 1920px stored image.
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      // The panel may have been closed (or the widget disposed) while we were
      // waiting — release the camera immediately in that case.
      if (!mounted || !_showCameraPreview) {
        await controller.dispose();
        if (mounted) {
          setState(() {
            _isInitializingCamera = false;
          });
        }
        return;
      }

      setState(() {
        _controller = controller;
        _isCameraInitialized = true;
        _isInitializingCamera = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _permissionError = 'Failed to initialize camera: $e';
          _isInitializingCamera = false;
        });
      }
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    var dialogOpen = false;
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
      dialogOpen = true;

      final XFile image = await controller.takePicture();

      // Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (e) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (e) {
          position = await Geolocator.getLastKnownPosition();
        }
      }

      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (position == null) {
        _showLocationError();
        return;
      }

      if (mounted) {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => ConfirmationScreen(
              imageFile: image,
              position: position!,
            ),
          ),
        );

        if (result == true) {
          widget.onPhotoTaken?.call();
        }
      }
    } catch (e) {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showError('Failed to take picture: $e');
    }
  }

  void _showLocationError() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Error'),
        content: const Text(
          'Unable to get your current location. Please ensure location services are enabled and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Content based on panel position and camera state
          Expanded(
            child: _showCameraPreview ? _buildCameraView() : _buildInitialView(),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Camera icon button
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _isPermissionGranted
                  ? Theme.of(context).primaryColor
                  : Colors.grey[400],
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isPermissionGranted
                          ? Theme.of(context).primaryColor
                          : Colors.grey[400]!)
                      .withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isRequestingPermissions
                ? const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  )
                : Icon(
                    _isPermissionGranted
                        ? Icons.camera_alt
                        : Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 36,
                  ),
          ),

          const SizedBox(height: 16),

          // Status text
          Text(
            _isPermissionGranted
                ? 'Capture Street Art'
                : 'Camera Setup Required',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _isPermissionGranted
                ? 'Swipe up to use camera'
                : 'Grant permissions to continue',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),

          // Permission error or swipe hint
          if (_permissionError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    _permissionError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _requestPermissions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade100,
                      foregroundColor: Colors.orange.shade700,
                      elevation: 0,
                    ),
                    child: const Text('Grant Permissions'),
                  ),
                ],
              ),
            ),
          ] else if (_isPermissionGranted) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.grey[400],
                  size: 20,
                ),
                Text(
                  'Swipe up for camera',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[400],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_isPermissionGranted) {
      return _buildPermissionError();
    }

    if (!_isCameraInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Camera preview
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CameraPreview(_controller!),
            ),
          ),
        ),

        // Camera controls
        Container(
          padding: const EdgeInsets.all(32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Capture button
              GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              _permissionError ?? 'Permissions required',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _requestPermissions,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('Grant Permissions'),
            ),
          ],
        ),
      ),
    );
  }
}
