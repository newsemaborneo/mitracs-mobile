class StringUtils {
  /// Mengambil inisial huruf pertama yang aman dari karakter non-BMP / Unicode surrogate pairs
  /// (misal font WhatsApp fancy / emoji: 𝑐𝑖𝑝𝑖𝑛𝑛, 𝕬𝖇𝖈, dll)
  static String getInitial(dynamic name, {String fallback = 'P'}) {
    if (name == null) return fallback;
    final str = name.toString().trim();
    if (str.isEmpty) return fallback;
    final runes = str.runes;
    if (runes.isEmpty) return fallback;
    final firstChar = String.fromCharCode(runes.first);
    return firstChar.toUpperCase();
  }
}
