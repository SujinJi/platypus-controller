import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/* -------------------------------------------------------
 * MqttManager — 싱글톤
 *
 * 수정 내용:
 *   1. factory 생성자로 싱글톤 보장 → 클라이언트 ID 충돌 방지
 *   2. connect() 내부의 subscribe / updates.listen 제거
 *      → 구독은 각 화면(robot_status.dart)에서만 담당
 *   3. isConnected getter 유지 — main.dart 호환
 * ------------------------------------------------------- */
class MqttManager {
  static final MqttManager _instance = MqttManager._internal();
  factory MqttManager() => _instance;
  MqttManager._internal();

  final String serverUri = 'test.mosquitto.org';
  final String clientId  = 'sujin_robot_app_client';

  late MqttServerClient client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    // 이미 연결되어 있으면 재연결 생략
    if (_isConnected) return;

    client = MqttServerClient(serverUri, clientId);
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;

    client.onDisconnected = () {
      print('=== MQTT 연결 해제됨 ===');
      _isConnected = false;
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;

    try {
      print('=== 로봇 서버 연결 중... ===');
      await client.connect();
    } catch (e) {
      print('=== 연결 실패 (더미 모드로 전환): $e ===');
      client.disconnect();
      return;
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('=== 연결 성공! ===');
      _isConnected = true;
      // ※ subscribe / updates.listen 은 여기서 하지 않음
      //    각 화면에서 필요한 토픽만 구독하도록 위임
    }
  }

  void disconnect() {
    if (_isConnected) client.disconnect();
    _isConnected = false;
    print('=== 연결 종료 ===');
  }
}
