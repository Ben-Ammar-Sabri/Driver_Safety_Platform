import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image/image.dart' as img;

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
  double _score = 85.0;
  double _speed = 60.0;
  double _acceleration = 1.2;
  Color _borderColor = Colors.transparent;
  String _alertMessage = '';
  Timer? _frameTimer;
  Timer? _dataTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCameras();
    _connectWebSocket();
    _testAudio(); // Test audio au démarrage
  }

  // Test audio au démarrage
  void _testAudio() async {
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('🧪 Test audio au démarrage...');
    try {
      await _audioPlayer.play(AssetSource('sounds/warning.wav'), volume: 0.5);
      debugPrint('✅ Audio fonctionne!');
    } catch (e) {
      debugPrint('❌ Audio ne fonctionne pas: $e');
    }
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
      
      // Afficher toutes les caméras disponibles
      for (int i = 0; i < widget.cameras.length; i++) {
        debugPrint('📷 Caméra $i: ${widget.cameras[i].lensDirection} - ${widget.cameras[i].name}');
      }
      
      // Trouver UNIQUEMENT la caméra frontale (selfie)
      CameraDescription? frontCamera;
      
      for (var camera in widget.cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          debugPrint('✅ Caméra frontale trouvée: ${camera.name}');
          break;
        }
      }

      // Si pas de caméra frontale trouvée, chercher par index
      if (frontCamera == null && widget.cameras.length > 1) {
        frontCamera = widget.cameras[1]; // Généralement index 1 = frontale
        debugPrint('⚠️ Utilisation caméra index 1 (supposée frontale)');
      } else if (frontCamera == null && widget.cameras.isNotEmpty) {
        frontCamera = widget.cameras[0];
        debugPrint('⚠️ Une seule caméra trouvée, utilisation de celle-ci');
      }

      if (frontCamera == null) {
        throw Exception('Aucune caméra disponible');
      }

      // Initialiser LA MÊME caméra frontale pour conducteur ET route
      _driverCam = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _driverCam!.initialize();
      debugPrint('✅ Caméra conducteur (frontale) initialisée');

      // Utiliser la MÊME caméra pour les deux vues
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

    _borderAnimationController.forward(from: 0).then((_) {
      _borderAnimationController.reverse();
    });
    
    // Jouer le son
    try {
      final soundPath = isAlarm ? 'alarm.wav' : 'warning.wav';
      debugPrint('🔊 Lecture du son: $soundPath');
      
      // Arrêter le son précédent
      await _audioPlayer.stop();
      
      // Jouer le nouveau son
      await _audioPlayer.play(
        AssetSource('sounds/$soundPath'),
        volume: 1.0,
        mode: PlayerMode.lowLatency,
      );
      
      debugPrint('✅ Son joué: $soundPath');
    } catch (e) {
      debugPrint('❌ Erreur son: $e');
      // Vibration comme fallback
      debugPrint('💡 Astuce: Vérifiez le volume du téléphone');
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
    // Timer pour envoyer les frames (une seule caméra utilisée)
    _frameTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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

    // Simulation données dynamiques
    _dataTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      setState(() {
        _speed = (50 + (30 * (0.5 - (DateTime.now().second % 10) / 10))).clamp(0, 120);
        _acceleration = (0.5 + (2 * (0.5 - (DateTime.now().second % 5) / 5))).clamp(-3, 3);
      });
    });
  }

  void _stopMonitoring() {
    _frameTimer?.cancel();
    _dataTimer?.cancel();
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
    _dataTimer?.cancel();
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
          // Contenu principal
          SafeArea(
            child: Column(
              children: [
                _buildCameraViews(),
                Expanded(child: _buildMainContent()),
                _buildControlPanel(),
              ],
            ),
          ),
          // Bordure fine d'alerte
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
          Expanded(child: _buildMapPlaceholder()),
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

  Widget _buildMapPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              'Carte GPS',
              style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.5)),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bouton toggle caméras
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
          // Bouton monitoring
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
          const SizedBox(height: 10),
          // Boutons alertes
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _triggerAlert(isAlarm: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9100).withOpacity(0.2),
                    foregroundColor: const Color(0xFFFF9100),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFFF9100), width: 1.5),
                    ),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.warning_amber, size: 20),
                      SizedBox(height: 4),
                      Text('Avertissement', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _triggerAlert(isAlarm: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1744).withOpacity(0.2),
                    foregroundColor: const Color(0xFFFF1744),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFFF1744), width: 1.5),
                    ),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.emergency, size: 20),
                      SizedBox(height: 4),
                      Text('Alarme', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}