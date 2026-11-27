import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier ringan untuk memicu refresh otomatis di Beranda, Pesanan, dan Inbox
/// setiap kali ada transaksi baru, perubahan status, atau pelanggan baru.
class AppRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() {
    state = state + 1;
  }
}

final appRefreshProvider = NotifierProvider<AppRefreshNotifier, int>(() {
  return AppRefreshNotifier();
});

/// Menyimpan filter status aktif untuk tab Pesanan agar bisa dibuka langsung dari Beranda
class OrdersFilterNotifier extends Notifier<String> {
  @override
  String build() => 'ALL';

  void setFilter(String filter) {
    state = filter;
  }
}

final ordersFilterProvider = NotifierProvider<OrdersFilterNotifier, String>(() {
  return OrdersFilterNotifier();
});

/// Menyimpan jumlah pesanan masuk (MENUNGGU_VALIDASI + DITERIMA) untuk badge navigasi
class IncomingOrdersCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setCount(int count) {
    state = count;
  }
}

final incomingOrdersCountProvider =
    NotifierProvider<IncomingOrdersCountNotifier, int>(() {
  return IncomingOrdersCountNotifier();
});
