# Panduan Build & Distribusi Mobile (`multibiz-mobile`)

Dokumentasi ini menjelaskan langkah build APK release dan persiapan distribusi melalui website landing page.

## 1. Arahkan `baseUrl` ke Server Produksi
Buka `lib/core/network/api_client.dart` dan ubah `baseUrl` dari `localhost:3001` ke domain HTTPS backend Anda, misalnya:

```dart
static const String baseUrl = 'https://api.domainanda.com/api/v1';
```

## 2. Daftarkan SHA-1 Release Keystore untuk Google SSO
Agar fitur **Masuk dengan Google** berfungsi pada APK yang di-download pengguna:
1. Buat release keystore (jika belum ada) dengan `keytool`.
2. Ambil SHA-1 fingerprint dari release keystore:
   ```bash
   keytool -list -v -keystore android/app/release-keystore.jks -alias release
   ```
3. Daftarkan SHA-1 tersebut ke **Google Cloud Console › APIs & Services › Credentials** pada OAuth 2.0 Client ID Android.

## 3. Build APK Release
Jalankan perintah berikut di direktori `multibiz-mobile`:

```bash
flutter pub get
flutter build apk --release
```

Hasil file APK berada di:
`build/app/outputs/flutter-apk/app-release.apk`

## 4. Upload ke Landing Page
1. Upload file `app-release.apk` ke hosting/CDN landing page Anda (misal `https://domainanda.com/download/mitracs-laundry.apk`).
2. Hubungkan tombol **Download Aplikasi** di landing page ke URL file `.apk` tersebut.
3. Sertakan catatan singkat di landing page untuk pengguna:
   - Setelah download selesai, buka file `.apk`.
   - Jika diminta Android, aktifkan **"Izinkan instalasi dari sumber ini"** (*Install unknown apps*), lalu lanjutkan instalasi.
   - Setelah terpasang, login menggunakan **Google**, isi **Username / Nama Usaha**, lalu hubungkan WhatsApp melalui menu **Opsi › Koneksi WhatsApp Outlet** (scan QR atau pakai Kode Pairing nomor WA).
