import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttManager {
  final String serverUri = 'test.mosquitto.org';
  final String clientId = 'sujin_robot_app_client';
  late MqttServerClient client;

  // 하드웨어 없이도 앱이 동작하도록 연결 상태 추적
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
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
      // 하드웨어 없을 때 오류가 나도 앱이 죽지 않도록 처리
      print('=== 연결 실패 (더미 모드로 전환): $e ===');
      client.disconnect();
      return;
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('=== 연결 성공! ===');
      _isConnected = true;

      client.subscribe('robot/status', MqttQos.atLeastOnce);

      client.updates!.listen((c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String pt =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        print('=== 로봇 수신: $pt ===');
      });
    }
  }

  void sendCommand(String command) {
    if (!_isConnected) {
      print('=== [더미 모드] 명령: $command (실제 전송 안 됨) ===');
      return;
    }
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      client.publishMessage('robot/control', MqttQos.exactlyOnce, builder.payload!);
      print('=== 로봇에게 명령 전송: $command ===');
    } catch (e) {
      print('=== 명령 전송 실패: $e ===');
    }
  }

  void disconnect() {
    if (_isConnected) client.disconnect();
    _isConnected = false;
    print('=== 연결 종료 ===');
  }
}