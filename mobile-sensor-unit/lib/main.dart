import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final log = Logger('DriverApp');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras}); // const + key ajouté

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(cameras: cameras),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CameraController frontController;
  late CameraController backController;
  bool isStreaming = false;
  String backendUrl = "http://192.168.1.10:5000/analyze"; // Met ton IP locale

  Map<String, dynamic> sensorsData = {};
  Position? currentPosition;

  Timer? streamingTimer;

  @override
  void initState() {
    super.initState();
    initCameras();
    initSensors();
    getLocation();
  }

  void initCameras() async {
    frontController = CameraController(
      widget.cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front),
      ResolutionPreset.medium,
    );
    backController = CameraController(
      widget.cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back),
      ResolutionPreset.medium,
    );

    await frontController.initialize();
    await backController.initialize();
    setState(() {}); // refresh UI après initialisation
  }

  void initSensors() {
    SensorsPlatform.instance.accelerometerEventStream().listen((event) {
  sensorsData['accelerometer'] = {'x': event.x, 'y': event.y, 'z': event.z};
});

SensorsPlatform.instance.gyroscopeEventStream().listen((event) {
  sensorsData['gyroscope'] = {'x': event.x, 'y': event.y, 'z': event.z};
});
  
  
  }

  void getLocation() async {
    try {
      currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      log.warning("Erreur géolocalisation: $e");
    }
  }

  Future<void> captureAndSend(CameraController controller, String type) async {
    if (!controller.value.isInitialized) return;

    try {
      final XFile file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      Map<String, dynamic> payload = {
        "type": type,
        "frame": base64Image,
        "sensors": sensorsData,
        "gps": currentPosition != null
            ? {"lat": currentPosition!.latitude, "lon": currentPosition!.longitude}
            : {}
      };

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        log.info("Result: ${response.body}");
      } else {
        log.warning("Erreur backend: ${response.statusCode}");
      }
    } catch (e) {
      log.severe("Erreur envoi données: $e");
    }
  }

  void startStreaming() {
    if (!isStreaming) {
      streamingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        captureAndSend(frontController, "driver");
        captureAndSend(backController, "road");
      });
      setState(() => isStreaming = true);
    }
  }

  @override
  void dispose() {
    streamingTimer?.cancel();
    frontController.dispose();
    backController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Safety App")),
      body: Center(
        child: ElevatedButton(
          onPressed: startStreaming,
          child: Text(isStreaming ? "Streaming..." : "Start Streaming"),
        ),
      ),
    );
  }
}
