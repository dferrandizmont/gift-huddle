import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Tope un poco por encima del tamano maximo de un sobre (2 MiB); Flutter
  /// rechaza lo que se pase.
  private static let maxIncomingBytes = 2 * 1024 * 1024 + 1024

  private var incomingChannel: FlutterMethodChannel?
  private var pendingFile: Data?
  private var flutterAskedForInitialFile = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
    let mapped = try? Data(contentsOf: url, options: .mappedIfSafe)
    // Copia en memoria antes de borrar: `mapped` puede ser el propio fichero.
    var data: Data?
    if let mapped = mapped, mapped.count <= AppDelegate.maxIncomingBytes {
      data = Data([UInt8](mapped))
    }
    AppDelegate.removeIfInInbox(url)
    guard let bytes = data else { return }
    if flutterAskedForInitialFile, let channel = incomingChannel {
      channel.invokeMethod("onFile", arguments: FlutterStandardTypedData(bytes: bytes))
    } else {
      pendingFile = bytes
    }
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

  /// "Borrar todo": vacia las carpetas Inbox de la app.
  private static func clearInbox() {
    let files = FileManager.default
    for folder in AppDelegate.inboxFolders() {
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
