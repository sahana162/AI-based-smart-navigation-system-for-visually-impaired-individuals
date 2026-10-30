/// Model representing an enrolled friend with facial identification profile.
class FriendProfile {
  final String id;
  final String name;
  final String imagePath;
  final DateTime enrolledAt;

  const FriendProfile({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.enrolledAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'enrolledAt': enrolledAt.toIso8601String(),
  };

  factory FriendProfile.fromJson(Map<String, dynamic> json) {
    return FriendProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Friend',
      imagePath: json['imagePath'] as String? ?? '',
      enrolledAt: json['enrolledAt'] != null
          ? DateTime.tryParse(json['enrolledAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  String toString() => 'FriendProfile(id: $id, name: $name, imagePath: $imagePath, enrolledAt: $enrolledAt)';
}
