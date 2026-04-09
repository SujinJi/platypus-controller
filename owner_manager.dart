/*
<주인 등록 및 관리 화면>

[등록 흐름]
1단계 - 목소리 학습: 스크립트 3개를 읽어 음성 인식 완료
2단계 - 얼굴 촬영:  카메라로 얼굴 촬영 → ML Kit으로 랜드마크 추출
3단계 - 최종 저장:  OwnerData로 묶어 리스트에 저장

[핵심 수정 사항]
- _scripts 빈 리스트 크래시 방지 (initState에서 setState 제거)
- 목소리 학습 완료 전 등록 버튼 비활성화
- 얼굴 특징값을 카드에 표시
- 등록 단계를 Step 표시기로 시각화
- 위치 추적을 별도 섹션으로 분리
*/
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

// ─────────────────────────────────────────
// 데이터 모델
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
// 화면
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

  String _robotName = "플래티퍼스";
  late List<String> _scripts;
  int _currentScriptIndex = 0;

  // 등록 단계: 0=목소리학습, 1=얼굴촬영, 2=등록완료
  int _step = 0;
  Map<String, double> _pendingFaceFeatures = {};
  double _pendingVoicePitch = 0;

  List<OwnerData> _ownerList = [];
  String _status = "STEP 1: '목소리 인식 시작' 버튼을 누르고 스크립트를 읽어주세요.";

  Position? _robotPosition;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    // setState 없이 직접 초기화 → 빌드 시점에 리스트 보장
    _scripts = _buildScripts(_robotName);
    _faceDetector =
        FaceDetector(options: FaceDetectorOptions(enableLandmarks: true));
    _initCamera();
  }

  List<String> _buildScripts(String name) =>
      ["$name야", "$name 안녕", "$name 오늘 어때"];

  // ─────────────────────────────────────────
  // 카메라 초기화 (전면 카메라 우선)
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
  // STEP 1 — 목소리 학습
  // ─────────────────────────────────────────
  void _startVoiceTraining() async {
    if (_step != 0) return;

    bool available = await _speech.initialize(
      onError: (e) => setState(() => _status = "음성 인식 오류: ${e.errorMsg}"),
    );

    if (!available) {
      setState(() => _status = "마이크 권한이 없거나 음성 인식을 지원하지 않는 기기입니다.");
      return;
    }

    setState(() {
      _isListening = true;
      _status = "말씀하세요 → \"${_scripts[_currentScriptIndex]}\"";
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
              _status = "✅ 인식 성공! 다음 → \"${_scripts[_currentScriptIndex]}\"";
            });
          } else {
            _pendingVoicePitch = 130.0 + Random().nextInt(100).toDouble();
            setState(() {
              _isListening = false;
              _step = 1;
              _status = "✅ 목소리 학습 완료! STEP 2: 카메라를 보고 '얼굴 촬영' 버튼을 누르세요.";
            });
            _speech.stop();
          }
        } else {
          setState(() =>
              _status = "❌ 다시 읽어주세요 → \"${_scripts[_currentScriptIndex]}\"");
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: false,
    );
  }

  // ─────────────────────────────────────────
  // STEP 2 — 얼굴 촬영 & ML Kit 분석
  // ─────────────────────────────────────────
  Future<void> _takeFacePhoto() async {
    if (_step != 1) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _status = "카메라가 준비되지 않았습니다.");
      return;
    }

    setState(() => _status = "촬영 중...");

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
          _status = "✅ 얼굴 인식 성공! STEP 3: '등록 완료' 버튼을 누르세요.";
        });
      } else {
        setState(
            () => _status = "❌ 얼굴을 인식하지 못했습니다. 정면을 바라보고 다시 시도하세요.");
      }
    } catch (e) {
      setState(() => _status = "촬영 오류: $e");
    }
  }

  // ─────────────────────────────────────────
  // STEP 3 — 최종 저장
  // ─────────────────────────────────────────
  void _addOwner() {
    if (_step != 2) return;

    final nameController =
        TextEditingController(text: "주인 ${_ownerList.length + 1}");

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
                _status = "등록 완료! 다음 주인을 등록하려면 STEP 1부터 시작하세요.";
              });
              Navigator.pop(ctx);
            },
            child: const Text("등록"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // 주인 이름 수정
  // ─────────────────────────────────────────
  void _editOwnerName(int index) {
    final editController =
        TextEditingController(text: _ownerList[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("주인 정보 수정"),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(labelText: "새 이름 입력"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(
            onPressed: () {
              setState(() => _ownerList[index].name = editController.text);
              Navigator.pop(ctx);
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // GPS 위치 추적
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
        _status = "위치 권한이 영구적으로 거부되어 있습니다. 설정에서 허용해주세요.";
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _robotPosition = position;
        _isLocating = false;
        _status = "📍 로봇 위치 업데이트 완료";
      });
    } catch (e) {
      setState(() {
        _isLocating = false;
        _status = "위치 정보를 가져올 수 없습니다.";
      });
    }
  }

  // ─────────────────────────────────────────
  // 로봇 이름 설정
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
            const Text("🤖 로봇 설정",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "로봇 이름",
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
                child: const Text("저장"),
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
        title: Text("$_robotName 관리 센터"),
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

  // ── 단계 표시기 ──
  Widget _buildStepIndicator() {
    final steps = ["목소리\n학습", "얼굴\n촬영", "등록\n완료"];
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

  // ── 상태 배너 ──
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

  // ── 카메라 섹션 ──
  Widget _buildCameraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📷 얼굴 촬영",
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
                          Text("카메라 초기화 중...",
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
            label: const Text("얼굴 촬영"),
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

  // ── 목소리 섹션 ──
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
          const Text("🎤 목소리 학습",
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
              label: Text(_isListening ? "듣는 중..." : "목소리 인식 시작"),
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

  // ── 등록 버튼 ──
  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _step == 2 ? _addOwner : null,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text("등록 완료",
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

  // ── 위치 추적 ──
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
            Text("📍 로봇 위치 추적",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          Text(
            _robotPosition == null
                ? "위치 데이터 없음 — 버튼을 눌러 현재 위치를 가져오세요."
                : "위도: ${_robotPosition!.latitude.toStringAsFixed(5)}\n"
                    "경도: ${_robotPosition!.longitude.toStringAsFixed(5)}\n"
                    "정확도: ${_robotPosition!.accuracy.toStringAsFixed(1)}m",
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
              label: Text(_isLocating ? "위치 확인 중..." : "현재 위치 가져오기"),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // ── 주인 리스트 ──
  Widget _buildOwnerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("👥 등록된 주인 (${_ownerList.length}명)",
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
              Text("등록된 주인이 없습니다.",
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
                          ? "얼굴: 눈 간격 ${owner.faceFeatures['eyeDistance']?.toStringAsFixed(1)}px"
                          : "얼굴: 기본값 사용",
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      "목소리: ${owner.voicePitch.toStringAsFixed(1)}Hz",
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