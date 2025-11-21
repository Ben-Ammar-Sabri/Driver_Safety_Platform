import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  bool _isCameraInitialized = false;
  double _score = 85.0;
  double _speed = 0.0;
  double _acceleration = 0.0;
  Color _borderColor = Colors.transparent;
  String _alertMessage = '';
  Timer? _frameTimer;
  Timer? _speedTimer;
  
  // GPS/Location
  LatLng _currentLocation = LatLng(36.8065, 10.1815); // Tunis par défaut
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCameras();
    _connectWebSocket();
    _startLocationTracking();
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

  Future<void> _startLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ Services de localisation désactivés');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('⚠️ Permission de localisation refusée');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Permission de localisation refusée définitivement');
        return;
      }

      // Obtenir la position actuelle
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _speed = position.speed * 3.6; // Convertir m/s en km/h
      });

      // Écouter les changements de position
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Mise à jour tous les 5 mètres
        ),
      ).listen((Position position) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _speed = position.speed * 3.6; // km/h
          _acceleration = position.speedAccuracy; // Approximation
        });
        
        // Centrer la carte sur la position actuelle
        _mapController.move(_currentLocation, _mapController.camera.zoom);
      });

      debugPrint('✅ Suivi GPS activé');
    } catch (e) {
      debugPrint('❌ Erreur GPS: $e');
    }
  }

  Future<void> _initializeCameras() async {
    if (widget.cameras.isEmpty) return;
    
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
      );
      await _driverCam!.initialize();
      debugPrint('✅ Caméra conducteur (frontale) initialisée');

      _roadCam = _driverCam;
      debugPrint('✅ Même caméra utilisée pour les deux vues');

      if (mounted) {
        setState(() => _isCameraInitialized = true);
        debugPrint('🎉 Caméra frontale prête pour les deux vues!');
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
      _channel = IOWebSocketChannel.connect('ws://192.168.1.159:8765/ws');
      _channel?.stream.listen(
        (message) {
          final alert = jsonDecode(message);
          _handleAlert(alert);
        },
        onError: (error) => debugPrint('WebSocket erreur: $error'),
      );
    } catch (e) {
      debugPrint('Connexion WebSocket échouée: $e');
    }
  }

  void _handleAlert(Map<String, dynamic> alert) {
    final isCritical = alert['critical'] == true;
    final message = alert['message'] ?? '';
    _triggerAlert(isAlarm: isCritical, message: message);
    _updateScore(isCritical ? -5 : -2);
  }

  Future<void> _triggerAlert({required bool isAlarm, String message = ''}) async {
    setState(() {
      _borderColor = isAlarm ? const Color(0xFFFF1744) : const Color(0xFFFF9100);
      _alertMessage = isAlarm ? 'ALARME!' : 'Avertissement';
    });

    _borderAnimationController.forward(from: 0).then(() {
      _borderAnimationController.reverse();
    });
    
    try {
      final soundPath = isAlarm ? 'alarm.wav' : 'warning.wav';
      debugPrint('🔊 Lecture du son: $soundPath');
      
      await _audioPlayer.stop();
      await _audioPlayer.play(
        AssetSource('sounds/$soundPath'),
        volume: 0.7, // Réduit de 1.0 à 0.7
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

  void _toggleMonitoring() {
    if (!_isCameraInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caméra non initialisée'),
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
    // Timer pour envoyer les frames à 3 FPS
    _frameTimer = Timer.periodic(const Duration(milliseconds: 333), () {
      if (_driverCam?.value.isInitialized == true) {
        try {
          _driverCam!.startImageStream((image) {
            _sendFrame(image, "driver");
            _driverCam!.stopImageStream();
          });
        } catch (e) {
          debugPrint('Erreur stream caméra: $e');
        }
      }
    });
  }

  void _stopMonitoring() {
    _frameTimer?.cancel();
    try {
      _driverCam?.stopImageStream();
      _roadCam?.stopImageStream();
    } catch (e) {
      debugPrint('Erreur arrêt stream: $e');
    }
  }

  void _sendFrame(CameraImage image, String camType) async {
    try {
      final imgBuffer = img.Image(width: image.width ~/ 4, height: image.height ~/ 4);
      final yPlane = image.planes[0].bytes;

      for (int y = 0; y < image.height; y += 4) {
        for (int x = 0; x < image.width; x += 4) {
          final pixel = yPlane[y * image.width + x];
          imgBuffer.setPixelRgba(x ~/ 4, y ~/ 4, pixel, pixel, pixel, 255);
        }
      }

      final jpeg = img.encodeJpg(imgBuffer, quality: 40);
      final base64String = base64Encode(jpeg);

      _channel?.sink.add(jsonEncode({
        'camera': camType,
        'frame': base64String,
        'timestamp': DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('Erreur envoi frame: $e');
    }
  }

  @override
  void dispose() {
    _borderAnimationController.dispose();
    _pulseAnimationController.dispose();
    _frameTimer?.cancel();
    _speedTimer?.cancel();
    _positionStream?.cancel();
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
                      borderRadius: BorderRadius.circular(😎,
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
      margin: const EdgeInsets.all(😎,
      child: Row(
        children: [
          Expanded(child: _buildCameraCard(_driverCam, 'Caméra Selfie', Icons.camera_front)),
          const SizedBox(width: 😎,
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
          Expanded(child: _buildRealMap()),
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

  Widget _buildRealMap() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation,
            initialZoom: 15.0,
            minZoom: 5.0,
            maxZoom: 18.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.driver_safety',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2196F3).withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
      child: SizedBox(
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
