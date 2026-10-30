/// Persistent spatial memory model representing an item and where the user stored or kept it.
class RememberedItem {
  final String id;
  final String itemName;
  final String locationDescription;
  final DateTime timestamp;

  const RememberedItem(
    this.id,
    this.itemName,
    this.locationDescription,
    this.timestamp,
  );

  const RememberedItem.named({
    required this.id,
    required this.itemName,
    required this.locationDescription,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemName': itemName,
        'locationDescription': locationDescription,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RememberedItem.fromJson(Map<String, dynamic> json) {
    return RememberedItem(
      json['id'] as String? ?? '',
      json['itemName'] as String? ?? '',
      json['locationDescription'] as String? ?? '',
      json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RememberedItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'RememberedItem(id: $id, itemName: $itemName, locationDescription: $locationDescription, timestamp: $timestamp)';
}
