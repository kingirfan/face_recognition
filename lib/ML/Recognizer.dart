import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../DB/DatabaseHelper.dart';
import 'Recognition.dart';

class Recognizer {
  late Interpreter interpreter;
  late InterpreterOptions _interpreterOptions;
  static const int WIDTH = 160;
  static const int HEIGHT = 160;
  final dbHelper = DatabaseHelper();
  Map<String, Recognition> registered = {};

  String get modelName => 'assets/facenet.tflite';

  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    loadModel();
    initDB();
  }

  initDB() async {
    await dbHelper.init();
    loadRegisteredFaces();
  }

  void loadRegisteredFaces() async {
    final allRows = await dbHelper.queryAllRows();
    // debugPrint('query all rows:');
    for (final row in allRows) {
      //  debugPrint(row.toString());
      print(' load register faces : ${row[DatabaseHelper.columnName]}');
      String name = row[DatabaseHelper.columnName];
      List<double> embd = row[DatabaseHelper.columnEmbedding]
          .split(',')
          .map((e) => double.parse(e))
          .toList()
          .cast<double>();
      Recognition recognition = Recognition(
        row[DatabaseHelper.columnName],
        Rect.zero,
        embd,
        0,
      );
      registered.putIfAbsent(name, () => recognition);
    }
  }

  Future<Uint8List> compressImage(Uint8List imageData, {int maxSizeInKB = 500}) async {
    img.Image? image = img.decodeImage(imageData);
    if (image == null) throw Exception('Image decoding failed');

    // Resize to smaller dimensions if necessary
    img.Image resized = img.copyResize(image, width: 300); // ~300px width

    int quality = 85; // Start with high quality
    Uint8List jpg;

    do {
      jpg = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      quality -= 5;
    } while (jpg.lengthInBytes > maxSizeInKB * 1024 && quality > 20);

    return jpg;
  }

  void registerFaceInDB(String name, List<double> embedding,Uint8List faceImage) async {
    Uint8List compressedImage = await compressImage(faceImage);
    // row to insert
    Map<String, dynamic> row = {
      DatabaseHelper.columnName: name,
      DatabaseHelper.columnEmbedding: embedding.join(","),
      DatabaseHelper.columnImage: compressedImage,
    };
    final id = await dbHelper.insert(row);
    print('inserted row id: $id');
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(modelName);
      // ✅ Print the input and output tensor shapes
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;

      print('✅ Model loaded successfully!');
      print('➡️  Input shape: $inputShape');
      print('➡️  Output shape: $outputShape');
    } catch (e) {
      print('Unable to create interpreter, Caught Exception: ${e.toString()}');
    }
  }

  // List<dynamic> imageToArray(img.Image inputImage){
  //   img.Image resizedImage = img.copyResize(inputImage!, width: WIDTH, height: HEIGHT);
  //   List<double> flattenedList = resizedImage.data!.expand((channel) => [channel.r, channel.g, channel.b]).map((value) => value.toDouble()).toList();
  //   Float32List float32Array = Float32List.fromList(flattenedList);
  //   int channels = 3;
  //   int height = HEIGHT;
  //   int width = WIDTH;
  //   Float32List reshapedArray = Float32List(1 * height * width * channels);
  //   for (int c = 0; c < channels; c++) {
  //     for (int h = 0; h < height; h++) {
  //       for (int w = 0; w < width; w++) {
  //         int index = c * height * width + h * width + w;
  //         reshapedArray[index] = (float32Array[c * height * width + h * width + w]-127.5)/127.5;
  //       }
  //     }
  //   }
  //   return reshapedArray.reshape([1,112,112,3]);
  // }

  // int redFromPixel(int p) => (p >> 16) & 0xFF;
  // int greenFromPixel(int p) => (p >> 8) & 0xFF;
  // int blueFromPixel(int p) => p & 0xFF;

  List imageToArray(img.Image inputImage) {
    // Resize the face image to match model input size
    final resizedImage = img.copyResize(
      inputImage,
      width: WIDTH,
      height: HEIGHT,
    );

    final int channels = 3;
    final int height = HEIGHT;
    final int width = WIDTH;

    final Float32List input = Float32List(1 * height * width * channels);
    int idx = 0;

    // Loop through all pixels
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // getPixel returns PixelUint8 in image 4.x
        final pixel = resizedImage.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        // Normalize values to [-1, 1] as expected by FaceNet
        input[idx++] = (r - 127.5) / 127.5;
        input[idx++] = (g - 127.5) / 127.5;
        input[idx++] = (b - 127.5) / 127.5;
      }
    }

    // IMPORTANT: match model shape (check via loadModel() print)
    return input.reshape([1, HEIGHT, WIDTH, channels]);
  }

  Recognition recognize(img.Image image, Rect location) {
    //TODO crop face from image resize it and convert it to float array
    var input = imageToArray(image);
    print(input.shape.toString());

    //TODO output array
    List output = List.filled(1 * 512, 0).reshape([1, 512]);

    //TODO performs inference
    final runs = DateTime.now().millisecondsSinceEpoch;
    interpreter.run(input, output);
    final run = DateTime.now().millisecondsSinceEpoch - runs;
    print('Time to run inference: $run ms$output');

    //TODO convert dynamic list to double list
    List<double> outputArray = output.first.cast<double>();

    //TODO looks for the nearest embeeding in the database and returns the pair
    Pair pair = findNearest(outputArray);
    print("distance= ${pair.distance}");

    return Recognition(pair.name, location, outputArray, pair.distance);
  }

  //TODO  looks for the nearest embeeding in the database and returns the pair which contain information of registered face with which face is most similar
  // findNearest(List<double> emb) {
  //   Pair pair = Pair("Unknown", -5);
  //   for (MapEntry<String, Recognition> item in registered.entries) {
  //     final String name = item.key;
  //     List<double> knownEmb = item.value.embeddings;
  //     double distance = 0;
  //     for (int i = 0; i < emb.length; i++) {
  //       double diff = emb[i] - knownEmb[i];
  //       distance += diff * diff;
  //     }
  //     distance = sqrt(distance);
  //     if (pair.distance == -5 || distance < pair.distance) {
  //       pair.distance = distance;
  //       pair.name = name;
  //     }
  //   }
  //   return pair;
  // }

  Pair findNearest(List<double> emb) {
    Pair pair = Pair("Unknown", -1); // Start with lowest similarity
    for (MapEntry<String, Recognition> item in registered.entries) {
      final String name = item.key;
      List<double> knownEmb = item.value.embeddings;

      double dotProduct = 0.0;
      double normA = 0.0;
      double normB = 0.0;

      for (int i = 0; i < emb.length; i++) {
        dotProduct += emb[i] * knownEmb[i];
        normA += emb[i] * emb[i];
        normB += knownEmb[i] * knownEmb[i];
      }

      double similarity = dotProduct / (sqrt(normA) * sqrt(normB));

      if (similarity > pair.distance) {
        pair.distance = similarity;
        pair.name = name;
      }
    }
    return pair;
  }

  void close() {
    interpreter.close();
  }

  ////////////////////

  Future<List<double>?> extractFaceEmbedding(File imageFile) async {
    // 1️⃣ Convert to MLKit input image
    final inputImage = InputImage.fromFile(imageFile);

    // 2️⃣ Create a face detector
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );

    // 3️⃣ Detect faces
    final faces = await faceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      await faceDetector.close();
      return null;
    }

    // 4️⃣ Load the image into memory for cropping
    final bytes = await imageFile.readAsBytes();
    final img.Image? fullImage = img.decodeImage(bytes);
    if (fullImage == null) {
      await faceDetector.close();
      return null;
    }

    // 5️⃣ Crop the first detected face
    final faceRect = faces.first.boundingBox;
    final croppedFace = img.copyCrop(
      fullImage,
      x: faceRect.left.toInt().clamp(0, fullImage.width - 1),
      y: faceRect.top.toInt().clamp(0, fullImage.height - 1),
      width: faceRect.width.toInt().clamp(
        0,
        fullImage.width - faceRect.left.toInt(),
      ),
      height: faceRect.height.toInt().clamp(
        0,
        fullImage.height - faceRect.top.toInt(),
      ),
    );

    // 6️⃣ Get the embedding vector using your TFLite model
    final embedding = getEmbedding(croppedFace);

    await faceDetector.close();
    return embedding;
  }

  List<double> getEmbedding(img.Image faceImage) {
    // Convert to model input format
    var input = imageToArray(faceImage);
    List output = List.filled(1 * 512, 0).reshape([1, 512]);

    // Run inference
    interpreter.run(input, output);

    // Convert output to list<double>
    return output.first.cast<double>();
  }
}

class Pair {
  String name;
  double distance;

  Pair(this.name, this.distance);
}
