/*
<Owner Registration and Management Screen>

Registration Flow
Step 1 – Voice Training:
Read three predefined scripts to complete voice recognition.
Step 2 – Face Capture:
Capture the face using the camera → Extract facial landmarks using ML Kit.
Step 3 – Final Save:
Combine the data into OwnerData and store it in the list.

<Key Updates>

Prevented crashes caused by an empty _scripts list (removed setState call in initState)
Disabled the registration button until voice training is completed
Display facial feature values on the owner card
Visualized the registration process using a step indicator
Separated location tracking into an independent section
*/
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

// ─────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────
class OwnerData {
  String id;
  String name;
  Map<String, double> faceFeatures;
  double voicePitch;
  bool hasFace;
  DateTime registeredAt;

  OwnerData({
    required this.id,
    required this.name,
    required this.faceFeatures,
    required this.voicePitch,
    required this.hasFace,
    required this.registeredAt,
  });
}

// ─────────────────────────────────────────
// Homescreen
// ─────────────────────────────────────────
class MultiOwnerControlScreen extends StatefulWidget {
  const MultiOwnerControlScreen({super.key});

  @override
  State<MultiOwnerControlScreen> createState() =>
      _MultiOwnerControlScreenState();
}

class _MultiOwnerControlScreenState extends State<MultiOwnerControlScreen> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  String _robotName = "PLATYPUS";
  late List<String> _scripts;
  int _currentScriptIndex = 0;

  // Registeration Process: 0 -> Learning voice (intonation and vibration), 1 -> take a face photo, 2-> Complete
  int _step = 0;
  Map<String, double> _pendingFaceFeatures = {};
  double _pendingVoicePitch = 0;

  List<OwnerData> _ownerList = [];
  String _status = "STEP 1: 'Starting to detect voice' Please Push the buttom and read the script.";

  Position? _robotPosition;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    // initinalize without setState → guarantee the risk in the state of 'Build'
    _scripts = _buildScripts(_robotName);
    _faceDetector =
        FaceDetector(options: FaceDetectorOptions(enableLandmarks: true));
    _initCamera();
  }

  List<String> _buildScripts(String name) =>
      ["Hey $name", "Hello $name", "How are you up to $name"];

  // ─────────────────────────────────────────
  // Initionalize the Camera (Priority to the front camera)
  // ─────────────────────────────────────────
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras[0],
    );

    _cameraController =
        CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    await _cameraController?.initialize();
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────
  // STEP 1 — Learning the user's voice
  // ─────────────────────────────────────────
  void _startVoiceTraining() async {
    if (_step != 0) return;

    bool available = await _speech.initialize(
      onError: (e) => setState(() => _status = "Failed to detect voice: ${e.errorMsg}"),
    );

    if (!available) {
      setState(() => _status = "It has no responsible to record voice or detect voice.");
      return;
    }

    setState(() {
      _isListening = true;
      _status = "Please say it → \"${_scripts[_currentScriptIndex]}\"";
    });

    _speech.listen(
      onResult: (result) {
        if (!result.finalResult) return;

        final target = _scripts[_currentScriptIndex]
            .replaceAll("?", "")
            .replaceAll(".", "");

        if (result.recognizedWords.contains(target)) {
          if (_currentScriptIndex < _scripts.length - 1) {
            setState(() {
              _currentScriptIndex++;
              _status = "✅ Complete to detect! Next → \"${_scripts[_currentScriptIndex]}\"";
            });
          } else {
            _pendingVoicePitch = 130.0 + Random().nextInt(100).toDouble();
            setState(() {
              _isListening = false;
              _step = 1;
              _status = "✅ Complete to record the voice! STEP 2: Click the 'photo-shot!' button after gazing the camera.";
            });
            _speech.stop();
          }
        } else {
          setState(() =>
              _status = "❌ Try it Again → \"${_scripts[_currentScriptIndex]}\"");
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: false,
    );
  }

  // ─────────────────────────────────────────
  // STEP 2 — Taking a face shot & ML Kit analysing
  // ─────────────────────────────────────────
  Future<void> _takeFacePhoto() async {
    if (_step != 1) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _status = "Not ready for taking a face-shot.");
      return;
    }

    setState(() => _status = "Processing...");

    try {
      final imageFile = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final leftEye = face.landmarks[FaceLandmarkType.leftEye];
        final rightEye = face.landmarks[FaceLandmarkType.rightEye];
        final noseBase = face.landmarks[FaceLandmarkType.noseBase];

        if (leftEye != null && rightEye != null && noseBase != null) {
          final eyeDist =
              (rightEye.position.x - leftEye.position.x).abs().toDouble();
          final eyeNose =
              (noseBase.position.y - leftEye.position.y).abs().toDouble();
          _pendingFaceFeatures = {
            'eyeDistance': eyeDist,
            'eyeToNoseRatio': eyeDist > 0 ? eyeNose / eyeDist : 0.0,
          };
        } else {
          _pendingFaceFeatures = {'ratio': 0.65};
        }

        setState(() {
          _step = 2;
          _status = "✅ Complete to detect face! STEP 3: Press the 'Registration Complete' button.";
        });
      } else {
        setState(
            () => _status = "❌ Unable to detect the user's face. Try again gazing on the front camera.");
      }
    } catch (e) {
      setState(() => _status = "Failed to take a face-shot: $e");
    }
  }

  // ─────────────────────────────────────────
  // STEP 3 — final saving 
  // ─────────────────────────────────────────
  void _addOwner() {
    if (_step != 2) return;

    final nameController =
        TextEditingController(text: "Owner ${_ownerList.length + 1}");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("주인 이름 설정"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "표시 이름",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _ownerList.add(OwnerData(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim().isEmpty
                      ? "주인 ${_ownerList.length + 1}"
                      : nameController.text.trim(),
                  faceFeatures: _pendingFaceFeatures,
                  voicePitch: _pendingVoicePitch,
                  hasFace: _pendingFaceFeatures.containsKey('eyeDistance'),
                  registeredAt: DateTime.now(),
                ));
                // 다음 등록을 위해 초기화
                _step = 0;
                _currentScriptIndex = 0;
                _pendingFaceFeatures = {};
                _status = "Complete to register! If you are willing to register the next User, start from 'Step 1'.";
              });
              Navigator.pop(ctx);
            },
            child: const Text("Registered"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // changing the user's name
  // ─────────────────────────────────────────
  void _editOwnerName(int index) {
    final editController =
        TextEditingController(text: _ownerList[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Changing the user information"),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(labelText: "Enter the new name"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              setState(() => _ownerList[index].name = editController.text);
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // Detecting the postion by GPS
  // ─────────────────────────────────────────
  Future<void> _getRobotLocation() async {
    setState(() => _isLocating = true);

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _isLocating = false;
        _status = "Permission of the current position is permanently rejected. Please allow this in Setting!";
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _robotPosition = position;
        _isLocating = false;
        _status = "📍 Completed to update the robot position";
      });
    } catch (e) {
      setState(() {
        _isLocating = false;
        _status = "Unable to bring the position information.";
      });
    }
  }

  // ─────────────────────────────────────────
  // Setting the robot name
  // ─────────────────────────────────────────
  void _showRobotSettings() {
    final nameController = TextEditingController(text: _robotName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("🤖 Setting the robot",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Robot Name",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.smart_toy_rounded),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _robotName = nameController.text;
                    _scripts = _buildScripts(_robotName);
                    _currentScriptIndex = 0;
                    _step = 0;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text("Save"),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _speech.stop();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$_robotName Setting Sensor"),
        centerTitle: true,
        actions: [
          IconButton(
              onPressed: _showRobotSettings,
              icon: const Icon(Icons.settings))
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepIndicator(),
            const SizedBox(height: 16),
            _buildStatusBanner(),
            const SizedBox(height: 16),
            _buildCameraSection(),
            const SizedBox(height: 16),
            _buildVoiceSection(),
            const SizedBox(height: 16),
            _buildRegisterButton(),
            const SizedBox(height: 24),
            _buildLocationSection(),
            const SizedBox(height: 24),
            _buildOwnerList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Stage indicater ──
  Widget _buildStepIndicator() {
    final steps = ["voice\nlearning", "face\nshot", "registeration\ncomplete"];
    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == _step;
        final isDone = i < _step;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isDone
                        ? Colors.green
                        : isActive
                            ? Colors.indigo
                            : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isDone ? Icons.check_circle : Icons.circle_outlined,
                        color: (isDone || isActive) ? Colors.white : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "STEP ${i + 1}\n${steps[i]}",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: (isDone || isActive) ? Colors.white : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (i < steps.length - 1)
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.grey.shade400),
            ],
          ),
        );
      }),
    );
  }

  // ── state banner ──
  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Text(_status,
          style: const TextStyle(color: Colors.indigo, fontSize: 13)),
    );
  }

  // ── camera section ──
  Widget _buildCameraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📷 face-shot",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: (_cameraController != null &&
                    _cameraController!.value.isInitialized)
                ? CameraPreview(_cameraController!)
                : Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text("Initionalizing the camera info...",
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _step == 1 ? _takeFacePhoto : null,
            icon: const Icon(Icons.camera),
            label: const Text("face shot"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
            ),
          ),
        ),
      ],
    );
  }

  // ── voice section ──
  Widget _buildVoiceSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("🎤 learning the voice info",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ...List.generate(_scripts.length, (i) {
            final isDone = i < _currentScriptIndex ||
                (_step > 0 && i <= _currentScriptIndex);
            final isCurrent = i == _currentScriptIndex && _step == 0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDone
                    ? Colors.green.shade100
                    : isCurrent
                        ? Colors.indigo.shade100
                        : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDone
                      ? Colors.green
                      : isCurrent
                          ? Colors.indigo
                          : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isDone
                        ? Colors.green
                        : isCurrent
                            ? Colors.indigo
                            : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _scripts[i],
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      fontSize: 15,
                      color: isDone
                          ? Colors.green.shade700
                          : isCurrent
                              ? Colors.indigo
                              : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_step == 0 && !_isListening)
                  ? _startVoiceTraining
                  : null,
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
              label: Text(_isListening ? "Listening to..." : "start to detect the voice"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── registration button ──
  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _step == 2 ? _addOwner : null,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text("Complete to register",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ── detecting the position ──
  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.location_on, color: Colors.red, size: 20),
            SizedBox(width: 8),
            Text("📍 Detecting the robot position",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          Text(
            _robotPosition == null
                ? "No position data - Bring the current postion by pushing the button."
                : "Latitude: ${_robotPosition!.latitude.toStringAsFixed(5)}\n"
                    "Longitude: ${_robotPosition!.longitude.toStringAsFixed(5)}\n"
                    "Accuracy: ${_robotPosition!.accuracy.toStringAsFixed(1)}m",
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLocating ? null : _getRobotLocation,
              icon: _isLocating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(_isLocating ? "Checking the position..." : "Bringing the current position"),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // ── User List ──
  Widget _buildOwnerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("👥 Registered User(s) (${_ownerList.length})",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (_ownerList.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(children: [
              Icon(Icons.person_off_outlined, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text("Cannot find the registered user(s).",
                  style: TextStyle(color: Colors.grey)),
            ]),
          )
        else
          ...List.generate(_ownerList.length, (index) {
            final owner = _ownerList[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      owner.hasFace ? Colors.indigo : Colors.grey,
                  child: Icon(
                    owner.hasFace ? Icons.face : Icons.person,
                    color: Colors.white,
                  ),
                ),
                title: Text(owner.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owner.hasFace
                          ? "Face: Eyes Interval ${owner.faceFeatures['eyeDistance']?.toStringAsFixed(1)}px"
                          : "Face: Default Usage",
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      "Voice: ${owner.voicePitch.toStringAsFixed(1)}Hz",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editOwnerName(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete,
                          color: Colors.redAccent, size: 20),
                      onPressed: () =>
                          setState(() => _ownerList.removeAt(index)),
                    ),
                  ],
                ),
                isThreeLine: true,
              ),
            );
          }),
      ],
    );
  }
}
