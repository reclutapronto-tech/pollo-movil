/// Equipment tracking model.
/// Tracks tools, vehicles, machinery — location and usage hours.
class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.type,
    this.serialNumber,
    this.assignedJobId,
    this.assignedTo,
    this.lastGpsLat,
    this.lastGpsLng,
    this.totalHours = 0,
    this.status = 'available',
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'tool',
      serialNumber: json['serial_number'] as String?,
      assignedJobId: json['assigned_job_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      lastGpsLat: (json['last_gps_lat'] as num?)?.toDouble(),
      lastGpsLng: (json['last_gps_lng'] as num?)?.toDouble(),
      totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'available',
    );
  }

  final String id;
  final String name;
  final String type; // tool, vehicle, machinery, other
  final String? serialNumber;
  final String? assignedJobId;
  final String? assignedTo;
  final double? lastGpsLat;
  final double? lastGpsLng;
  final double totalHours;
  final String status; // available, checked_out, maintenance, lost
}
