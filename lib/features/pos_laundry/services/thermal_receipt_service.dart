import 'dart:convert';
import 'package:intl/intl.dart';

/// Thermal Receipt generator for ESC/POS Bluetooth printers (58mm / 80mm).
/// Generates standard ESC/POS bytecode bytes for thermal receipt printing.
class ThermalReceiptService {
  // ESC/POS Commands
  static const List<int> escInit = [0x1B, 0x40]; // Initialize printer
  static const List<int> escCenter = [0x1B, 0x61, 0x01]; // Align center
  static const List<int> escLeft = [0x1B, 0x61, 0x00]; // Align left
  static const List<int> escRight = [0x1B, 0x61, 0x02]; // Align right
  static const List<int> escBoldOn = [0x1B, 0x45, 0x01]; // Bold on
  static const List<int> escBoldOff = [0x1B, 0x45, 0x00]; // Bold off
  static const List<int> escDoubleHeight = [0x1B, 0x21, 0x10]; // Double height
  static const List<int> escNormal = [0x1B, 0x21, 0x00]; // Normal text
  static const List<int> escFeedCut = [0x1D, 0x56, 0x41, 0x03]; // Feed and cut
  static const List<int> escFeedLines = [0x1B, 0x64, 0x02]; // Feed 2 lines

  /// Generate 58mm (32 columns) thermal receipt bytes
  static List<int> generateLaundryReceiptBytes({
    required String businessName,
    required String outletName,
    required String orderNumber,
    required String customerName,
    required String customerPhone,
    required List<Map<String, dynamic>> items,
    required double total,
    required String paymentStatus,
    required String paymentMethod,
    DateTime? createdAt,
  }) {
    final bytes = <int>[];
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(createdAt ?? DateTime.now());
    final currencyFmt = NumberFormat('#,###', 'id_ID');

    void appendBytes(List<int> cmd) => bytes.addAll(cmd);
    void appendLine(String text) => bytes.addAll(utf8.encode('$text\n'));

    // 1. Init
    appendBytes(escInit);

    // 2. Header (Center)
    appendBytes(escCenter);
    appendBytes(escBoldOn);
    appendBytes(escDoubleHeight);
    appendLine(businessName.toUpperCase());
    appendBytes(escNormal);
    appendBytes(escBoldOff);
    appendLine(outletName);
    appendLine('================================'); // 32 chars for 58mm

    // 3. Order Info (Left)
    appendBytes(escLeft);
    appendLine('No Nota : $orderNumber');
    appendLine('Waktu   : $dateStr');
    appendLine('Pelanggan: $customerName');
    appendLine('WhatsApp: $customerPhone');
    appendLine('--------------------------------');

    // 4. Items Table
    for (final item in items) {
      final name = item['serviceName'] ?? 'Layanan';
      final qty = item['qty']?.toString() ?? '1';
      final unit = item['unit'] ?? 'kg';
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      final subtotal = (double.tryParse(qty) ?? 1) * price;

      appendBytes(escBoldOn);
      appendLine(name);
      appendBytes(escBoldOff);

      final qtyPriceStr = ' $qty $unit x ${currencyFmt.format(price)}';
      final subtotalStr = 'Rp ${currencyFmt.format(subtotal)}';

      // Format aligned 32 columns
      final spaces = 32 - (qtyPriceStr.length + subtotalStr.length);
      final spaceStr = spaces > 0 ? ' ' * spaces : ' ';
      appendLine('$qtyPriceStr$spaceStr$subtotalStr');
    }
    appendLine('--------------------------------');

    // 5. Total & Payment
    final totalLabel = 'TOTAL:';
    final totalVal = 'Rp ${currencyFmt.format(total)}';
    final spacesTotal = 32 - (totalLabel.length + totalVal.length);
    appendBytes(escBoldOn);
    appendLine('$totalLabel${' ' * (spacesTotal > 0 ? spacesTotal : 1)}$totalVal');
    appendBytes(escBoldOff);

    final payStatusStr = paymentStatus == 'PAID' ? 'LUNAS ($paymentMethod)' : 'BELUM LUNAS';
    appendLine('Status Bayar: $payStatusStr');
    appendLine('================================');

    // 6. Footer (Center)
    appendBytes(escCenter);
    appendLine('Simpan nota ini untuk pengambilan.');
    appendLine('Info otomatis dikirim via WhatsApp.');
    appendLine('Terima Kasih atas Kunjungan Anda!');
    appendBytes(escFeedLines);
    appendBytes(escFeedCut);

    return bytes;
  }
}
