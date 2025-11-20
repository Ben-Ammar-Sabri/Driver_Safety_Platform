import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image/image.dart' as img;

// MAIN
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

// APP ROOT
class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  MyApp({required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Driver Safety Monitor',
      theme: ThemeData.dark(),
      home: DriverSafetyScreen(cameras: cameras),
    );
  }
}

// DRIVER SAFETY SCREEN
class DriverSafetyScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  DriverSafetyScreen({required this.cameras});

  @override
  _DriverSafetyScreenState createState() => _DriverSafetyScreenState();
}

class _DriverSafetyScreenState extends State<DriverSafetyScreen> {
  late CameraController driverCam;
  late CameraController roadCam;
  bool isMonitoring = false;
  bool isDriverCamActive = true;
  late IOWebSocketChannel channel;
  AudioPlayer audioPlayer = AudioPlayer();

  // Score, vitesse et accélération simulés
  double score = 70;
  double speed = 80; // km/h
  double acceleration = 2.5; // m/s²

  @override
  void initState() {
    super.initState();
    driverCam = CameraController(widget.cameras[0], ResolutionPreset.medium);
    roadCam = CameraController(widget.cameras[1], ResolutionPreset.medium);
    initializeCameras();
    connectWebSocket();
  }

  Future<void> initializeCameras() async {
    await driverCam.initialize();
    await roadCam.initialize();
    setState(() {});
  }

  void connectWebSocket() {
    // Remplacez par l'adresse de votre serveur WebSocket
    channel = IOWebSocketChannel.connect('ws://YOUR_SERVER_IP:8765');
    channel.stream.listen((message) {
      final alert = jsonDecode(message);
      print("ALERT RECEIVED: ${alert['type']} - ${alert['status']}");
      if (alert['critical'] == true) {
        playAlarmSound();
      } else {
        playWarningSound();
      }
    });
  }

  void playAlarmSound() async {
    await audioPlayer.play(AssetSource('sounds/alarm.wav'));
  }

  void playWarningSound() async {
    await audioPlayer.play(AssetSource('sounds/warning.wav'));
  }

  void toggleMonitoring() {
    setState(() {
      isMonitoring = !isMonitoring;
      if (isMonitoring) {
        driverCam.startImageStream((image) => sendFrame(image, "driver"));
        roadCam.startImageStream((image) => sendFrame(image, "road"));
      } else {
        driverCam.stopImageStream();
        roadCam.stopImageStream();
      }
    });
  }

  void toggleCamera() {
    setState(() {
      isDriverCamActive = !isDriverCamActive;
    });
  }

  void sendFrame(CameraImage image, String camType) async {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0].bytes;
    final imgBuffer = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = yPlane[y * width + x];
        imgBuffer.setPixelRgba(x, y, pixel, pixel, pixel, 255);
      }
    }

    final jpeg = img.encodeJpg(imgBuffer, quality: 50);
    final base64String = base64Encode(jpeg);

    channel.sink.add(jsonEncode({
      'camera': camType,
      'frame': base64String,
      'timestamp': DateTime.now().toIso8601String(),
    }));
  }

  @override
  void dispose() {
    driverCam.dispose();
    roadCam.dispose();
    channel.sink.close();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!driverCam.value.isInitialized || !roadCam.value.isInitialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Driver Safety Monitor"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          // Camera Preview (60%)
          Expanded(
            flex: 6,
            child: Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CameraPreview(isDriverCamActive ? driverCam : roadCam),
              ),
            ),
          ),

          // Infos et boutons (40%)
          Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Infos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InfoCard(title: "Vitesse", value: "${speed.toStringAsFixed(1)} km/h"),
                      InfoCard(title: "Accélération", value: "${acceleration.toStringAsFixed(1)} m/s²"),
                      InfoCard(title: "Score", value: "${score.toStringAsFixed(0)} %", color: Colors.green),
                    ],
                  ),
                  SizedBox(height: 12),

                  // Switch Camera
                  ElevatedButton.icon(
                    onPressed: toggleCamera,
                    icon: Icon(Icons.switch_camera),
                    label: Text("Switch Camera"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),

                  // Start / Stop Monitoring
                  ElevatedButton(
                    onPressed: toggleMonitoring,
                    child: Text(
                      isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// INFO CARD WIDGET
class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  InfoCard({required this.title, required this.value, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(12),
        width: 100,
        child: Column(
          children: [
            Text(title, style: TextStyle(color: Colors.grey[300], fontSize: 14)),
            SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
