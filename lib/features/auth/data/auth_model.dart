class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final bool isPlatformSuperAdmin;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.isPlatformSuperAdmin = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      avatarUrl: json['avatarUrl'],
      isPlatformSuperAdmin: json['isPlatformSuperAdmin'] == true,
    );
  }
}

class BusinessModel {
  final String id;
  final String name;
  final String category;
  final String role;
  final String? outletId;
  final String? outletName;
  final String? phoneNumber;
  final String? address;
  final String? operationalHours;

  BusinessModel({
    required this.id,
    required this.name,
    required this.category,
    required this.role,
    this.outletId,
    this.outletName,
    this.phoneNumber,
    this.address,
    this.operationalHours,
  });

  factory BusinessModel.fromJson(Map<String, dynamic> json) {
    return BusinessModel(
      id: json['id'] ?? json['businessId'] ?? '',
      name: json['name'] ?? json['businessName'] ?? '',
      category: json['category'] ?? 'LAUNDRY',
      role: json['role'] ?? 'OWNER',
      outletId: json['outlets'] != null && (json['outlets'] as List).isNotEmpty ? json['outlets'][0]['id'] : json['outletId'],
      outletName: json['outlets'] != null && (json['outlets'] as List).isNotEmpty ? json['outlets'][0]['outletName'] : json['outletName'],
      phoneNumber: json['phoneNumber'] ?? (json['outlets'] != null && (json['outlets'] as List).isNotEmpty ? json['outlets'][0]['phoneNumber'] : null),
      address: json['address'] ?? (json['outlets'] != null && (json['outlets'] as List).isNotEmpty ? json['outlets'][0]['address'] : null),
      operationalHours: json['operationalHours'] ?? 'Setiap Hari: 08:00 - 21:00',
    );
  }
}
