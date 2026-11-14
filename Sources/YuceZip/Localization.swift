import Foundation
import Combine

/// Supported UI languages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case turkish = "tr"
    case portugueseBR = "pt-BR"

    var id: String { rawValue }

    /// Name of the language written in that language (shown in the picker).
    var nativeName: String {
        switch self {
        case .system: return L("lang.system")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .portugueseBR: return "Português (Brasil)"
        }
    }
}

/// Very small runtime localisation engine. Allows switching the language
/// inside the app without restarting it.
final class L10n: ObservableObject {
    static let shared = L10n()

    private static let defaultsKey = "appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: stored) ?? .system
    }

    /// The concrete language code being used ("en", "tr" or "pt-BR").
    var effectiveCode: String {
        if language != .system { return language.rawValue }
        for pref in Locale.preferredLanguages {
            let p = pref.lowercased()
            if p.hasPrefix("tr") { return "tr" }
            if p.hasPrefix("pt") { return "pt-BR" }
            if p.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    var locale: Locale {
        switch effectiveCode {
        case "tr": return Locale(identifier: "tr_TR")
        case "pt-BR": return Locale(identifier: "pt_BR")
        default: return Locale(identifier: "en_US")
        }
    }

    func string(_ key: String) -> String {
        let code = effectiveCode
        if let table = Strings.tables[code], let value = table[key] { return value }
        if let value = Strings.tables["en"]?[key] { return value }
        return key
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("YuceZipLanguageChanged")
}

/// Shorthand for a localised string.
func L(_ key: String) -> String { L10n.shared.string(key) }

/// Shorthand for a localised format string.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.shared.string(key), locale: L10n.shared.locale, arguments: args)
}

// MARK: - String tables

enum Strings {
    static let tables: [String: [String: String]] = [
        "en": en,
        "tr": tr,
        "pt-BR": ptBR,
    ]

    // MARK: English
    static let en: [String: String] = [
        "lang.system": "System Default",

        "menu.about": "About YUCE ZIP",
        "menu.checkUpdates": "Check for Updates…",
        "menu.settings": "Settings…",
        "menu.services": "Services",
        "menu.hide": "Hide YUCE ZIP",
        "menu.hideOthers": "Hide Others",
        "menu.showAll": "Show All",
        "menu.quit": "Quit YUCE ZIP",
        "menu.file": "File",
        "menu.newWindow": "New Window",
        "menu.open": "Open Archive…",
        "menu.compress": "Compress Files…",
        "menu.extract": "Extract…",
        "menu.extractHere": "Extract Here",
        "menu.test": "Test Archive",
        "menu.properties": "Archive Properties",
        "menu.close": "Close Window",
        "menu.edit": "Edit",
        "menu.undo": "Undo",
        "menu.redo": "Redo",
        "menu.cut": "Cut",
        "menu.copy": "Copy",
        "menu.paste": "Paste",
        "menu.selectAll": "Select All",
        "menu.window": "Window",
        "menu.minimize": "Minimize",
        "menu.zoom": "Zoom",
        "menu.front": "Bring All to Front",
        "menu.help": "Help",
        "menu.github": "YUCE ZIP on GitHub",

        "welcome.title": "Drop files here",
        "welcome.subtitle": "Drop an archive to open it, or any files and folders to compress them.",
        "welcome.open": "Open Archive…",
        "welcome.compress": "Compress Files…",
        "welcome.formats": "Opens 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB and more",

        "toolbar.up": "Up",
        "toolbar.add": "Add",
        "toolbar.extract": "Extract",
        "toolbar.test": "Test",
        "toolbar.delete": "Delete",
        "toolbar.info": "Info",
        "toolbar.close": "Close Archive",

        "col.name": "Name",
        "col.size": "Size",
        "col.packed": "Packed Size",
        "col.modified": "Modified",
        "col.method": "Method",

        "status.items": "%d items",
        "status.selected": "%d of %d selected",
        "status.summary": "%@ · %d files · %d folders · %@",
        "status.readOnly": "Read-only format",
        "status.encrypted": "Encrypted",

        "context.open": "Open",
        "context.extract": "Extract Selected…",
        "context.delete": "Delete from Archive",

        "common.cancel": "Cancel",
        "common.ok": "OK",
        "common.close": "Close",
        "common.yes": "Yes",
        "common.no": "No",
        "common.choose": "Choose…",
        "common.showInFinder": "Show in Finder",

        "extract.title": "Extract Files",
        "extract.archive": "Archive:",
        "extract.destination": "Extract to:",
        "extract.newFolder": "Create a folder named after the archive",
        "extract.overwrite": "Existing files:",
        "ow.overwrite": "Overwrite",
        "ow.skip": "Skip",
        "ow.rename": "Rename extracted files",
        "ow.renameExisting": "Rename existing files",
        "extract.selectedOnly": "Extract only the selected items (%d)",
        "extract.password": "Password:",
        "extract.openAfter": "Show files in Finder when done",
        "extract.start": "Extract",

        "compress.title": "Add to Archive",
        "compress.files": "Items to compress: %d",
        "compress.name": "Archive name:",
        "compress.location": "Save in:",
        "compress.format": "Format:",
        "compress.level": "Compression level:",
        "level.0": "Store (no compression)",
        "level.1": "Fastest",
        "level.3": "Fast",
        "level.5": "Normal",
        "level.7": "Maximum",
        "level.9": "Ultra",
        "compress.split": "Split into volumes:",
        "split.none": "Don't split",
        "compress.encryption": "Encryption",
        "compress.password": "Password:",
        "compress.confirm": "Confirm password:",
        "compress.encryptNames": "Encrypt file names",
        "compress.excludeMac": "Exclude macOS system files (.DS_Store, ._*)",
        "compress.noEncryption": "This format does not support encryption.",
        "compress.mismatch": "Passwords do not match.",
        "compress.start": "Compress",
        "compress.exists": "A file named “%@” already exists. It will be updated.",

        "add.title": "Add files to archive?",
        "add.message": "Add %d item(s) to “%@”?",
        "add.button": "Add",

        "progress.compressing": "Compressing…",
        "progress.extracting": "Extracting…",
        "progress.testing": "Testing archive…",
        "progress.deleting": "Deleting…",
        "progress.adding": "Adding files…",
        "progress.opening": "Opening archive…",
        "progress.preparing": "Preparing…",

        "pw.title": "Password Required",
        "pw.message": "“%@” is protected by a password.",
        "pw.wrong": "The password is incorrect. Please try again.",
        "pw.placeholder": "Password",
        "pw.show": "Show password",

        "result.title.ok": "Done",
        "result.title.warning": "Completed with warnings",
        "result.title.error": "Operation failed",
        "result.extracted": "Files were extracted to:\n%@",
        "result.created": "Archive created:\n%@",
        "result.testOK": "No errors found. The archive is OK.",
        "result.deleted": "The selected items were deleted.",
        "result.added": "The files were added to the archive.",
        "result.cancelled": "The operation was cancelled.",
        "result.details": "Details",

        "error.open": "Could not open “%@”",
        "error.notArchive": "The file is not a supported archive or it is damaged.",
        "error.engine": "The 7-Zip engine could not be found inside the application.",

        "delete.title": "Delete selected items?",
        "delete.message": "%d item(s) will be permanently removed from the archive. This cannot be undone.",
        "delete.button": "Delete",

        "info.title": "Archive Properties",
        "info.path": "Location",
        "info.type": "Type",
        "info.physSize": "Archive size",
        "info.unpacked": "Unpacked size",
        "info.files": "Files",
        "info.folders": "Folders",
        "info.ratio": "Compression ratio",
        "info.method": "Method",
        "info.solid": "Solid",
        "info.encrypted": "Encrypted",

        "settings.title": "Settings",
        "settings.general": "General",
        "settings.language": "Language:",
        "settings.defaults": "Defaults for new archives",
        "settings.defaultFormat": "Format:",
        "settings.defaultLevel": "Compression level:",
        "settings.afterExtract": "Show extracted files in Finder",
        "settings.updates": "Updates",
        "settings.autoCheck": "Check for updates automatically at launch",
        "settings.checkNow": "Check Now",
        "settings.lastCheck": "Last check: %@",
        "settings.never": "Never",

        "update.checking": "Checking for updates…",
        "update.available.title": "A new version of YUCE ZIP is available!",
        "update.available.message": "YUCE ZIP %@ is available — you have %@. Would you like to download it now?",
        "update.download": "Download",
        "update.later": "Later",
        "update.uptodate.title": "You're up to date!",
        "update.uptodate.message": "YUCE ZIP %@ is the newest version available.",
        "update.failed.title": "Could not check for updates",
        "update.failed.message": "Please check your internet connection and try again.\n\n%@",
        "update.notes": "What's new:",

        "about.version": "Version %@",
        "about.description": "Free and open-source file archiver for macOS, powered by the 7-Zip engine.",
        "about.engine": "Compression engine: 7-Zip %@ © Igor Pavlov (GNU LGPL)",
        "about.github": "GitHub",

        "settings.integration": "System Integration",
        "settings.makeDefault": "Make YUCE ZIP the Default App for Archives",
        "settings.isDefault": "YUCE ZIP opens ZIP files by default.",
        "settings.notDefault": "Another app currently opens ZIP files by default.",
        "settings.defaultDone": "YUCE ZIP is now the default app for %d archive types.",
        "settings.defaultFailed": "Some file types could not be changed (%d).",
        "settings.finderMenu": "Show YUCE ZIP in Finder's right-click menu",
        "settings.finderSettings": "Extension Settings…",
        "settings.finderHint": "If the menu doesn't appear, enable “YUCE ZIP” under System Settings → General → Login Items & Extensions → Finder.",
        "finder.open": "Open with YUCE ZIP",
        "finder.extract": "Extract Files…",
        "finder.extractHere": "Extract Here",
        "finder.extractTo": "Extract to “%@/”",
        "finder.test": "Test Archive",
        "finder.addTo": "Add to Archive…",
        "finder.compressTo": "Compress to “%@”",
        "qa.confirmTitle": "Run YUCE ZIP action?",
        "qa.confirmMessage": "Another application asked YUCE ZIP to run “%@” on:\n\n%@",
        "qa.run": "Run",
    ]

    // MARK: Turkish
    static let tr: [String: String] = [
        "lang.system": "Sistem Varsayılanı",

        "menu.about": "YUCE ZIP Hakkında",
        "menu.checkUpdates": "Güncellemeleri Denetle…",
        "menu.settings": "Ayarlar…",
        "menu.services": "Servisler",
        "menu.hide": "YUCE ZIP'i Gizle",
        "menu.hideOthers": "Diğerlerini Gizle",
        "menu.showAll": "Tümünü Göster",
        "menu.quit": "YUCE ZIP'ten Çık",
        "menu.file": "Dosya",
        "menu.newWindow": "Yeni Pencere",
        "menu.open": "Arşiv Aç…",
        "menu.compress": "Dosyaları Sıkıştır…",
        "menu.extract": "Çıkart…",
        "menu.extractHere": "Buraya Çıkart",
        "menu.test": "Arşivi Sına",
        "menu.properties": "Arşiv Özellikleri",
        "menu.close": "Pencereyi Kapat",
        "menu.edit": "Düzen",
        "menu.undo": "Geri Al",
        "menu.redo": "Yinele",
        "menu.cut": "Kes",
        "menu.copy": "Kopyala",
        "menu.paste": "Yapıştır",
        "menu.selectAll": "Tümünü Seç",
        "menu.window": "Pencere",
        "menu.minimize": "Küçült",
        "menu.zoom": "Yakınlaştır",
        "menu.front": "Tümünü Öne Getir",
        "menu.help": "Yardım",
        "menu.github": "GitHub'da YUCE ZIP",

        "welcome.title": "Dosyaları buraya bırakın",
        "welcome.subtitle": "Açmak için bir arşiv, sıkıştırmak için herhangi bir dosya veya klasör bırakın.",
        "welcome.open": "Arşiv Aç…",
        "welcome.compress": "Dosyaları Sıkıştır…",
        "welcome.formats": "7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB ve daha fazlasını açar",

        "toolbar.up": "Yukarı",
        "toolbar.add": "Ekle",
        "toolbar.extract": "Çıkart",
        "toolbar.test": "Sına",
        "toolbar.delete": "Sil",
        "toolbar.info": "Bilgi",
        "toolbar.close": "Arşivi Kapat",

        "col.name": "Ad",
        "col.size": "Boyut",
        "col.packed": "Sıkıştırılmış",
        "col.modified": "Değiştirilme",
        "col.method": "Yöntem",

        "status.items": "%d öğe",
        "status.selected": "%d / %d seçili",
        "status.summary": "%@ · %d dosya · %d klasör · %@",
        "status.readOnly": "Salt okunur biçim",
        "status.encrypted": "Şifreli",

        "context.open": "Aç",
        "context.extract": "Seçilenleri Çıkart…",
        "context.delete": "Arşivden Sil",

        "common.cancel": "Vazgeç",
        "common.ok": "Tamam",
        "common.close": "Kapat",
        "common.yes": "Evet",
        "common.no": "Hayır",
        "common.choose": "Seç…",
        "common.showInFinder": "Finder'da Göster",

        "extract.title": "Dosyaları Çıkart",
        "extract.archive": "Arşiv:",
        "extract.destination": "Çıkartılacak yer:",
        "extract.newFolder": "Arşiv adıyla bir klasör oluştur",
        "extract.overwrite": "Var olan dosyalar:",
        "ow.overwrite": "Üzerine yaz",
        "ow.skip": "Atla",
        "ow.rename": "Çıkartılanları yeniden adlandır",
        "ow.renameExisting": "Var olanları yeniden adlandır",
        "extract.selectedOnly": "Yalnızca seçili öğeleri çıkart (%d)",
        "extract.password": "Parola:",
        "extract.openAfter": "Bitince dosyaları Finder'da göster",
        "extract.start": "Çıkart",

        "compress.title": "Arşive Ekle",
        "compress.files": "Sıkıştırılacak öğe: %d",
        "compress.name": "Arşiv adı:",
        "compress.location": "Kaydedilecek yer:",
        "compress.format": "Biçim:",
        "compress.level": "Sıkıştırma düzeyi:",
        "level.0": "Depola (sıkıştırma yok)",
        "level.1": "En hızlı",
        "level.3": "Hızlı",
        "level.5": "Normal",
        "level.7": "Yüksek",
        "level.9": "Ultra",
        "compress.split": "Parçalara böl:",
        "split.none": "Bölme",
        "compress.encryption": "Şifreleme",
        "compress.password": "Parola:",
        "compress.confirm": "Parola (tekrar):",
        "compress.encryptNames": "Dosya adlarını da şifrele",
        "compress.excludeMac": "macOS sistem dosyalarını hariç tut (.DS_Store, ._*)",
        "compress.noEncryption": "Bu biçim şifrelemeyi desteklemiyor.",
        "compress.mismatch": "Parolalar eşleşmiyor.",
        "compress.start": "Sıkıştır",
        "compress.exists": "“%@” adlı bir dosya zaten var. Güncellenecek.",

        "add.title": "Dosyalar arşive eklensin mi?",
        "add.message": "%d öğe “%@” arşivine eklensin mi?",
        "add.button": "Ekle",

        "progress.compressing": "Sıkıştırılıyor…",
        "progress.extracting": "Çıkartılıyor…",
        "progress.testing": "Arşiv sınanıyor…",
        "progress.deleting": "Siliniyor…",
        "progress.adding": "Dosyalar ekleniyor…",
        "progress.opening": "Arşiv açılıyor…",
        "progress.preparing": "Hazırlanıyor…",

        "pw.title": "Parola Gerekli",
        "pw.message": "“%@” parola ile korunuyor.",
        "pw.wrong": "Parola yanlış. Lütfen tekrar deneyin.",
        "pw.placeholder": "Parola",
        "pw.show": "Parolayı göster",

        "result.title.ok": "Tamamlandı",
        "result.title.warning": "Uyarılarla tamamlandı",
        "result.title.error": "İşlem başarısız oldu",
        "result.extracted": "Dosyalar şuraya çıkartıldı:\n%@",
        "result.created": "Arşiv oluşturuldu:\n%@",
        "result.testOK": "Hata bulunamadı. Arşiv sağlam.",
        "result.deleted": "Seçili öğeler silindi.",
        "result.added": "Dosyalar arşive eklendi.",
        "result.cancelled": "İşlem iptal edildi.",
        "result.details": "Ayrıntılar",

        "error.open": "“%@” açılamadı",
        "error.notArchive": "Dosya desteklenen bir arşiv değil ya da hasarlı.",
        "error.engine": "7-Zip motoru uygulamanın içinde bulunamadı.",

        "delete.title": "Seçili öğeler silinsin mi?",
        "delete.message": "%d öğe arşivden kalıcı olarak silinecek. Bu işlem geri alınamaz.",
        "delete.button": "Sil",

        "info.title": "Arşiv Özellikleri",
        "info.path": "Konum",
        "info.type": "Tür",
        "info.physSize": "Arşiv boyutu",
        "info.unpacked": "Açılmış boyut",
        "info.files": "Dosyalar",
        "info.folders": "Klasörler",
        "info.ratio": "Sıkıştırma oranı",
        "info.method": "Yöntem",
        "info.solid": "Katı (solid)",
        "info.encrypted": "Şifreli",

        "settings.title": "Ayarlar",
        "settings.general": "Genel",
        "settings.language": "Dil:",
        "settings.defaults": "Yeni arşivler için varsayılanlar",
        "settings.defaultFormat": "Biçim:",
        "settings.defaultLevel": "Sıkıştırma düzeyi:",
        "settings.afterExtract": "Çıkartılan dosyaları Finder'da göster",
        "settings.updates": "Güncellemeler",
        "settings.autoCheck": "Açılışta güncellemeleri otomatik denetle",
        "settings.checkNow": "Şimdi Denetle",
        "settings.lastCheck": "Son denetim: %@",
        "settings.never": "Hiç",

        "update.checking": "Güncellemeler denetleniyor…",
        "update.available.title": "YUCE ZIP'in yeni bir sürümü var!",
        "update.available.message": "YUCE ZIP %@ yayımlandı — sizdeki sürüm %@. Şimdi indirmek ister misiniz?",
        "update.download": "İndir",
        "update.later": "Daha Sonra",
        "update.uptodate.title": "Uygulamanız güncel!",
        "update.uptodate.message": "YUCE ZIP %@ mevcut en yeni sürüm.",
        "update.failed.title": "Güncellemeler denetlenemedi",
        "update.failed.message": "Lütfen internet bağlantınızı kontrol edip tekrar deneyin.\n\n%@",
        "update.notes": "Yenilikler:",

        "about.version": "Sürüm %@",
        "about.description": "7-Zip motorunu kullanan, macOS için ücretsiz ve açık kaynaklı arşiv yöneticisi.",
        "about.engine": "Sıkıştırma motoru: 7-Zip %@ © Igor Pavlov (GNU LGPL)",
        "about.github": "GitHub",

        "settings.integration": "Sistem Entegrasyonu",
        "settings.makeDefault": "YUCE ZIP'i Arşivler İçin Varsayılan Uygulama Yap",
        "settings.isDefault": "ZIP dosyaları varsayılan olarak YUCE ZIP ile açılıyor.",
        "settings.notDefault": "ZIP dosyaları şu anda başka bir uygulamayla açılıyor.",
        "settings.defaultDone": "YUCE ZIP artık %d arşiv türü için varsayılan uygulama.",
        "settings.defaultFailed": "Bazı dosya türleri değiştirilemedi (%d).",
        "settings.finderMenu": "YUCE ZIP'i Finder'ın sağ tık menüsünde göster",
        "settings.finderSettings": "Eklenti Ayarları…",
        "settings.finderHint": "Menü görünmüyorsa Sistem Ayarları → Genel → Giriş Öğeleri ve Uzantılar → Finder altında “YUCE ZIP”i açın.",
        "finder.open": "YUCE ZIP ile Aç",
        "finder.extract": "Dosyaları Çıkart…",
        "finder.extractHere": "Buraya Çıkart",
        "finder.extractTo": "“%@/” klasörüne çıkart",
        "finder.test": "Arşivi Sına",
        "finder.addTo": "Arşive Ekle…",
        "finder.compressTo": "“%@” olarak sıkıştır",
        "qa.confirmTitle": "YUCE ZIP işlemi çalıştırılsın mı?",
        "qa.confirmMessage": "Başka bir uygulama YUCE ZIP'ten “%@” işlemini şu öğeler için istedi:\n\n%@",
        "qa.run": "Çalıştır",
    ]

    // MARK: Brazilian Portuguese
    static let ptBR: [String: String] = [
        "lang.system": "Padrão do Sistema",

        "menu.about": "Sobre o YUCE ZIP",
        "menu.checkUpdates": "Verificar Atualizações…",
        "menu.settings": "Ajustes…",
        "menu.services": "Serviços",
        "menu.hide": "Ocultar YUCE ZIP",
        "menu.hideOthers": "Ocultar Outros",
        "menu.showAll": "Mostrar Tudo",
        "menu.quit": "Encerrar YUCE ZIP",
        "menu.file": "Arquivo",
        "menu.newWindow": "Nova Janela",
        "menu.open": "Abrir Arquivo Compactado…",
        "menu.compress": "Compactar Arquivos…",
        "menu.extract": "Extrair…",
        "menu.extractHere": "Extrair Aqui",
        "menu.test": "Testar Arquivo",
        "menu.properties": "Propriedades do Arquivo",
        "menu.close": "Fechar Janela",
        "menu.edit": "Editar",
        "menu.undo": "Desfazer",
        "menu.redo": "Refazer",
        "menu.cut": "Recortar",
        "menu.copy": "Copiar",
        "menu.paste": "Colar",
        "menu.selectAll": "Selecionar Tudo",
        "menu.window": "Janela",
        "menu.minimize": "Minimizar",
        "menu.zoom": "Zoom",
        "menu.front": "Trazer Tudo para a Frente",
        "menu.help": "Ajuda",
        "menu.github": "YUCE ZIP no GitHub",

        "welcome.title": "Solte os arquivos aqui",
        "welcome.subtitle": "Solte um arquivo compactado para abri-lo, ou quaisquer arquivos e pastas para compactá-los.",
        "welcome.open": "Abrir Arquivo Compactado…",
        "welcome.compress": "Compactar Arquivos…",
        "welcome.formats": "Abre 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB e muito mais",

        "toolbar.up": "Acima",
        "toolbar.add": "Adicionar",
        "toolbar.extract": "Extrair",
        "toolbar.test": "Testar",
        "toolbar.delete": "Excluir",
        "toolbar.info": "Info",
        "toolbar.close": "Fechar Arquivo",

        "col.name": "Nome",
        "col.size": "Tamanho",
        "col.packed": "Compactado",
        "col.modified": "Modificado",
        "col.method": "Método",

        "status.items": "%d itens",
        "status.selected": "%d de %d selecionados",
        "status.summary": "%@ · %d arquivos · %d pastas · %@",
        "status.readOnly": "Formato somente leitura",
        "status.encrypted": "Criptografado",

        "context.open": "Abrir",
        "context.extract": "Extrair Selecionados…",
        "context.delete": "Excluir do Arquivo",

        "common.cancel": "Cancelar",
        "common.ok": "OK",
        "common.close": "Fechar",
        "common.yes": "Sim",
        "common.no": "Não",
        "common.choose": "Escolher…",
        "common.showInFinder": "Mostrar no Finder",

        "extract.title": "Extrair Arquivos",
        "extract.archive": "Arquivo:",
        "extract.destination": "Extrair para:",
        "extract.newFolder": "Criar uma pasta com o nome do arquivo",
        "extract.overwrite": "Arquivos existentes:",
        "ow.overwrite": "Substituir",
        "ow.skip": "Ignorar",
        "ow.rename": "Renomear arquivos extraídos",
        "ow.renameExisting": "Renomear arquivos existentes",
        "extract.selectedOnly": "Extrair apenas os itens selecionados (%d)",
        "extract.password": "Senha:",
        "extract.openAfter": "Mostrar arquivos no Finder ao concluir",
        "extract.start": "Extrair",

        "compress.title": "Adicionar ao Arquivo",
        "compress.files": "Itens a compactar: %d",
        "compress.name": "Nome do arquivo:",
        "compress.location": "Salvar em:",
        "compress.format": "Formato:",
        "compress.level": "Nível de compressão:",
        "level.0": "Armazenar (sem compressão)",
        "level.1": "Mais rápido",
        "level.3": "Rápido",
        "level.5": "Normal",
        "level.7": "Máximo",
        "level.9": "Ultra",
        "compress.split": "Dividir em volumes:",
        "split.none": "Não dividir",
        "compress.encryption": "Criptografia",
        "compress.password": "Senha:",
        "compress.confirm": "Confirmar senha:",
        "compress.encryptNames": "Criptografar nomes de arquivos",
        "compress.excludeMac": "Excluir arquivos de sistema do macOS (.DS_Store, ._*)",
        "compress.noEncryption": "Este formato não suporta criptografia.",
        "compress.mismatch": "As senhas não coincidem.",
        "compress.start": "Compactar",
        "compress.exists": "Já existe um arquivo chamado “%@”. Ele será atualizado.",

        "add.title": "Adicionar arquivos ao arquivo compactado?",
        "add.message": "Adicionar %d item(ns) a “%@”?",
        "add.button": "Adicionar",

        "progress.compressing": "Compactando…",
        "progress.extracting": "Extraindo…",
        "progress.testing": "Testando arquivo…",
        "progress.deleting": "Excluindo…",
        "progress.adding": "Adicionando arquivos…",
        "progress.opening": "Abrindo arquivo…",
        "progress.preparing": "Preparando…",

        "pw.title": "Senha Necessária",
        "pw.message": "“%@” está protegido por senha.",
        "pw.wrong": "A senha está incorreta. Tente novamente.",
        "pw.placeholder": "Senha",
        "pw.show": "Mostrar senha",

        "result.title.ok": "Concluído",
        "result.title.warning": "Concluído com avisos",
        "result.title.error": "A operação falhou",
        "result.extracted": "Os arquivos foram extraídos para:\n%@",
        "result.created": "Arquivo criado:\n%@",
        "result.testOK": "Nenhum erro encontrado. O arquivo está OK.",
        "result.deleted": "Os itens selecionados foram excluídos.",
        "result.added": "Os arquivos foram adicionados.",
        "result.cancelled": "A operação foi cancelada.",
        "result.details": "Detalhes",

        "error.open": "Não foi possível abrir “%@”",
        "error.notArchive": "O arquivo não é um formato suportado ou está danificado.",
        "error.engine": "O mecanismo 7-Zip não foi encontrado dentro do aplicativo.",

        "delete.title": "Excluir os itens selecionados?",
        "delete.message": "%d item(ns) serão removidos permanentemente do arquivo. Isso não pode ser desfeito.",
        "delete.button": "Excluir",

        "info.title": "Propriedades do Arquivo",
        "info.path": "Local",
        "info.type": "Tipo",
        "info.physSize": "Tamanho do arquivo",
        "info.unpacked": "Tamanho descompactado",
        "info.files": "Arquivos",
        "info.folders": "Pastas",
        "info.ratio": "Taxa de compressão",
        "info.method": "Método",
        "info.solid": "Sólido",
        "info.encrypted": "Criptografado",

        "settings.title": "Ajustes",
        "settings.general": "Geral",
        "settings.language": "Idioma:",
        "settings.defaults": "Padrões para novos arquivos",
        "settings.defaultFormat": "Formato:",
        "settings.defaultLevel": "Nível de compressão:",
        "settings.afterExtract": "Mostrar arquivos extraídos no Finder",
        "settings.updates": "Atualizações",
        "settings.autoCheck": "Verificar atualizações automaticamente ao iniciar",
        "settings.checkNow": "Verificar Agora",
        "settings.lastCheck": "Última verificação: %@",
        "settings.never": "Nunca",

        "update.checking": "Verificando atualizações…",
        "update.available.title": "Uma nova versão do YUCE ZIP está disponível!",
        "update.available.message": "O YUCE ZIP %@ está disponível — você tem a versão %@. Deseja baixá-la agora?",
        "update.download": "Baixar",
        "update.later": "Mais Tarde",
        "update.uptodate.title": "Você está atualizado!",
        "update.uptodate.message": "O YUCE ZIP %@ é a versão mais recente.",
        "update.failed.title": "Não foi possível verificar atualizações",
        "update.failed.message": "Verifique sua conexão com a internet e tente novamente.\n\n%@",
        "update.notes": "Novidades:",

        "about.version": "Versão %@",
        "about.description": "Compactador de arquivos gratuito e de código aberto para macOS, com o mecanismo 7-Zip.",
        "about.engine": "Mecanismo de compressão: 7-Zip %@ © Igor Pavlov (GNU LGPL)",
        "about.github": "GitHub",

        "settings.integration": "Integração com o Sistema",
        "settings.makeDefault": "Tornar o YUCE ZIP o App Padrão para Arquivos",
        "settings.isDefault": "O YUCE ZIP abre arquivos ZIP por padrão.",
        "settings.notDefault": "Outro app abre arquivos ZIP por padrão no momento.",
        "settings.defaultDone": "O YUCE ZIP agora é o app padrão para %d tipos de arquivo.",
        "settings.defaultFailed": "Alguns tipos de arquivo não puderam ser alterados (%d).",
        "settings.finderMenu": "Mostrar o YUCE ZIP no menu de clique direito do Finder",
        "settings.finderSettings": "Ajustes da Extensão…",
        "settings.finderHint": "Se o menu não aparecer, ative “YUCE ZIP” em Ajustes do Sistema → Geral → Itens de Início e Extensões → Finder.",
        "finder.open": "Abrir com YUCE ZIP",
        "finder.extract": "Extrair Arquivos…",
        "finder.extractHere": "Extrair Aqui",
        "finder.extractTo": "Extrair para “%@/”",
        "finder.test": "Testar Arquivo",
        "finder.addTo": "Adicionar ao Arquivo…",
        "finder.compressTo": "Compactar para “%@”",
        "qa.confirmTitle": "Executar ação do YUCE ZIP?",
        "qa.confirmMessage": "Outro aplicativo pediu ao YUCE ZIP para executar “%@” em:\n\n%@",
        "qa.run": "Executar",
    ]
}
