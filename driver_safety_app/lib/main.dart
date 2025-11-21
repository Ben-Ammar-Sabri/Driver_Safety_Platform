import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image/image.dart' as img;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({required this.cameras, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Driver Safety Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00E676),
          secondary: const Color(0xFFFF5252),
          surface: const Color(0xFF1D1E33),
        ),
      ),
      home: DriverSafetyScreen(cameras: cameras),
    );
  }
}

class DriverSafetyScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DriverSafetyScreen({required this.cameras, Key? key}) : super(key: key);

  @override
  State<DriverSafetyScreen> createState() => _DriverSafetyScreenState();
}

class _DriverSafetyScreenState extends State<DriverSafetyScreen>
    with TickerProviderStateMixin {
  CameraController? _driverCam;
  CameraController? _roadCam;
  late AnimationController _borderAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseAnimation;
  
  IOWebSocketChannel? _channel;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isMonitoring = false;
  bool _cameraEnabled = true;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  
  double _score = 85.0;
  double _speed = 0.0; // Changed to actual speed from GPS
  double _acceleration = 0.0;
  Color _borderColor = Colors.transparent;
  String _alertMessage = '';
  Timer? _dataTimer;

  // Map and GPS variables
  Completer<GoogleMapController> _mapController = Completer();
  static final CameraPosition _initialPosition = CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 14.0,
  );
  Set<Marker> _markers = {};
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  double _previousSpeed = 0.0;
  DateTime? _previousSpeedTime;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCameras();
    _connectWebSocket();
    _initializeLocationService();
  }

  void _initializeLocationService() async {
    // Check permissions
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ Location permissions are denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Location permissions are permanently denied');
      return;
    }

    // Start listening to location updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1, // Update every 1 meter
      ),
    ).listen((Position position) {
      _updatePosition(position);
    });

    // Get initial position
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      _updatePosition(position);
    } catch (e) {
      debugPrint('❌ Error getting initial position: $e');
    }
  }

  void _updatePosition(Position position) {
    final now = DateTime.now();
    
    setState(() {
      _currentPosition = position;
      _speed = position.speed * 3.6; // Convert m/s to km/h
      
      // Calculate acceleration (m/s²)
      if (_previousSpeedTime != null) {
        final timeDiff = now.difference(_previousSpeedTime!).inSeconds;
        if (timeDiff > 0) {
          final speedDiff = (_speed - _previousSpeed) / 3.6; // Convert km/h to m/s
          _acceleration = speedDiff / timeDiff;
        }
      }
      
      _previousSpeed = _speed;
      _previousSpeedTime = now;
    });

    // Update map marker
    _updateMapMarker(position);
  }

  void _updateMapMarker(Position position) {
    final newPosition = LatLng(position.latitude, position.longitude);
    
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: MarkerId('current_location'),
          position: newPosition,
          infoWindow: InfoWindow(
            title: 'Position actuelle',
            snippet: 'Vitesse: ${_speed.toStringAsFixed(1)} km/h',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });

    // Update camera position if map is ready
    _mapController.future.then((controller) {
      controller.animateCamera(
        CameraUpdate.newLatLng(newPosition),
      );
    });
  }

  void _initializeAnimations() {
    _borderAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _initializeCameras() async {
    if (!_cameraEnabled || widget.cameras.isEmpty) return;
    
    try {
      debugPrint('🔍 Nombre de caméras disponibles: ${widget.cameras.length}');
      
      for (int i = 0; i < widget.cameras.length; i++) {
        debugPrint('📷 Caméra $i: ${widget.cameras[i].lensDirection} - ${widget.cameras[i].name}');
      }
      
      CameraDescription? frontCamera;
      
      for (var camera in widget.cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          debugPrint('✅ Caméra frontale trouvée: ${camera.name}');
          break;
        }
      }

      if (frontCamera == null && widget.cameras.length > 1) {
        frontCamera = widget.cameras[1];
        debugPrint('⚠️ Utilisation caméra index 1 (supposée frontale)');
      } else if (frontCamera == null && widget.cameras.isNotEmpty) {
        frontCamera = widget.cameras[0];
        debugPrint('⚠️ Une seule caméra trouvée, utilisation de celle-ci');
      }

      if (frontCamera == null) {
        throw Exception('Aucune caméra disponible');
      }

      _driverCam = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _driverCam!.initialize();
      debugPrint('✅ Caméra conducteur (frontale) initialisée: ${_driverCam!.value.previewSize}');

      _roadCam = _driverCam;
      debugPrint('✅ Même caméra utilisée pour les deux vues');

      if (mounted) {
        setState(() => _isCameraInitialized = true);
        debugPrint('🎉 Caméra frontale prête!');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ERREUR initialisation caméras: $e');
      debugPrint('📋 StackTrace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur caméra: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _connectWebSocket() {
    try {
      // IMPORTANT: Change this IP to your backend server IP
      _channel = IOWebSocketChannel.connect('ws://192.168.1.159:8765/ws');
      debugPrint('🔌 Tentative de connexion WebSocket...');
      
      _channel?.stream.listen(
        (message) {
          debugPrint('📨 Message WebSocket reçu: $message');
          try {
            final alert = jsonDecode(message);
            debugPrint('🔔 Alert décodé: $alert');
            _handleAlert(alert);
          } catch (e) {
            debugPrint('❌ Erreur décodage JSON: $e');
          }
        },
        onError: (error) {
          debugPrint('❌ WebSocket erreur: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur WebSocket: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onDone: () {
          debugPrint('⚠️ WebSocket connexion fermée');
        },
      );
      
      debugPrint('✅ WebSocket connecté');
    } catch (e) {
      debugPrint('❌ Connexion WebSocket échouée: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de se connecter au serveur: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _handleAlert(Map<String, dynamic> alert) {
    debugPrint('🔔 Traitement alert: $alert');
    
    final message = alert['message'] ?? alert['status'] ?? '';
    final isCritical = alert['critical'] == true;
    
    debugPrint('  - message: $message');
    debugPrint('  - critical: $isCritical');
    
    if (message != 'OK' && message.isNotEmpty) {
      _triggerAlert(isAlarm: isCritical, message: message);
      _updateScore(isCritical ? -5 : -2);
    }
  }

  Future<void> _triggerAlert({required bool isAlarm, String message = ''}) async {
    debugPrint('🚨 Déclenchement alert: isAlarm=$isAlarm, message=$message');
    
    setState(() {
      _borderColor = isAlarm ? const Color(0xFFFF1744) : const Color(0xFFFF9100);
      _alertMessage = message.isNotEmpty ? message : (isAlarm ? 'ALARME!' : 'Avertissement');
    });

    _borderAnimationController.forward(from: 0).then((_) {
      _borderAnimationController.reverse();
    });
    
    try {
      final soundPath = isAlarm ? 'alarm.wav' : 'warning.wav';
      debugPrint('🔊 Tentative lecture du son: $soundPath');
      
      await _audioPlayer.stop();
      await _audioPlayer.play(
        AssetSource('sounds/$soundPath'),
        volume: 1.0,
        mode: PlayerMode.lowLatency,
      );
      
      debugPrint('✅ Son joué: $soundPath');
    } catch (e) {
      debugPrint('❌ Erreur son: $e');
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _borderColor = Colors.transparent;
          _alertMessage = '';
        });
      }
    });
  }

  void _updateScore(double delta) {
    setState(() {
      _score = (_score + delta).clamp(0.0, 100.0);
    });
  }

  void _toggleCameras() {
    setState(() {
      _cameraEnabled = !_cameraEnabled;
    });

    if (_cameraEnabled) {
      _initializeCameras();
    } else {
      _stopMonitoring();
      _driverCam?.dispose();
      _roadCam?.dispose();
      _driverCam = null;
      _roadCam = null;
      _isCameraInitialized = false;
    }
  }

  void _toggleMonitoring() {
    if (!_cameraEnabled || !_isCameraInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez activer les caméras d\'abord'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isMonitoring = !_isMonitoring);

    if (_isMonitoring) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }
  }

  void _startMonitoring() {
    debugPrint('🚀 Démarrage de la surveillance...');
    
    _frameCount = 0;
    _lastFrameTime = DateTime.now();
    
    if (_driverCam?.value.isInitialized == true) {
      _driverCam!.startImageStream((CameraImage image) {
        final now = DateTime.now();
        final timeSinceLastFrame = _lastFrameTime != null 
            ? now.difference(_lastFrameTime!).inMilliseconds 
            : 1000;
        
        if (!_isProcessingFrame && timeSinceLastFrame >= 500) {
          _isProcessingFrame = true;
          _lastFrameTime = now;
          _sendFrame(image, "driver");
        }
      });
    }
    
    debugPrint('✅ Surveillance active');
  }

  void _stopMonitoring() {
    debugPrint('⏹️ Arrêt de la surveillance...');
    
    _dataTimer?.cancel();
    
    try {
      _driverCam?.stopImageStream();
      _isProcessingFrame = false;
    } catch (e) {
      debugPrint('❌ Erreur arrêt stream: $e');
    }
    
    debugPrint('✅ Surveillance arrêtée (${_frameCount} frames envoyés)');
  }

  Future<void> _sendFrame(CameraImage image, String camType) async {
    try {
      _frameCount++;
      
      final int width = image.width;
      final int height = image.height;
      
      final int targetWidth = 320;
      final int targetHeight = (height * targetWidth / width).round();
      
      final imgBuffer = img.Image(width: targetWidth, height: targetHeight);
      
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;
      
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      
      final double scaleX = width / targetWidth;
      final double scaleY = height / targetHeight;
      
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final int srcX = (x * scaleX).round();
          final int srcY = (y * scaleY).round();
          
          final int yIndex = srcY * width + srcX;
          final int uvIndex = (srcY ~/ 2) * uvRowStride + (srcX ~/ 2) * uvPixelStride;
          
          if (yIndex < yPlane.length && uvIndex < uPlane.length && uvIndex < vPlane.length) {
            final int yValue = yPlane[yIndex];
            final int uValue = uPlane[uvIndex];
            final int vValue = vPlane[uvIndex];
            
            int r = (yValue + 1.370705 * (vValue - 128)).round().clamp(0, 255);
            int g = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128)).round().clamp(0, 255);
            int b = (yValue + 1.732446 * (uValue - 128)).round().clamp(0, 255);
            
            imgBuffer.setPixelRgba(x, y, r, g, b, 255);
          }
        }
      }

      final jpeg = img.encodeJpg(imgBuffer, quality: 80);
      final base64String = base64Encode(jpeg);

      final payload = jsonEncode({
        'camera': camType,
        'frame': base64String,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _channel?.sink.add(payload);
      
      if (_frameCount % 5 == 0) {
        final fps = _lastFrameTime != null 
            ? 1000 / DateTime.now().difference(_lastFrameTime!).inMilliseconds 
            : 0;
        debugPrint('📤 Frame #$_frameCount envoyé: ${imgBuffer.width}x${imgBuffer.height}, '
                   'taille: ${(base64String.length / 1024).toStringAsFixed(1)} KB, '
                   'FPS: ${fps.toStringAsFixed(1)}');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ Erreur envoi frame: $e');
      debugPrint('Stack: $stackTrace');
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 Nettoyage des ressources...');
    
    _borderAnimationController.dispose();
    _pulseAnimationController.dispose();
    _dataTimer?.cancel();
    _positionStream?.cancel();
    
    try {
      _driverCam?.stopImageStream();
    } catch (e) {
      debugPrint('Erreur lors de l\'arrêt du stream: $e');
    }
    
    _driverCam?.dispose();
    _roadCam?.dispose();
    _channel?.sink.close();
    _audioPlayer.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildCameraViews(),
                Expanded(child: _buildMainContent()),
                _buildControlPanel(),
              ],
            ),
          ),
          if (_borderColor != Colors.transparent)
            AnimatedBuilder(
              animation: _borderAnimationController,
              builder: (context, child) {
                return IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _borderColor.withOpacity(_borderAnimationController.value),
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    margin: const EdgeInsets.all(4),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCameraViews() {
    return Container(
      height: 140,
      margin: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(child: _buildCameraCard(_driverCam, 'Caméra Selfie', Icons.camera_front)),
          const SizedBox(width: 8),
          Expanded(child: _buildCameraCard(_roadCam, 'Vue Conducteur', Icons.person)),
        ],
      ),
    );
  }

  Widget _buildCameraCard(CameraController? controller, String label, IconData icon) {
    final isActive = controller?.value.isInitialized == true;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.green.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          width: 2,
        ),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            isActive
                ? CameraPreview(controller!)
                : Center(
                    child: Icon(
                      icon,
                      size: 48,
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            if (_isMonitoring && isActive)
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          if (_alertMessage.isNotEmpty) _buildAlertBanner(),
          const SizedBox(height: 12),
          _buildScoreCircle(),
          const SizedBox(height: 16),
          _buildMetricsRow(),
          const SizedBox(height: 12),
          Expanded(child: _buildMap()),
        ],
      ),
    );
  }

  Widget _buildAlertBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _borderColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _borderColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _alertMessage,
              style: TextStyle(
                color: _borderColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCircle() {
    final scoreColor = _score >= 80
        ? const Color(0xFF00E676)
        : _score >= 50
            ? const Color(0xFFFFD600)
            : const Color(0xFFFF5252);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            value: _score / 100,
            strokeWidth: 10,
            color: scoreColor,
            backgroundColor: Colors.white.withOpacity(0.1),
          ),
        ),
        Column(
          children: [
            Text(
              '${_score.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
            const Text(
              'Score',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.speed,
            title: 'Vitesse',
            value: _speed.toStringAsFixed(1),
            unit: 'km/h',
            color: const Color(0xFF2196F3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.trending_up,
            title: 'Accélération',
            value: _acceleration.toStringAsFixed(1),
            unit: 'm/s²',
            color: const Color(0xFFFF9800),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
              children: [
                TextSpan(text: value),
                TextSpan(text: ' $unit', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          mapType: MapType.normal,
          initialCameraPosition: _initialPosition,
          markers: _markers,
          onMapCreated: (GoogleMapController controller) {
            _mapController.complete(controller);
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggleCameras,
              icon: Icon(_cameraEnabled ? Icons.videocam : Icons.videocam_off),
              label: Text(
                _cameraEnabled ? 'Désactiver Caméras' : 'Activer Caméras',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cameraEnabled 
                    ? const Color(0xFF00E676)
                    : Colors.grey[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggleMonitoring,
              icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow, size: 24),
              label: Text(
                _isMonitoring ? 'Arrêter Surveillance' : 'Démarrer Surveillance',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMonitoring
                    ? const Color(0xFFFF5252)
                    : const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
