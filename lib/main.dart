import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'HomeScreen.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const MaterialApp(home: LiveCameraFootage()));
}

class LiveCameraFootage extends StatefulWidget {
  const LiveCameraFootage({super.key});

  @override
  State<LiveCameraFootage> createState() => _LiveCameraFootageState();
}

class _LiveCameraFootageState extends State<LiveCameraFootage> {
  late CameraController controller;

  @override
  void initState() {
    super.initState();
    controller = CameraController(_cameras[0], ResolutionPreset.max);
    controller
        .initialize()
        .then((_) {
          if (!mounted) {
            return;
          }
          controller.startImageStream((image) {
           print('imageimageimage ${image.width.toString()}  :  ${image.height.toString()}  : ${image.planes}');
          });
          setState(() {});
        })
        .catchError((Object e) {
          if (e is CameraException) {
            switch (e.code) {
              case 'CameraAccessDenied':
                // Handle access errors here.
                break;
              default:
                // Handle other errors here.
                break;
            }
          }
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Live Camera Footage')),
      body: Center(
        child: controller.value.isInitialized
            ? CameraPreview(controller)
            : SizedBox(),
      ),
    );
  }
}
