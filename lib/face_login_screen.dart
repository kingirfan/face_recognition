import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_app/ML/Recognition.dart';
import 'package:image_picker_app/ML/Recognizer.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  late ImagePicker imagePicker;
  late FaceDetector faceDetector;
  late Recognizer recognizer;
  File? _image;

  List<Face> faces = [];
  List<Recognition> recognitions = [];
  var image;
  var faceImage;

  @override
  void initState() {
    super.initState();
    imagePicker = ImagePicker();

    // Face detector
    final options = FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    );
    faceDetector = FaceDetector(options: options);

    // Recognizer
    recognizer = Recognizer();

    // Automatically open front camera
    Future.delayed(Duration(milliseconds: 500), _imgFromCamera);
  }

  // Capture image using front camera
  _imgFromCamera() async {
    XFile? pickedFile = await imagePicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
      await doFaceDetection();
    } else {
      Navigator.pop(context); // user cancelled
    }
  }

  doFaceDetection() async {
    recognitions.clear();
    _image = await removeRotation(_image!);
    InputImage inputImage = InputImage.fromFile(_image!);
    faces = await faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      _showSnack("No face detected. Try again.");
      return;
    }

    final bytes = await _image!.readAsBytes();
    final img.Image? fullImage = img.decodeImage(bytes);

    for (Face face in faces) {
      final Rect faceRect = face.boundingBox;

      // Clamp bounds to avoid overflow
      int x = faceRect.left.clamp(0, fullImage!.width - 1).toInt();
      int y = faceRect.top.clamp(0, fullImage.height - 1).toInt();
      int w = faceRect.width.clamp(1, fullImage.width - x).toInt();
      int h = faceRect.height.clamp(1, fullImage.height - y).toInt();

      final croppedFace = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);

      final recognition = await recognizer.recognize(croppedFace, faceRect);
      print("Similarity score: ${recognition.distance}");
      if (recognition.distance > 0.6) {
        final name = recognition.name.isNotEmpty ? recognition.name : 'Unknown User';
        _showMessage('Login Authenticated: $name', success: true);
      } else {
        _showMessage('Face not recognized. Access denied.');
      }

      recognitions.add(recognition);
    }

    drawRectangleAroundFace();
  }

  drawRectangleAroundFace() async {
    var bytes = await _image!.readAsBytes();
    image = await decodeImageFromList(bytes);
    setState(() {
      image;
      recognitions;
    });
  }

  void _showMessage(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        backgroundColor: success ? Colors.green.shade600 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  removeRotation(File inputImage) async {
    final img.Image? capturedImage = img.decodeImage(
      await File(inputImage.path).readAsBytes(),
    );
    final img.Image orientedImage = img.bakeOrientation(capturedImage!);
    return await File(_image!.path).writeAsBytes(img.encodeJpg(orientedImage));
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1f4037),
      appBar: AppBar(
        title: const Text("Face ID Login"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: image != null
            ? FittedBox(
                child: SizedBox(
                  width: image.width.toDouble(),
                  height: image.height.toDouble(),
                  child: CustomPaint(
                    painter: FacePainter(
                      facesList: recognitions,
                      imageFile: image,
                    ),
                  ),
                ),
              )
            : const Text(
                "Please wait till it recognize...",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  List<Recognition> facesList;
  dynamic imageFile;

  FacePainter({required this.facesList, @required this.imageFile});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageFile != null) {
      canvas.drawImage(imageFile, Offset.zero, Paint());
    }

    Paint p = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    for (Recognition recognition in facesList) {
      canvas.drawRect(recognition.location, p);
      final name = recognition.name;
      final textSpan = TextSpan(
        text: name,
        style: const TextStyle(color: Colors.red, fontSize: 24),
      );
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(recognition.location.left, recognition.location.top),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
