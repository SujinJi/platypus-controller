/*
<Robot Status Monitoring Dashboard>

Serves as a "control panel" that displays the robot's current health status at a glance.

1. Data Visualization: 
Sensor data such as battery level, temperature, and network connection status are neatly organized and displayed as card widgets.
2. Status Report:
Rather than complex control logic, the focus is on communicating the robot's current hardware condition to the user.
3. Periodic Data Fetching:
Sensor data values (battery, temperature, network, and sensor status) are fetched at regular intervals.
4. Score-Based Logic:
The score passed to _getStatusTheme(score) changes dynamically based on the fetched values.
5. Reactive Theming:
When the score changes, the color scheme and status text update automatically.
*/

import 'dart:async'; // Include Class Timer in order to execute the function periodically
import 'package:flutter/material.dart';

// [Screen Widget] Timly dashboard which shows the Robot HW State(Battery, Network etc).
class RobotStatusScreen extends StatefulWidget {
  const RobotStatusScreen({super.key});

  @override
  State<RobotStatusScreen> createState() => _RobotStatusScreenState();
}

class _RobotStatusScreenState extends State<RobotStatusScreen> {
  // [상태 변수] 로봇의 현재 컨디션을 점수화(0 ~ 5점)하여 저장하는 변수들
  int batteryScore = 4; // 배터리 효율성 점수
  int networkScore = 5; // 네트워크 연결 강도 점수
  int tempScore = 3; //모터 및 시스템 온도 안전 점수
  int sensorScore = 2; // 각종 센서(초음파, 적외선 등)작동 점수

  // [시뮬레이션 데이터] 실제 로봇에서 받아올 구체적인 수치 값들
  int batteryValue = 85; // 실제 배터리 잔량(%)
  int tempValue = 38; // 실제 측정 온도 (℃)

  // 주기적으로 코드를 실행하기 위한 타이머 객체
  late Timer _timer;

