import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'mqtt_manager.dart';
import 'package:mqtt_client/mqtt_client.dart';

/* -------------------------------------------------------
 * 로봇 상태 대시보드
 *
 * robot/status 토픽 수신 페이로드 구조:
 * {
 *   "state":        "IDLE" | "OBSTACLE" | "OWNER_NEAR" | "PETTED" | "DIGGING",
 *   "obstacle":     true | false,
 *   "touch":        true | false,
 *   "owner_nearby": true | false,
 *   "distance_cm":  45.2,
 *   "battery":      -1,   // 미장착 시 -1
 *   "temp":         -1    // 미장착 시 -1
 * }
 *
 * robot/gps 토픽 수신 페이로드 구조:
 * {"lat": 37.451230, "lon": 127.124560}
 * ------------------------------------------------------- */

class RobotStatusScreen extends StatefulWidget {
  const RobotStatusScreen({super.key});

  @override
  State<RobotStatusScreen> createState() => _RobotStatusScreenState();
}

class _RobotStatusScreenState extends State<RobotStatusScreen> {
  final MqttManager _mqtt = MqttManager();

  // ── 상태값 ──
  String _robotState   = '연결 대기 중';
  bool   _obstacle     = false;
  bool   _touch        = false;
  bool   _ownerNearby  = false;
  double _distanceCm   = 0.0;
  int    _battery      = -1;
  int    _temp         = -1;

  // ── GPS ──
  double? _lat;
  double? _lon;

  // ── 연결·수신 시각 ──
  bool     _mqttConnected  = false;
  DateTime? _lastUpdated;

  // 수신 없을 때 타임아웃 표시용 타이머
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  Future<void> _connectAndListen() async {
    await _mqtt.connect();

    if (!_mqtt.isConnected) {
      if (mounted) setState(() => _mqttConnected = false);
      return;
    }

    if (mounted) setState(() => _mqttConnected = true);

    // robot/status 와 robot/gps 구독
    _mqtt.client.subscribe('robot/status', MqttQos.atLeastOnce);
    _mqtt.client.subscribe('robot/gps',    MqttQos.atLeastOnce);

    _mqtt.client.updates!.listen((messages) {
      for (final msg in messages) {
        final topic   = msg.topic;
        final payload = MqttPublishPayload.bytesToStringAsString(
            (msg.payload as MqttPublishMessage).payload.message);

        try {
          final Map<String, dynamic> data = jsonDecode(payload);

          if (topic == 'robot/status') {
            _applyStatus(data);
          } else if (topic == 'robot/gps') {
            _applyGps(data);
          }
        } catch (e) {
          debugPrint('[Status] JSON 파싱 오류: $e');
        }
      }
    });

    // 30초 수신 없으면 연결 끊김으로 표시
    _resetTimeoutTimer();
  }

