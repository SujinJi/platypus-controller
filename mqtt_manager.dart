import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttManager {
  final String serverUri = 'test.mosquitto.org';
  final String clientId = 'sujin_robot_app_client';
  late MqttServerClient client;

  // detecting the conncetion state to be able to operate the APP without HW
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    client = MqttServerClient(serverUri, clientId);
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;

    client.onDisconnected = () {
      print('=== MQTT connect initionalized ===');
      _isConnected = false;
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;

    try {
      print('=== Connecting to the robot server... ===');
      await client.connect();
    } catch (e) {
      // without HW -> if it comes out "fail", not let APP be logged out
      print('=== failed to connect (convert to 'Dummy Mode'): $e ===');
      client.disconnect();
      return;
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('=== Approved! ===');
      _isConnected = true;

      client.subscribe('robot/status', MqttQos.atLeastOnce);

      client.updates!.listen((c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String pt =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        print('=== Reception form the robot: $pt ===');
      });
    }
  }

  void sendCommand(String command) {
    if (!_isConnected) {
      print('=== [Dummy Mode] Request: $command (Not be sent in actual) ===');
      return;
    }
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      client.publishMessage('robot/control', MqttQos.exactlyOnce, builder.payload!);
      print('=== Sending the request to the robot: $command ===');
    } catch (e) {
      print('=== Unable to send the request: $e ===');
    }
  }

  void disconnect() {
    if (_isConnected) client.disconnect();
    _isConnected = false;
    print('=== End to connect ===');
  }
}