  @override
  void initState() {
    super.initState();

    // [기능] 3초마다 로봇의 센서값이 변하는 상황을 시뮬레이션함
    // 실제 로봇 개발 시에는 이곳에서 로봇의 API(ROS, HTTP 등)를 호출하여 실시간 데이터를 가져옴
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // 위젯이 화면에 붙어있는 상태(mounted)인지 확인하여 메모리 오류 방지
      if (!mounted) return; // 화면이 닫혔을 때 메모리 누수 방지
      
      setState(() {
        // 1. 배터리 시뮬레이션: 2%씩 감소하다가 10% 미만이 되면 다시 95%로 충전됨 (테스트용)
        batteryValue = (batteryValue > 10) ? batteryValue - 2 : 95;
        // 베터리 잔량에 따라 0 ~ 5점 사이의 점수로 환산 (20%당 1점)
        batteryScore = (batteryValue / 20).floor().clamp(0, 5);

        // 2. 온도 시뮬레이션: 35도에서 50도 사이를 왔다갔다 함
        tempValue = 35 + (timer.tick % 15); 
        // 온도가 높을수록 점수를 낮게 받음 (위험도 상승)
        tempScore = (tempValue > 45) ? 1 : (tempValue > 40 ? 3 : 5);

        // 3. 센서 점수: 0 ~ 5 사이를 순환하며 변화
        sensorScore = (sensorScore + 1) % 6;
        
        // [알림 로직] 센서 점수가 '위험(0점)'이 되면 사용자에게 팝업 알림을 띄움
        if (sensorScore == 0) {
          _showWarningSnackBar();
        }
      });
    });
  }

  @override
  void dispose() {
    //[중요] 화면이 닫힐 때 타이머를 반드시 정지시켜야 메모리 낭비와 앱 버벅임을 방지할 수 있음
    _timer.cancel(); // 페이지 이탈 시 타이머 종료
    super.dispose();
  }

  // [사용자 알림] 화면 하단에 빨간색 경고 메시지를 띄우는 함수
  void _showWarningSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("⚠️ 로봇 센서에 치명적 오류가 감지되었습니다!"),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 2),
        // 알림창 옆에 '로그 확인' 버튼을 배치하여 인터랙션 재공
        action: SnackBarAction(label: "로그확인", textColor: Colors.white, onPressed: () {}),
      ),
    );
  }

  // [테마 엔진] 점수(0~5)를 입력 받아 그에 맞는 색상과 텍스트 정보를 반환함
  // 디자인 코드가 간결해지고 유지보수 쉽게함
  Map<String, dynamic> _getStatusTheme(int score) {
    switch (score) {
      case 5: return {"color": Colors.blue, "text": "최상", "desc": "Excellent"};
      case 4: return {"color": Colors.green, "text": "좋음", "desc": "Good"};
      case 3: return {"color": Colors.lightGreen, "text": "보통", "desc": "Stable"};
      case 2: return {"color": Colors.orangeAccent, "text": "주의", "desc": "Caution"};
      case 1: return {"color": Colors.deepOrange, "text": "경고", "desc": "Warning"};
      case 0: return {"color": const Color.fromARGB(255, 138, 11, 2), "text": "위험", "desc": "Critical"};
      default: return {"color": Colors.grey, "text": "연결 끊김", "desc": "Unknown"};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("실시간 로봇 상태 리포트"),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          // 배경에 아주 연한 그라데이션을 주어 대시보드 느낌 강조
          color: Colors.grey.shade50, // 대시보드 배경: 연한 회색
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text("시스템 실시간 모니터링",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const Text("마지막 업데이트: 방금 전", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(height: 30, thickness: 1),

              // [메인 영역] 상태 카드들을 리스트 형태로 나열
              Expanded(
                child: ListView(
                  children: [
                    _statusCard("배터리 시스템", "$batteryValue%", batteryScore, Icons.battery_charging_full),
                    _statusCard("네트워크 상태", "5G 연결됨", networkScore, Icons.wifi_protected_setup),
                    _statusCard("구동 모터 온도", "$tempValue°C", tempScore, Icons.thermostat_auto),
                    _statusCard("충돌 방지 센서", sensorScore == 0 ? "오류 발생" : "정상", sensorScore, Icons.sensors),
                    
                    // [확장] 신규 추가 항목: CPU 부하율 
                    _statusCard("프로세서 점유율", "${(100 - (networkScore * 10))}%", networkScore, Icons.memory),
                  ],
                ),
              ),

              // [하단 영역] 안전 주의사항 및 복귀 버튼
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey),
                        SizedBox(width: 8),
                        Text("상태가 '위험'일 경우 로봇 운행을 즉시 중단하십시오.",
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.home_filled),
                        label: const Text("메인 메뉴로 복귀", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // [커스텀 위젯] 개별 상태 항목을 카드 형태로 그리는 함수
  Widget _statusCard(String title, String value, int score, IconData icon) {
    // 현재 점수에 맞는 테마(색상, 텍스트)를 가져옴
    final theme = _getStatusTheme(score);
    final Color statusColor = theme['color'];

    return AnimatedContainer(
      // [기능] 데이터가 바뀔 때 배경색이나 테두리 색상이 0.5초 동안 부드럽게 변함
      duration: const Duration(milliseconds: 500), // 상태 변화 시 부드러운 색상 전환
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5), // 상태색상 테두리
        boxShadow: [
          BoxShadow(color: statusColor.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        // 왼쪽 아이콘 영역
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1), 
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: statusColor, size: 28),
        ),
        // 중앙 텍스트 영역
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Row(
          children: [
            // 작은 상태 표시 점
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text("${theme['text']} (${theme['desc']})", 
                 style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        // 오른쪽 수치 표시 영역
        trailing: Text(value,                          //black color
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.grey.shade800)),
      ),
    );
  }
}