  void _applyStatus(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _robotState  = data['state']        ?? '알 수 없음';
      _obstacle    = data['obstacle']     ?? false;
      _touch       = data['touch']        ?? false;
      _ownerNearby = data['owner_nearby'] ?? false;
      _distanceCm  = (data['distance_cm'] ?? 0.0).toDouble();
      _battery     = data['battery']      ?? -1;
      _temp        = data['temp']         ?? -1;
      _lastUpdated = DateTime.now();
    });
    _resetTimeoutTimer();
  }

  void _applyGps(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _lat = (data['lat'] ?? 0.0).toDouble();
      _lon = (data['lon'] ?? 0.0).toDouble();
    });
  }

  void _resetTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() => _robotState = '신호 없음 (30초 초과)');
      }
    });
  }

  // ── 상태 → 색상·아이콘 ──
  Color _stateColor() {
    switch (_robotState) {
      case 'OBSTACLE':   return Colors.red;
      case 'OWNER_NEAR': return Colors.indigo;
      case 'PETTED':     return Colors.pink;
      case 'DIGGING':    return Colors.brown;
      case 'IDLE':       return Colors.green;
      default:           return Colors.grey;
    }
  }

  String _stateLabel() {
    switch (_robotState) {
      case 'OBSTACLE':   return '⚠️ 장애물 경계';
      case 'OWNER_NEAR': return '🐾 주인 발견';
      case 'PETTED':     return '💕 쓰다듬기';
      case 'DIGGING':    return '🌱 땅 파기';
      case 'IDLE':       return '😴 대기 중';
      default:           return _robotState;
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _mqtt.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 로봇 상태'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.circle,
              size: 14,
              color: _mqttConnected ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _connectAndListen,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildConnectionBanner(),
            const SizedBox(height: 16),
            _buildStateCard(),
            const SizedBox(height: 12),
            _buildSensorGrid(),
            const SizedBox(height: 12),
            _buildGpsCard(),
            const SizedBox(height: 24),
            _buildLastUpdated(),
          ],
        ),
      ),
    );
  }

  // ── MQTT 연결 상태 배너 ──
  Widget _buildConnectionBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _mqttConnected
            ? Colors.green.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _mqttConnected ? Colors.green : Colors.orange,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _mqttConnected ? Icons.wifi : Icons.wifi_off,
            color: _mqttConnected ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 10),
          Text(
            _mqttConnected
                ? 'MQTT 연결됨 — 실시간 수신 중'
                : '연결 안 됨 — 아래로 당겨 재연결',
            style: TextStyle(
              color: _mqttConnected ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── 현재 상태 카드 ──
  Widget _buildStateCard() {
    final color = _stateColor();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(Icons.smart_toy_rounded, color: color, size: 30),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('현재 상태',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                _stateLabel(),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 센서 그리드 ──
  Widget _buildSensorGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        _sensorTile('거리', '${_distanceCm.toStringAsFixed(1)} cm',
            Icons.radar, Colors.blue),
        _sensorTile('장애물', _obstacle ? '감지됨' : '없음',
            Icons.warning_amber_rounded,
            _obstacle ? Colors.red : Colors.green),
        _sensorTile('주인 근처', _ownerNearby ? '근처 있음' : '없음',
            Icons.person_search_rounded,
            _ownerNearby ? Colors.indigo : Colors.grey),
        _sensorTile('터치', _touch ? '감지됨' : '없음',
            Icons.touch_app_rounded,
            _touch ? Colors.pink : Colors.grey),
        _sensorTile(
          '배터리',
          _battery == -1 ? '센서 미장착' : '$_battery%',
          Icons.battery_charging_full,
          _battery == -1 ? Colors.grey : (_battery > 30 ? Colors.green : Colors.red),
        ),
        _sensorTile(
          '온도',
          _temp == -1 ? '센서 미장착' : '$_temp°C',
          Icons.thermostat_auto,
          _temp == -1 ? Colors.grey : (_temp < 45 ? Colors.green : Colors.deepOrange),
        ),
      ],
    );
  }

  Widget _sensorTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── GPS 카드 ──
  Widget _buildGpsCard() {
    final hasGps = _lat != null && _lon != null;
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
            Icon(Icons.location_on, color: Colors.red, size: 18),
            SizedBox(width: 6),
            Text('로봇 GPS 위치',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          Text(
            hasGps
                ? '위도: ${_lat!.toStringAsFixed(6)}\n'
                  '경도: ${_lon!.toStringAsFixed(6)}'
                : '로봇에서 GPS 신호를 수신하지 못했습니다.\n'
                  '(GPS 모듈 미연결 또는 실외 신호 필요)',
            style: TextStyle(
              fontSize: 13,
              color: hasGps ? Colors.black87 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ── 마지막 수신 시각 ──
  Widget _buildLastUpdated() {
    return Center(
      child: Text(
        _lastUpdated == null
            ? '아직 데이터를 수신하지 못했습니다.'
            : '마지막 수신: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:'
              '${_lastUpdated!.minute.toString().padLeft(2, '0')}:'
              '${_lastUpdated!.second.toString().padLeft(2, '0')}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    );
  }
}
