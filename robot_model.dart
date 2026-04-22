class RobotData{
  final int battery;
  final String status;

  RobotData({required this.battery, required this.status});

  factory RobotData.fromJson(Map<String, dynamic> json){
    return RobotData(
      battery: json['battery'] ?? 0,
      status: json['status'] ?? 'Unable to connect'
      );
  }
}
