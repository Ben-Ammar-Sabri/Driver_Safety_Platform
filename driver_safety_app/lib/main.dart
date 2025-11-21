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

  const MyApp({required this.cameras, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Driver Safety Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFFFF5252),
          surface: Color(0xFF1D1E33),
        ),
      ),
      home: DriverSafetyScreen(cameras: cameras),
    );
  }
}

class DriverSafetyScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const DriverSafetyScreen({required this.cameras, super.key});

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

  /// GPS
  LatLng _currentLocation = LatLng(36.8065, 10.1815);
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
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _speed = position.speed * 3.6;
      });

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((Position pos) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _speed = pos.speed * 3.6;
          _acceleration = pos.speedAccuracy;
        });

        _mapController.move(_currentLocation, _mapController.camera.zoom);
      });
    } catch (e) {
      debugPrint("GPS ERROR: $e");
    }
  }

  Future<void> _initializeCameras() async {
    if (widget.cameras.isEmpty) return;

    try {
      CameraDescription? frontCamera;

      for (var cam in widget.cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          frontCamera = cam;
          break;
        }
      }

      frontCamera ??= widget.cameras.first;

      _driverCam = CameraController(
        frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _driverCam!.initialize();

      _roadCam = _driverCam;

      setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera error: $e");
    }
  }

  void _connectWebSocket() {
    try {
      _channel = IOWebSocketChannel.connect("ws://192.168.1.159:8765/ws");
      _channel!.stream.listen((msg) {
        final alert = jsonDecode(msg);
        _handleAlert(alert);
      });
    } catch (e) {
      debugPrint("WebSocket error: $e");
    }
  }

  void _handleAlert(Map<String, dynamic> alert) {
    final isCritical = alert["critical"] == true;
    final msg = alert["message"] ?? "";

    _triggerAlert(isAlarm: isCritical, message: msg);
    _updateScore(isCritical ? -5 : -2);
  }

  Future<void> _triggerAlert({required bool isAlarm, required String message}) async {
    setState(() {
      _borderColor = isAlarm ? Colors.red : Colors.orange;
      _alertMessage = message.isEmpty ? (isAlarm ? "ALARME!" : "Avertissement") : message;
    });

    _borderAnimationController.forward(from: 0).then((_) {
      _borderAnimationController.reverse();
    });

    final soundPath = isAlarm ? "alarm.wav" : "warning.wav";

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(
        AssetSource("sounds/$soundPath"),
        volume: 0.7,
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      debugPrint("Audio error: $e");
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _borderColor = Colors.transparent;
        _alertMessage = "";
      });
    });
  }

  void _updateScore(double delta) {
    setState(() {
      _score = (_score + delta).clamp(0, 100);
    });
  }

  void _toggleMonitoring() {
    if (!_isCameraInitialized) return;

    setState(() => _isMonitoring = !_isMonitoring);

    if (_isMonitoring) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }
  }

  void _startMonitoring() {
    _frameTimer = Timer.periodic(const Duration(milliseconds: 333), (timer) async {
      if (_driverCam?.value.isInitialized == true) {
        try {
          _driverCam!.startImageStream((image) {
            _sendFrame(image, "driver");
            _driverCam!.stopImageStream();
          });
        } catch (_) {}
      }
    });
  }

  void _stopMonitoring() {
    _frameTimer?.cancel();
    try {
      _driverCam?.stopImageStream();
    } catch (_) {}
  }

  void _sendFrame(CameraImage image, String camType) async {
    try {
      final buffer =
          img.Image(width: image.width ~/ 4, height: image.height ~/ 4);

      final y = image.planes[0].bytes;

      for (int yy = 0; yy < image.height; yy += 4) {
        for (int xx = 0; xx < image.width; xx += 4) {
          final pixel = y[yy * image.width + xx];
          buffer.setPixelRgba(xx ~/ 4, yy ~/ 4, pixel, pixel, pixel, 255);
        }
      }

      final jpg = img.encodeJpg(buffer, quality: 40);
      final base64 = base64Encode(jpg);

      _channel?.sink.add(jsonEncode({
        "camera": camType,
        "frame": base64,
        "timestamp": DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      debugPrint("Frame send error: $e");
    }
  }

  @override
  void dispose() {
    _borderAnimationController.dispose();
    _pulseAnimationController.dispose();
    _frameTimer?.cancel();
    _positionStream?.cancel();
    _driverCam?.dispose();
    _channel?.sink.close();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        SafeArea(
          child: Column(children: [
            _buildCameraViews(),
            Expanded(child: _buildMainContent()),
            _buildControlPanel(),
          ]),
        ),

        /// ALERT BORDER
        if (_borderColor != Colors.transparent)
          AnimatedBuilder(
            animation: _borderAnimationController,
            builder: (context, child) {
              return IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _borderColor
                          .withOpacity(_borderAnimationController.value),
                      width: 4,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            },
          ),
      ]),
    );
  }

  Widget _buildCameraViews() {
    return Container(
      height: 140,
      margin: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: _buildCameraCard(_driverCam, "Selfie", Icons.camera_front)),
          const SizedBox(width: 12),
          Expanded(child: _buildCameraCard(_roadCam, "Conducteur", Icons.person)),
        ],
      ),
    );
  }

  Widget _buildCameraCard(CameraController? controller, String label, IconData icon) {
    final active = controller?.value.isInitialized == true;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? Colors.green.withOpacity(0.5) : Colors.white24,
          width: 2,
        ),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            active
                ? CameraPreview(controller!)
                : Center(
                    child: Icon(icon, size: 48, color: Colors.white24),
                  ),

            /// LABEL
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
                  children: [
                    Icon(icon, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),

            /// RED DOT WHEN MONITORING
            if (_isMonitoring && active)
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
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
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
    final color = _score >= 80
        ? Colors.greenAccent
        : _score >= 50
            ? Colors.yellow
            : Colors.redAccent;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            value: _score / 100,
            strokeWidth: 10,
            color: color,
            backgroundColor: Colors.white12,
          ),
        ),
        Column(
          children: [
            Text(
              "${_score.toStringAsFixed(0)}%",
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: color),
            ),
            const Text("Score", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        )
      ],
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.speed,
            title: "Vitesse",
            value: _speed.toStringAsFixed(1),
            unit: "km/h",
            color: Colors.blueAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.trending_up,
            title: "Accélération",
            value: _acceleration.toStringAsFixed(1),
            unit: "m/s²",
            color: Colors.orangeAccent,
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
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
              children: [
                TextSpan(text: value),
                TextSpan(text: " $unit", style: const TextStyle(fontSize: 11)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRealMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation,
        initialZoom: 15,
        keepAlive: true,
      ),
      children: [
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        ),
        MarkerLayer(markers: [
          Marker(
            point: _currentLocation,
            width: 40,
            height: 40,
            child: const Icon(Icons.location_pin, size: 40, color: Colors.red),
          ),
        ]),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black.withOpacity(0.2),
      child: ElevatedButton.icon(
        icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
        label: Text(_isMonitoring ? "STOP MONITORING" : "START MONITORING"),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isMonitoring ? Colors.red : Colors.green,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _toggleMonitoring,
      ),
    );
  }
}
