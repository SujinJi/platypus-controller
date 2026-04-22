// Architecture Overview (Mobile App Controller):
// UI Layer: main.dart (Handles the entire main interface).
// Identity System: Manages user IDs/names and handles authentication.
// Data Manager: Oversees all user and robot-related information.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'mqtt_manager.dart';
import 'owner_manager.dart';
import 'robot_status.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.camera, Permission.microphone, Permission.location].request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controlling the Platypus Robot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeMenuScreen(),
    );
  }
}

class HomeMenuScreen extends StatefulWidget {
  const HomeMenuScreen({super.key});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen> {
  final String _robotName = "Platypus";
  final MqttManager _mqttManager = MqttManager();
  bool _mqttConnected = false;

  @override
  void initState() {
    super.initState();
    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    await _mqttManager.connect();
    if (mounted) setState(() => _mqttConnected = _mqttManager.isConnected);
  }

  @override
  void dispose() {
    _mqttManager.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$_robotName Home System"),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 50.0),
            child: Column(
              children: [
                const Icon(Icons.smart_toy_rounded, size: 140, color: Colors.indigo),
                const SizedBox(height: 20),
                Text(
                  "$_robotName Intelligent control",
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  _mqttConnected ? "Operating Current System" : "Dummy Mode (Hardware Disconnect)",
                  style: TextStyle(
                    color: _mqttConnected ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 50),

                // ① User Management Center
                _buildMenuButton(
                  context,
                  "User Management Center",
                  "Register User, Revise or destination detect",
                  Icons.person_search_rounded,
                  Colors.blue,
                  const MultiOwnerControlScreen(),
                ),

                const SizedBox(height: 16),

                // ② Reporting Robot Statement 
                _buildMenuButton(
                  context,
                  "Reporting Robot Statement",
                  "System Diagnosis and Checking Hardware-Log",
                  Icons.insights_rounded,
                  Colors.teal,
                  const RobotStatusScreen(),
                ),

                const SizedBox(height: 40),
                const Text("v1.0.4 - Platypus Tech",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    Widget destination,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => destination)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }
}
