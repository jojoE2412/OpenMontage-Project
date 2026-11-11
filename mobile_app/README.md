# OpenMontage Mobile

Aplikasi mobile Flutter untuk OpenMontage. Aplikasi ini menyediakan antarmuka untuk menjelajahi fitur, membuat dan mengelola project, memilih aset, serta mengirim dan memantau pekerjaan video melalui backend OpenMontage.

## Status proyek

Frontend mobile sedang dikembangkan dan terhubung ke API backend OpenMontage. Ketersediaan fitur AI mengikuti capability dan provider yang benar-benar diiklankan backend. Dukungan provider bergantung pada konfigurasi, perangkat, kredensial, dan biaya yang tersedia; tampilan aplikasi tidak menjamin semua provider dapat digunakan.

Pengujian generasi video lokal pada laptop dengan NVIDIA GeForce GTX 1650 4 GB pernah berakhir dengan status job `failed` setelah proses yang lama. Generasi cloud Hugging Face pernah menghasilkan video pemandangan gunung berdurasi 5 detik, tetapi pengujian cloud belum dapat diulang saat ini karena keterbatasan biaya/token. Hasil pengujian ini bukan jaminan bahwa provider atau pipeline saat ini tersedia.

## Fitur frontend

- Home, Create, Projects, Library, dan Profile.
- Katalog fitur dan halaman untuk workflow video, gambar, audio, subtitle, editing, serta enhancement.
- AI Video Generator dengan pilihan provider/model dan parameter berdasarkan opsi yang diberikan backend.
- Pemantauan status job dan tampilan artifact/video jika backend mengembalikan hasil yang dapat diputar.
- Penyimpanan data project dan Library lokal pada aplikasi.
- Pengaturan aplikasi dan navigasi antarfitur.

Sebagian halaman atau operasi memerlukan capability backend yang sesuai. Jika provider tidak tersedia atau operasi belum didukung, hasilnya mengikuti respons backend dan dapat ditampilkan sebagai tidak tersedia/gagal.

## Prasyarat

- Flutter SDK yang sesuai dengan batas SDK pada `pubspec.yaml`.
- Android Studio atau Android SDK untuk menjalankan aplikasi Android.
- Backend OpenMontage berjalan dan dapat dijangkau dari emulator/perangkat untuk fitur yang memerlukan API.

## Menjalankan aplikasi

Dari folder `mobile_app`:

```bash
flutter pub get
flutter run
```

Secara default, aplikasi menghubungi backend di `http://10.0.2.2:8001`, alamat khusus Android Emulator untuk mengakses port `8001` pada komputer host.

### Menggunakan backend pada perangkat fisik

Pastikan komputer dan ponsel berada di jaringan yang sama, backend mendengarkan koneksi jaringan, dan firewall mengizinkan port backend. Jalankan aplikasi dengan alamat IP komputer yang dapat dijangkau ponsel:

```bash
flutter run --dart-define=BACKEND_URL=http://192.168.1.23:8001
```

Ganti `192.168.1.23` dengan alamat IP komputer backend. Untuk emulator atau backend pada host lain, sesuaikan URL-nya. Jangan memasukkan token provider atau rahasia ke dalam repository atau `--dart-define` yang akan dipublikasikan.

## Pengujian dan pemeriksaan

Jalankan dari folder `mobile_app`:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

Perintah tersebut memeriksa kode, menjalankan pengujian Flutter, dan membangun APK debug. Keberhasilan build tidak berarti provider AI atau proses generasi video backend berhasil dijalankan.

## Struktur utama

```text
lib/
  main.dart                 Entry point aplikasi
  models/                   Model katalog fitur, request, dan job
  pages/                    Halaman aplikasi dan workflow
  services/                 Komunikasi API dan penyimpanan lokal
  theme/                    Tema aplikasi
  widgets/                  Widget bersama
 test/                      Pengujian Flutter
```

## Konfigurasi dan keamanan

- `BACKEND_URL` dapat diatur melalui `--dart-define` saat menjalankan atau membangun aplikasi.
- Backend harus dapat dijangkau dari lingkungan tempat aplikasi berjalan; `localhost` pada ponsel menunjuk ke ponsel itu sendiri, bukan komputer backend.
- Jangan commit API key, token provider, kredensial, file `.env`, atau data pribadi.
- Source backend OpenMontage dikelola terpisah dari repository Flutter ini; jalankan dan konfigurasi backend sesuai dokumentasi backend-nya.

## Lisensi

Periksa lisensi OpenMontage dan seluruh dependency sebelum mendistribusikan aplikasi atau source code. README ini tidak menyatakan lisensi tambahan untuk source upstream.
