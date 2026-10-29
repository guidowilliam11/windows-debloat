# 🧹 Claude Debloat

Plugin [Claude Code](https://claude.com/claude-code) untuk bikin Windows kamu **lega, ringan dan sehat**, dengan aman dan terukur.

## Install (2 perintah)

**Cara A: dari terminal biasa** (PowerShell/CMD; ini jalan juga untuk pengguna aplikasi desktop Claude):

```
claude plugin marketplace add guidowilliam11/claude-glowup
claude plugin install windows-glowup@claude-glowup
```

**Cara B: dari dalam sesi `claude` di terminal:**

```
/plugin marketplace add guidowilliam11/claude-glowup
/plugin install windows-debloat@claude-glowup
```

**Cara C: dari aplikasi desktop Claude (tab Code):** ketik di chat:

```
Install plugin windows-glowup dari marketplace guidowilliam11/claude-glowup
```

Claude akan menjalankan Cara A untukmu. Setelah selesai, buka **sesi baru** dan ketik `/windows-glowup`.

> `/plugin` tidak tersedia di kotak chat aplikasi desktop. Pakai Cara A atau C.

Lalu jalankan:

```
/windows-debloat bersihkan dan percepat laptop saya
```

> Disarankan pakai model **Opus 5.5**. Update ke versi terbaru: `/plugin marketplace update claude-glowup`.

## Apa yang dilakukan

1. **Debloat Windows.** Pakai [Win11Debloat](https://github.com/Raphire/Win11Debloat): hapus bloatware, matikan telemetri, iklan, Copilot, Recall dan pencarian Bing di Start. Ada level **Lite** (tanpa hapus app), **Defaults** atau **Custom**. Skrip diunduh, hash-nya ditampilkan, restore point dibuat dulu, dan hasilnya dicek jujur (tidak percaya "completed" begitu saja).
2. **Survei paralel.** 5 agent jalan bersamaan, semua read-only dengan angka nyata:
   - **Disk:** termasuk scan cepat file berat (±1,8 juta file dalam ±2 menit) yang dikelompokkan per kategori.
   - **Proyek dev:** node_modules, .next, target dan sejenisnya, termasuk di dalam worktree.
   - **RAM & Startup.**
   - **Kesehatan & Kecepatan:** apakah disk, RAM dan CPU jalan sesuai kelasnya.
   - **IDE & Ekstensi:** editor dobel, ekstensi berat, versi lama yang tertinggal, dan ekstensi yang terpasang di beberapa editor.
3. **Laporan tiga kategori.** ✅ aman dihapus · ⚠️ kamu yang putuskan · ⛔ jangan disentuh (dengan alasannya). Tidak ada yang dihapus sebelum kamu memilih.
4. **Eksekusi aman.**
   - Cache dan artefak build (`node_modules`, `.next`, Rust `target`, Temp, cache browser) dihapus dengan cara yang tidak ikut menelusuri junction.
   - Perubahan sistem (service → Manual, startup off, uninstall, DISM/SFC, chkdsk) dibuatkan **skrip yang kamu jalankan sendiri sebagai Administrator**, lengkap dengan `undo.ps1`.
   - Update driver dan aplikasi lewat winget dengan daftar terkurasi (patch keamanan dulu, versi mayor database dan IDE tidak disentuh).
5. **Laporan sebelum → sesudah**, diukur ulang secara live.

## Hasil nyata (laptop pertama)

| | Sebelum | Sesudah |
|---|---|---|
| Ruang kosong C: | 25,8 GB | ~150 GB |
| RAM kosong saat idle | 3,2 GB | 8,2 GB |
| Disk C: | perlu perbaikan | healthy |
| Aplikasi usang | 74 | 37 diupdate |

## Tanpa plugin?

Copy isi [`PROMPT.md`](PROMPT.md) dan paste ke Claude Code.

## Keamanan

- Plugin ini tidak menyimpan dan tidak mengirim data ke mana pun. Semua skrip PowerShell bisa dibaca di [`plugins/windows-debloat/skills/windows-debloat/scripts`](plugins/windows-debloat/skills/windows-debloat/scripts).
- Baca dulu setiap skrip yang diminta untuk dijalankan sebagai Administrator.
- Dipakai dengan risiko sendiri. Backup data penting sebelum menghapus atau meng-uninstall apa pun.

## Lisensi

MIT
