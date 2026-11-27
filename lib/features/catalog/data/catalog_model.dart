/// Model untuk Kategori Layanan (dinamis, diatur oleh Owner)
class ServiceCategory {
  final String id;
  final String name;
  final String? iconName; // Nama icon Material, misal "iron_rounded"
  final String? colorHex; // Hex warna, misal "#0284C7"
  final int sortOrder;
  final bool isActive;
  final List<ServiceItem> services;

  ServiceCategory({
    required this.id,
    required this.name,
    this.iconName,
    this.colorHex,
    this.sortOrder = 0,
    this.isActive = true,
    this.services = const [],
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      iconName: json['iconName'],
      colorHex: json['colorHex'],
      sortOrder: json['sortOrder'] ?? 0,
      isActive: json['isActive'] != false,
      services: json['services'] != null
          ? (json['services'] as List).map((s) => ServiceItem.fromJson(s)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'iconName': iconName,
        'colorHex': colorHex,
        'sortOrder': sortOrder,
        'isActive': isActive,
      };

  ServiceCategory copyWith({
    String? id,
    String? name,
    String? iconName,
    String? colorHex,
    int? sortOrder,
    bool? isActive,
    List<ServiceItem>? services,
  }) {
    return ServiceCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      services: services ?? this.services,
    );
  }
}

/// Model untuk Layanan / Produk (item dalam kategori)
class ServiceItem {
  final String id;
  final String categoryId;
  final String name;
  final String unit; // kg, pcs, meter, porsi, item
  final double price;
  final int estHours; // Estimasi jam selesai
  final String? description;
  final bool isActive;
  final int sortOrder;

  ServiceItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.unit,
    required this.price,
    this.estHours = 24,
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    return ServiceItem(
      id: json['id'] ?? '',
      categoryId: json['categoryId'] ?? '',
      name: json['name'] ?? '',
      unit: json['unit'] ?? 'pcs',
      price: (json['price'] ?? 0).toDouble(),
      estHours: json['estHours'] ?? 24,
      description: json['description'],
      isActive: json['isActive'] != false,
      sortOrder: json['sortOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'name': name,
        'unit': unit,
        'price': price,
        'estHours': estHours,
        'description': description,
        'isActive': isActive,
        'sortOrder': sortOrder,
      };

  ServiceItem copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? unit,
    double? price,
    int? estHours,
    String? description,
    bool? isActive,
    int? sortOrder,
  }) {
    return ServiceItem(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      estHours: estHours ?? this.estHours,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// Model untuk item di keranjang POS
class CartItemData {
  final ServiceItem service;
  double qty;
  String notes;

  CartItemData({required this.service, required this.qty, this.notes = ''});

  double get subtotal => qty * service.price;
}
