import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainPage(cameras: cameras),
    );
  }
}

class MainPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainPage({super.key, required this.cameras});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [
      CameraRecognition(cameras: widget.cameras),
      const UploadRecognition(),
      const TrafficSignGuide(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.upload),
            label: 'Upload',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book),
            label: 'Guide',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class CameraRecognition extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraRecognition({super.key, required this.cameras});

  @override
  // ignore: library_private_types_in_public_api
  _CameraRecognitionState createState() => _CameraRecognitionState();
}

class _CameraRecognitionState extends State<CameraRecognition> {
  late CameraController _cameraController;
  String? prediction;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() async {
    _cameraController =
        CameraController(widget.cameras[0], ResolutionPreset.medium);
    await _cameraController.initialize();
    setState(() {});
  }

  static final _logger = Logger('CameraRecognition');
  
  void _predictSign() async {
    try {
      final image = await _cameraController.takePicture();
      File imageFile = File(image.path);
      
      final predictionResponse = await RoboflowAPI.predictImage(imageFile);
      final formattedPrediction = RoboflowAPI.formatPrediction(predictionResponse);
      
      setState(() {
        prediction = formattedPrediction;
      });
    } catch (e, stackTrace) {
      _logger.severe('Error during prediction', e, stackTrace);
      setState(() {
        prediction = "Error: Could not process image";
      });
    }
  }


  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Camera Recognition")),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_cameraController)),
          Text(prediction ?? "Capture an image to recognize"),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _predictSign,
        child: const Icon(Icons.camera),
      ),
    );
  }
}

class UploadRecognition extends StatefulWidget {
  const UploadRecognition({super.key});

  @override
  _UploadRecognitionState createState() => _UploadRecognitionState();
}

class _UploadRecognitionState extends State<UploadRecognition> {
  String? prediction;

  static final _logger = Logger('UploadRecognition');
  
  void _uploadAndPredict() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        
        final predictionResponse = await RoboflowAPI.predictImage(file);
        final formattedPrediction = RoboflowAPI.formatPrediction(predictionResponse);
        
        setState(() {
          prediction = formattedPrediction;
        });
      }
    } catch (e, stackTrace) {
      _logger.severe('Error during upload prediction', e, stackTrace);
      setState(() {
        prediction = "Error: Could not process image";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Recognition")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(prediction ?? "Upload an image to recognize"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _uploadAndPredict,
              child: const Text("Upload Image"),
            ),
          ],
        ),
      ),
    );
  }
}

class TrafficSignGuide extends StatelessWidget {
  const TrafficSignGuide({super.key});

  Future<String> _loadPDF() async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfPath = "${directory.path}/India-Road-Traffic-Signs.pdf";

    if (!File(pdfPath).existsSync()) {
      final data = await rootBundle.load('assets/India-Road-Traffic-Signs.pdf');
      final bytes = data.buffer.asUint8List();
      await File(pdfPath).writeAsBytes(bytes, flush: true);
    }

    return pdfPath;
  }

  void _viewPDF(BuildContext context) async {
    final pdfPath = await _loadPDF();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PDFViewerScreen(pdfPath: pdfPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Traffic Sign Guide")),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _viewPDF(context),
          child: const Text("View Traffic Signs PDF"),
        ),
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String pdfPath;

  const PDFViewerScreen({super.key, required this.pdfPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PDF Viewer")),
      body: PDFView(
        filePath: pdfPath,
      ),
    );
  }
}
class RoboflowAPI {
  static final _logger = Logger('RoboflowAPI');

  // Initialize logger
  static void initializeLogging() {
    Logger.root.level = Level.ALL; // Adjust this based on your environment
    Logger.root.onRecord.listen((record) {
      // In production, you might want to send this to a logging service
      if (kDebugMode) {
        debugPrint('${record.level.name}: ${record.time}: ${record.message}');
      }
    });
  }
  static const String apiKey = "yBBUqH7OoybOPn4VB63e";
  static const String modelEndpoint = "traffic-and-road-signs/1";
  static const String baseUrl = "https://detect.roboflow.com";

  static Future<Map<String, dynamic>> predictImage(File imageFile) async {
    try {
      List<int> imageBytes = await imageFile.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      final response = await http.post(
        Uri.parse('$baseUrl/$modelEndpoint?api_key=$apiKey'), 
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'image': base64Image,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        _logger.severe('API request failed with status code: ${response.statusCode}');
        throw Exception('Failed to get prediction: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      _logger.severe('Error during API call', e, stackTrace);
      rethrow;
    }
  }

  static String formatPrediction(Map<String, dynamic> prediction) {
    try {
      var predictions = prediction['predictions'] as List;
      if (predictions.isEmpty) return "No traffic signs detected";

      predictions.sort((a, b) => (b['confidence'] as double)
          .compareTo(a['confidence'] as double));

      var topPrediction = predictions.first;
      var className = topPrediction['class'];
      var confidence = (topPrediction['confidence'] * 100).toStringAsFixed(1);

      return "$className (Confidence: $confidence%)";
    } catch (e, stackTrace) {
      _logger.severe('Error formatting prediction', e, stackTrace);
      return "Error processing prediction";
    }
  }
}