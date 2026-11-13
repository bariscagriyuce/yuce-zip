<p align="center"><img src="docs/icon.png" width="128" alt="YUCE ZIP"></p>

<h1 align="center">YUCE ZIP</h1>

<p align="center">
  macOS için ücretsiz, açık kaynaklı, grafik arayüzlü arşiv yöneticisi — <b>7-Zip</b> motoruyla.<br>
  Free, open-source archive manager with a graphical interface for macOS — powered by <b>7-Zip</b>.<br>
  Gerenciador de arquivos compactados gratuito e de código aberto para macOS — com o mecanismo <b>7-Zip</b>.
</p>

<p align="center">
  <a href="https://github.com/bariscagriyuce/yuce-zip/releases/latest"><b>⬇︎ İndir / Download / Baixar (.dmg)</b></a>
</p>

---

## 🇹🇷 Türkçe

**Özellikler**
- 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB ve daha birçok biçimi açar
- 7z, ZIP, TAR, TAR.GZ, TAR.BZ2, TAR.XZ ve WIM arşivleri oluşturur
- Arşiv içinde klasörler arasında gezinme, dosyayı çift tıklayarak açma
- Tümünü ya da yalnızca seçili öğeleri çıkartma, “Buraya Çıkart”
- AES-256 şifreleme (7z ve ZIP), 7z'de dosya adlarını da şifreleme
- Parçalara bölme (CD, DVD, FAT32 vb.), sıkıştırma düzeyi seçimi
- Arşivi sınama, arşive dosya ekleme ve arşivden silme (7z, ZIP, TAR, WIM)
- Sürükle-bırak: arşiv bırakırsanız açar, dosya bırakırsanız sıkıştırır
- Finder'da “Birlikte Aç” menüsünde görünür
- **Türkçe, English, Português (Brasil)** — uygulama içinden anında değiştirilebilir
- **Güncelleme denetimi:** GitHub Releases üzerinden yeni sürümü kontrol eder

**Kurulum**
1. [Releases](https://github.com/bariscagriyuce/yuce-zip/releases/latest) sayfasından `YUCE-ZIP-x.y.z.dmg` dosyasını indirin.
2. DMG'yi açın, **YUCE ZIP**'i **Applications** klasörüne sürükleyin.
3. Uygulama Apple tarafından noter onaylı olmadığı için ilk açılışta: uygulamaya **sağ tıklayın → Aç** deyin
   (veya *Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç*). Gerekirse Terminal'de:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/YUCE ZIP.app"
   ```

Gereksinimler: macOS 13 Ventura veya üzeri, Apple Silicon (M1/M2/M3/M4…).

## 🇬🇧 English

**Features**
- Opens 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB and many more
- Creates 7z, ZIP, TAR, TAR.GZ, TAR.BZ2, TAR.XZ and WIM archives
- Browse folders inside archives, double-click to open a file
- Extract everything or only the selected items, “Extract Here”
- AES-256 encryption (7z and ZIP), file-name encryption for 7z
- Split into volumes, selectable compression level
- Test archives, add files to and delete files from archives (7z, ZIP, TAR, WIM)
- Drag & drop: drop an archive to open it, drop files to compress them
- Appears in Finder's “Open With” menu
- **Türkçe, English, Português (Brasil)** — switchable instantly inside the app
- **Update checker:** looks for new versions on GitHub Releases

**Install:** download the DMG from [Releases](https://github.com/bariscagriyuce/yuce-zip/releases/latest), drag **YUCE ZIP** to **Applications**.
The app is not notarized, so the first time **right-click → Open** it (or run the `xattr` command above).

Requirements: macOS 13 Ventura or later, Apple Silicon.

## 🇧🇷 Português (Brasil)

**Recursos**
- Abre 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB e muito mais
- Cria arquivos 7z, ZIP, TAR, TAR.GZ, TAR.BZ2, TAR.XZ e WIM
- Navegue pelas pastas dentro do arquivo, clique duas vezes para abrir um item
- Extraia tudo ou apenas os itens selecionados, “Extrair Aqui”
- Criptografia AES-256 (7z e ZIP), criptografia de nomes no 7z
- Divisão em volumes, nível de compressão ajustável
- Testar, adicionar e excluir itens (7z, ZIP, TAR, WIM)
- Arrastar e soltar; aparece no menu “Abrir com” do Finder
- **Türkçe, English, Português (Brasil)** — troca instantânea dentro do app
- **Verificação de atualizações** pelo GitHub Releases

**Instalação:** baixe o DMG em [Releases](https://github.com/bariscagriyuce/yuce-zip/releases/latest) e arraste o **YUCE ZIP** para **Aplicativos**.
Como o app não é notarizado, na primeira vez clique com o **botão direito → Abrir**.

---

## 🛠 Derleme / Build

```bash
brew install sevenzip      # 7zz motoru / engine
./scripts/build.sh         # -> build/YUCE ZIP.app + dist/YUCE-ZIP-<version>.dmg
```

Sürüm numarası `VERSION` dosyasındadır. Yeni sürüm yayımlamak için / To publish a new version:

```bash
echo 1.0.1 > VERSION && ./scripts/build.sh
gh release create v1.0.1 dist/YUCE-ZIP-1.0.1.dmg --title "YUCE ZIP 1.0.1" --notes "..."
```

Uygulama `https://api.github.com/repos/bariscagriyuce/yuce-zip/releases/latest` adresini kontrol eder; etiket (`v1.0.1`) mevcut sürümden yüksekse kullanıcıya indirme önerir.

## Proje yapısı / Project layout

| Dosya | Açıklama |
|---|---|
| `Sources/YuceZip/AppDelegate.swift` | Uygulama, menüler, pencereler |
| `Sources/YuceZip/BrowserView.swift` | Ana pencere: araç çubuğu, dosya tablosu, sürükle-bırak |
| `Sources/YuceZip/Sheets.swift` | Çıkartma, sıkıştırma ve özellikler pencereleri |
| `Sources/YuceZip/ArchiveModel.swift` | Arşiv modeli ve işlemler |
| `Sources/YuceZip/SevenZip.swift` | `7zz` süreç sarmalayıcısı ve çıktı ayrıştırıcı |
| `Sources/YuceZip/UpdateChecker.swift` | GitHub güncelleme denetimi |
| `Sources/YuceZip/Localization.swift` | TR / EN / PT-BR çeviriler |
| `scripts/build.sh` | .app paketleme, ikon, imzalama, DMG |

## Lisans / License

YUCE ZIP: MIT. Gömülü 7-Zip motoru (`7zz`) © Igor Pavlov, GNU LGPL + unRAR kısıtlaması — bkz. [`Resources/7-Zip-License.txt`](Resources/7-Zip-License.txt).
