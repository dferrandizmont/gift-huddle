import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentPickerDelegate
{
  /// Tope un poco por encima del tamano maximo de un sobre (2 MiB); Flutter
  /// rechaza lo que se pase.
  private static let maxIncomingBytes = 2 * 1024 * 1024 + 1024
  /// Tope de un fichero de recuperación (ADR 0008).
  private static let maxRecoveryBytes = 512

  private var incomingChannel: FlutterMethodChannel?
  private var pendingFile: Data?
  private var flutterAskedForInitialFile = false

  /// Selector de ficheros abierto para el fichero de recuperación (ADR 0008):
  /// uno a la vez. Cancelar devuelve nil, no un error.
  private var pickerResult: FlutterResult?
  private var pickerMaxBytes = 0
  /// Copia temporal que se exporta al guardar; se borra al terminar.
  private var pickerExport: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Una copia del fichero de recuperación que quedara de un cierre abrupto
    // con el selector abierto (ADR 0008): aquí todavía no hay ninguno abierto.
    AppDelegate.clearRecoveryExport()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.dferrandizmont.regalos/incoming",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "takeInitialFile":
        self.flutterAskedForInitialFile = true
        if let data = self.pendingFile {
          self.pendingFile = nil
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)
        }
      case "excludeFromBackup":
        // NSURLIsExcludedFromBackupKey: el documento cifrado no va a iCloud ni
        // a las copias del iPhone.
        guard let path = call.arguments as? String else {
          return result(FlutterError(code: "bad_args", message: "falta la ruta", details: nil))
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(nil)
        } catch {
          result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
        }
      case "deviceModel":
        // "iPhone" o "iPad": el nombre que puso la persona al móvil no se lee.
        result(UIDevice.current.model)
      case "openUrl":
        // Abre un enlace https en el navegador del sistema (la politica de
        // privacidad de Acerca de) o un mailto: en la app de correo (el
        // soporte). La app no se conecta a nada.
        guard let text = call.arguments as? String,
          // Validate the original authority, including any explicit :443.
          text.hasPrefix("mailto:") || text.range(
            of: #"^https://gifthuddle\.app(?:[/?#]|$)"#,
            options: [.regularExpression, .caseInsensitive]
          ) != nil,
          let url = URL(string: text),
          url.scheme == "https" || url.scheme == "mailto"
        else { return result(false) }
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened)
        }
      case "saveDocument":
        self.saveDocument(call.arguments, result: result)
      case "openDocument":
        self.openDocument(call.arguments, result: result)
      case "normalizeNfc":
        // NFC de la contraseña del fichero de recuperación, sin recortar ni
        // cambiar nada más.
        guard let text = call.arguments as? String else {
          return result(FlutterError(code: "bad_args", message: nil, details: nil))
        }
        result(text.precomposedStringWithCanonicalMapping)
      case "clearRecoveryExport":
        // Arranque: la copia del fichero de recuperación que exporta el
        // selector, si un cierre abrupto la dejó (ADR 0008).
        AppDelegate.clearRecoveryExport()
        result(nil)
      case "clearInbox":
        // "Borrar todo": las copias de los .regalos abiertos con la app que
        // quedaran en Documents/Inbox.
        AppDelegate.clearInbox()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    incomingChannel = channel
  }

  // MARK: - Fichero de recuperación (ADR 0008)

  /// Guarda con UIDocumentPickerViewController(forExporting:): escribe una
  /// copia temporal en tmp/recovery-export, la exporta y relee el destino
  /// elegido (con acceso de seguridad y coordinación) con lectura acotada.
  private func saveDocument(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pickerResult == nil else {
      return result(FlutterError(code: "busy", message: nil, details: nil))
    }
    guard let args = arguments as? [String: Any],
      let data = (args["bytes"] as? FlutterStandardTypedData)?.data,
      let name = args["name"] as? String, !name.isEmpty, !name.contains("/"),
      !name.hasPrefix("."),
      let max = args["maxReadBytes"] as? Int, max > 0, max <= AppDelegate.maxIncomingBytes
    else {
      return result(FlutterError(code: "bad_args", message: nil, details: nil))
    }
    guard let presenter = AppDelegate.topViewController() else {
      return result(FlutterError(code: "unavailable", message: nil, details: nil))
    }
    let files = FileManager.default
    let folder = files.temporaryDirectory.appendingPathComponent(
      "recovery-export", isDirectory: true)
    let url = folder.appendingPathComponent(name)
    do {
      try files.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: url, options: [.atomic, .completeFileProtection])
    } catch {
      try? files.removeItem(at: url)
      return result(FlutterError(code: "write_failed", message: nil, details: nil))
    }
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.delegate = self
    pickerResult = result
    pickerMaxBytes = max
    pickerExport = url
    presenter.present(picker, animated: true)
  }

  /// Abre con el document picker en el sitio (sin copia: un fichero grande
  /// no llega a copiarse) y lo lee solo si mide como mucho maxBytes.
  private func openDocument(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pickerResult == nil else {
      return result(FlutterError(code: "busy", message: nil, details: nil))
    }
    guard let args = arguments as? [String: Any],
      let max = args["maxBytes"] as? Int, max > 0, max <= AppDelegate.maxIncomingBytes
    else {
      return result(FlutterError(code: "bad_args", message: nil, details: nil))
    }
    guard let presenter = AppDelegate.topViewController() else {
      return result(FlutterError(code: "unavailable", message: nil, details: nil))
    }
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [UTType.data], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    pickerResult = result
    pickerMaxBytes = max
    pickerExport = nil
    presenter.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let result = pickerResult else { return }
    let max = pickerMaxBytes
    let export = pickerExport
    pickerResult = nil
    pickerExport = nil
    guard let url = urls.first else {
      if let export = export { try? FileManager.default.removeItem(at: export) }
      return result(nil)
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let outcome = AppDelegate.readBounded(url, max: max)
      if let export = export { try? FileManager.default.removeItem(at: export) }
      DispatchQueue.main.async {
        switch outcome {
        case .success(let data):
          result(FlutterStandardTypedData(bytes: data))
        case .failure(let failure):
          result(FlutterError(code: failure.code, message: nil, details: nil))
        }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let result = pickerResult else { return }
    if let export = pickerExport { try? FileManager.default.removeItem(at: export) }
    pickerResult = nil
    pickerExport = nil
    result(nil)
  }

  private enum ReadFailure: Error {
    case tooLarge
    case unreadable

    var code: String { self == .tooLarge ? "too_large" : "read_failed" }
  }

  /// Lee url con acceso de seguridad y NSFileCoordinator, solo si mide como
  /// mucho max bytes: mira antes el tamaño y nunca lee más de max + 1.
  private static func readBounded(_ url: URL, max: Int) -> Result<Data, ReadFailure> {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    var outcome: Result<Data, ReadFailure> = .failure(.unreadable)
    var coordination: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: [.withoutChanges], error: &coordination
    ) { readURL in
      if let size = try? readURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size > max
      {
        outcome = .failure(.tooLarge)
        return
      }
      guard let handle = try? FileHandle(forReadingFrom: readURL) else { return }
      defer { try? handle.close() }
      do {
        let data = try handle.read(upToCount: max + 1) ?? Data()
        outcome = data.count > max ? .failure(.tooLarge) : .success(data)
      } catch {
        outcome = .failure(.unreadable)
      }
    }
    return outcome
  }

  /// El controlador visible desde el que presentar el selector.
  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  /// Un fichero .regalos abierto desde Archivos, WhatsApp, etc. (sin escenas).
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.isFileURL {
      deliverIncomingFile(url)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// Lee el fichero y se lo pasa a Flutter. Lo usa tambien SceneDelegate.
  ///
  /// Con LSSupportsOpeningDocumentsInPlace = false iOS no da el fichero
  /// original sino una copia dentro de la app (Documents/Inbox), que nadie
  /// mas borra: entraria en las copias de iCloud y sobreviviria a "Borrar
  /// todo". Se borra aqui, nada mas leerla (tambien si no se pudo leer o
  /// pesa demasiado). Un fichero de fuera del contenedor no se toca.
  func deliverIncomingFile(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    // Lectura acotada, nunca el fichero entero de golpe: se lee en memoria
    // antes de borrar la copia de Inbox.
    let data = AppDelegate.readIncoming(url)
    AppDelegate.removeIfInInbox(url)
    guard let bytes = data else { return }
    if flutterAskedForInitialFile, let channel = incomingChannel {
      channel.invokeMethod("onFile", arguments: FlutterStandardTypedData(bytes: bytes))
    } else {
      pendingFile = bytes
    }
  }

  /// Mira primero la magia: un fichero de recuperación (GHK) se corta en
  /// 513 bytes (Flutter lo rechaza por grande) sin leer el resto; un sobre se
  /// lee solo si mide como mucho maxIncomingBytes.
  private static func readIncoming(_ url: URL) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    do {
      var data = try handle.read(upToCount: 3) ?? Data()
      let recovery = data.count == 3 && data[data.startIndex] == 0x47
        && data[data.startIndex + 1] == 0x48 && data[data.startIndex + 2] == 0x4B
      let limit = recovery ? AppDelegate.maxRecoveryBytes : AppDelegate.maxIncomingBytes
      if !recovery,
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size > limit
      {
        return nil
      }
      if data.count == 3, let rest = try handle.read(upToCount: limit + 1 - 3) {
        data.append(rest)
      }
      if data.count > limit {
        return recovery ? data : nil
      }
      return data
    } catch {
      return nil
    }
  }

  /// Borra la copia temporal que exporta el selector del fichero de
  /// recuperación (tmp/recovery-export).
  private static func clearRecoveryExport() {
    let files = FileManager.default
    let export = files.temporaryDirectory.appendingPathComponent(
      "recovery-export", isDirectory: true)
    try? files.removeItem(at: export)
  }

  /// Las carpetas de la app donde iOS deja la copia de un fichero que se
  /// abre con ella: Documents/Inbox y, segun la version, tmp/<bundle>-Inbox.
  private static func inboxFolders() -> [URL] {
    let files = FileManager.default
    var folders: [URL] = []
    if let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first {
      folders.append(documents.appendingPathComponent("Inbox", isDirectory: true))
    }
    if let bundle = Bundle.main.bundleIdentifier {
      folders.append(
        files.temporaryDirectory.appendingPathComponent("\(bundle)-Inbox", isDirectory: true))
    }
    return folders
  }

  /// La ruta real de una carpeta, para comparar (/var y /private/var son la
  /// misma).
  private static func realPath(_ folder: URL) -> String {
    return folder.standardizedFileURL.resolvingSymlinksInPath().path
  }

  /// Borra el fichero solo si esta directamente dentro de una de las
  /// carpetas Inbox de la app; nunca fuera del contenedor.
  private static func removeIfInInbox(_ url: URL) {
    guard url.isFileURL else { return }
    let parent = AppDelegate.realPath(url.deletingLastPathComponent())
    let inbox = AppDelegate.inboxFolders().map { AppDelegate.realPath($0) }
    guard inbox.contains(parent) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// "Borrar todo": vacia las carpetas Inbox de la app y la copia temporal
  /// que exporta el selector del fichero de recuperación.
  private static func clearInbox() {
    let files = FileManager.default
    let export = files.temporaryDirectory.appendingPathComponent(
      "recovery-export", isDirectory: true)
    for folder in AppDelegate.inboxFolders() + [export] {
      guard
        let entries = try? files.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: nil, options: [])
      else { continue }
      for entry in entries {
        try? files.removeItem(at: entry)
      }
    }
  }
}
