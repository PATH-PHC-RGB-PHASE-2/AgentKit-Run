# AgentKit-Run — KaderKita

Skrip untuk memasang dan memelihara berkas agent lokal proyek **Backend**, **CMS**, dan **Mobile** KaderKita (`CLAUDE.md`, `AGENTS.md`, `kilo.jsonc`, `.agents/`, `.claude/`, `.codex/`, `.kilo/`, `docs/`, `.docker/`) tanpa melewati Git repo proyek.

Repo ini **publik** dan hanya berisi skrip. Datanya (konfigurasi per proyek dan rangkaian patch) ada di repo **privat** [`AgentKit`](https://github.com/PATH-PHC-RGB-PHASE-2/AgentKit). Skrip mengunduh data itu memakai token GitHub milik Anda, jadi hanya anggota yang punya akses ke repo AgentKit yang bisa memasang kit.

```
RGB/
├── AgentKit-Run/          ← repo ini (publik): agent_kit.sh, agent_kit.ps1
├── AgentKit/              ← repo data (privat): projects/<PROJECT>.conf, .agent-kit/dist/<PROJECT>/
├── Backend/   CMS/   Mobile/
```

## Akses ke data (repo privat)

`raw.githubusercontent.com` menjawab **404 Not Found** untuk berkas repo privat bila permintaan datang tanpa token, walaupun halaman `github.com/.../blob/...` terbuka di browser. Skrip mencari token sendiri secara berurutan, tanpa prompt, dan tidak pernah mencetaknya:

1. `AGENTKIT_TOKEN` / `GITHUB_TOKEN` / `GH_TOKEN`
2. `gh auth token` (GitHub CLI, setelah `gh auth login`)
3. kredensial github.com yang tersimpan di git (Keychain macOS, Git Credential Manager)

Bila belum punya salah satunya, jalankan `gh auth login` sekali, atau buat PAT *fine-grained* dengan izin **Contents: Read-only** untuk repo AgentKit lalu simpan di `AGENTKIT_TOKEN`. Token otomatis hanya dikirim ke `raw.githubusercontent.com`/`api.github.com`. `status` menampilkan sumber token yang dipakai.

## Perintah

macOS, Linux, WSL2, Git Bash (jalankan dari folder `RGB/` atau dari dalam folder proyek):

```bash
curl -fsSL https://raw.githubusercontent.com/PATH-PHC-RGB-PHASE-2/AgentKit-Run/refs/heads/main/agent_kit.sh | bash -s -- <PROJECT> <COMMAND> [opsi]
```

PowerShell (Windows PowerShell 5.1 / PowerShell 7; membutuhkan Git for Windows atau WSL2):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/PATH-PHC-RGB-PHASE-2/AgentKit-Run/refs/heads/main/agent_kit.ps1))) <PROJECT> <COMMAND> [opsi]
```

> `iwr ... | iex -ArgumentList ...` **tidak** bisa dipakai: `Invoke-Expression` tidak menerima argumen. Bentuk `& ([scriptblock]::Create(...)) <args>` meneruskan argumen dan tidak menutup sesi PowerShell.

Dengan kedua repo sudah di-clone di `RGB/`, skrip bisa dijalankan tanpa unduhan sama sekali:

```bash
bash AgentKit-Run/agent_kit.sh <PROJECT> <COMMAND> --local     # data dibaca dari RGB/AgentKit
```

| COMMAND | Fungsi |
|---|---|
| `build` | (pemelihara) Membandingkan isi proyek dengan versi terakhir di `AgentKit/.agent-kit/dist/<PROJECT>/`; bila ada perubahan, membuat `vNNNN.patch` berikutnya, manifest, dan entri CHANGELOG. Skill baru, perubahan `CLAUDE.md`/`AGENTS.md`, dokumen baru, maupun berkas yang dihapus otomatis tertangkap. Selalu membaca dan menulis folder `AgentKit` lokal. |
| `apply` | Menerapkan patch dari versi terpasang (atau `v0001` untuk repo baru) sampai versi terbaru secara berurutan, lalu memasang symlink skill, hook git, blok exclude, seed, dan verifikasi. |
| `verify` | Memeriksa berkas terhadap manifest versi terpasang, hook git, blok exclude, `git status`, dan skill. |
| `status` | Versi terpasang, versi terbaru, sumber token, dan catatan versi yang belum diterapkan. |
| `help` | Bantuan. |

| Opsi | Fungsi |
|---|---|
| `--dry-run` | `apply` tanpa mengubah berkas (simulasi rantai patch di folder sementara) |
| `--overwrite` | `apply`: samakan berkas dengan versi terbaru walaupun ada perubahan lokal; berkas lama dicadangkan di `<git-dir>/agent-kit/backups/<waktu>/` |
| `--note "teks"` | `build`: catatan versi untuk CHANGELOG |
| `--target DIR` | folder repo proyek bila namanya tidak sama dengan PROJECT |
| `--root DIR` / `--agentkit DIR` | lokasi folder induk / folder data AgentKit lokal (default `<root>/AgentKit`) |
| `--local` | `apply`/`verify`/`status` membaca data dari AgentKit lokal, bukan unduhan |
| `--base-url URL` | sumber data lain (default: raw GitHub repo AgentKit, branch `master`) |

Variabel lingkungan: `AGENTKIT_TOKEN`, `AGENTKIT_BASE_URL` (sumber data), `AGENTKIT_RUN_URL` (sumber skrip untuk peluncur PowerShell), `AGENTKIT_ROOT`, `AGENTKIT_SOURCE=local`, `AGENTKIT_BASH` (lokasi bash di Windows).

## Alur pemelihara (build)

1. Ubah berkas agent di proyek (mis. tambah skill di `CMS/.agents/skills/`).
2. Dari folder `RGB/`: `bash AgentKit-Run/agent_kit.sh CMS build --note "tambah skill X"`.
3. Tinjau `AgentKit/.agent-kit/dist/CMS/vNNNN.patch` dan `CHANGELOG.md`, lalu commit dan push repo **AgentKit**. Skrip tidak pernah commit atau push.

Sebelum menulis, rantai `v0001..vBARU` diuji ulang dari nol dan harus menghasilkan isi yang identik. Build menolak bila ditemukan pola rahasia (private key, token GitLab, AWS key, kunci AES, token Mapbox, `storePassword`). Jalankan build di macOS/Linux/WSL2 agar bit eksekusi skrip terjaga.

Perubahan skrip di-commit ke repo ini (AgentKit-Run); perubahan data ke repo AgentKit.

## Alur pengguna (apply)

```bash
cd RGB            # berisi CMS/ (clone dari GitLab)
curl -fsSL https://raw.githubusercontent.com/PATH-PHC-RGB-PHASE-2/AgentKit-Run/refs/heads/main/agent_kit.sh | bash -s -- CMS apply
```

- Patch diterapkan di folder sementara lalu disalin ke proyek. Bila satu versi tidak bisa diterapkan (berkas diubah lokal atau sudah ada sebelum pemasangan pertama), **tidak ada berkas yang diubah untuk versi itu** dan status tetap di versi sebelumnya.
- Perubahan di `.git/` proyek hanya: `hooks/pre-commit`, `hooks/pre-push`, blok `# BEGIN agent-kit` di `info/exclude`, dan `<git-dir>/agent-kit/` (status + cadangan; per worktree). Tidak ada commit, push, atau fetch.

## Kebutuhan

`git` (mesin diff/patch), `curl`, `bash` 3.2+, `awk`, `find`, `sha256sum` atau `shasum`; opsional `gh` (GitHub CLI) untuk token. Windows: Git for Windows (menyertakan Git Bash) atau WSL2.
