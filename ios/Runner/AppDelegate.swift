import Darwin
import Flutter
import UIKit
import UniformTypeIdentifiers

@_silgen_name("posix_spawnattr_set_persona_np")
private func posix_spawnattr_set_persona_np(
  _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
  _ persona_id: uid_t,
  _ flags: UInt32
) -> Int32

@_silgen_name("posix_spawnattr_set_persona_uid_np")
private func posix_spawnattr_set_persona_uid_np(
  _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
  _ persona_id: uid_t
) -> Int32

@_silgen_name("posix_spawnattr_set_persona_gid_np")
private func posix_spawnattr_set_persona_gid_np(
  _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
  _ persona_id: uid_t
) -> Int32

private let kPersonaFlagsOverride: UInt32 = 1

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var bridgeChannel: FlutterMethodChannel?
  private var pendingPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "com.magicfall.trollservice/bridge",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleBridgeCall(call: call, result: result)
    }
    self.bridgeChannel = channel
  }

  private func handleBridgeCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initWorkspace":
      DispatchQueue.global(qos: .userInitiated).async {
        let output = self.invokeRootHelper(args: ["init-workspace"])
        DispatchQueue.main.async {
          result(output)
        }
      }

    case "installService":
      guard let args = call.arguments as? [String: Any],
            let serviceId = args["id"] as? String,
            let srcPath = args["srcPath"] as? String,
            let binaryName = args["binaryName"] as? String else {
        DispatchQueue.main.async {
          result(["ok": false, "error": "installService 缺少必要参数"])
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let output = self.invokeRootHelper(args: ["install", serviceId, srcPath, binaryName])
        DispatchQueue.main.async {
          result(output)
        }
      }

    case "updateService":
      guard let args = call.arguments as? [String: Any],
            let serviceId = args["id"] as? String,
            let srcPath = args["srcPath"] as? String,
            let binaryName = args["binaryName"] as? String else {
        DispatchQueue.main.async {
          result(["ok": false, "error": "updateService 缺少必要参数"])
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let output = self.invokeRootHelper(args: ["update", serviceId, srcPath, binaryName])
        DispatchQueue.main.async {
          result(output)
        }
      }

    case "startService":
      guard let args = call.arguments as? [String: Any],
            let serviceId = args["id"] as? String,
            let binaryName = args["binaryName"] as? String else {
        DispatchQueue.main.async {
          result(["ok": false, "error": "startService 缺少必要参数"])
        }
        return
      }
      let keepAlive = (args["keepAlive"] as? Bool) ?? true
      let extraArgs = (args["args"] as? [String]) ?? []
      var cmdArgs = ["start", serviceId, binaryName, keepAlive ? "1" : "0"]
      cmdArgs.append(contentsOf: extraArgs)

      DispatchQueue.global(qos: .userInitiated).async {
        let output = self.invokeRootHelper(args: cmdArgs)
        DispatchQueue.main.async {
          result(output)
        }
      }

    case "stopService":
      guard let args = call.arguments as? [String: Any],
            let serviceId = args["id"] as? String else {
        DispatchQueue.main.async {
          result(["ok": false, "error": "stopService 缺少必要参数"])
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let output = self.invokeRootHelper(args: ["stop", serviceId])
        DispatchQueue.main.async {
          result(output)
        }
      }

    case "getServiceStatus":
      guard let args = call.arguments as? [String: Any],
            let serviceId = args["id"] as? String else {
        DispatchQueue.main.async {
          result(["ok": false, "error": "getServiceStatus 缺少必要参数"])
        }
        return
      }
      let port = (args["port"] as? Int) ?? 0
      DispatchQueue.global(qos: .utility).async {
        var statusDict = self.invokeRootHelper(args: ["status", serviceId])
        let isRunning = (statusDict["running"] as? Bool) ?? false
        let portOpen = (isRunning && port > 0) ? self.checkLocalPortOpen(port: UInt16(clamping: port)) : false
        statusDict["port_open"] = portOpen
        DispatchQueue.main.async {
          result(statusDict)
        }
      }

    case "uninstallService":
      guard let args = call.arguments as? [String: Any],
            let serviceId = args["id"] as? String else {
        DispatchQueue.main.async {
          result(["ok": false, "error": "uninstallService 缺少必要参数"])
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let output = self.invokeRootHelper(args: ["uninstall", serviceId])
        DispatchQueue.main.async {
          result(output)
        }
      }

    case "getLocalIpAddress":
      DispatchQueue.global(qos: .utility).async {
        let ip = self.resolveLocalWiFiIPv4() ?? "127.0.0.1"
        DispatchQueue.main.async {
          result(ip)
        }
      }

    case "pickBinaryFile":
      DispatchQueue.main.async {
        self.presentBinaryDocumentPicker(result: result)
      }

    case "openUrl":
      guard let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString) else {
        DispatchQueue.main.async {
          result(false)
        }
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { success in
          result(success)
        }
      }

    default:
      DispatchQueue.main.async {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func invokeRootHelper(args: [String]) -> [String: Any] {
    let helperPath = Bundle.main.bundlePath + "/Helpers/daemon_root_helper"
    guard FileManager.default.fileExists(atPath: helperPath) else {
      return ["ok": false, "error": "未找到内置 daemon_root_helper: \(helperPath)"]
    }

    var allArgs = [helperPath]
    allArgs.append(contentsOf: args)

    var cArgs: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) }
    cArgs.append(nil)
    defer {
      for ptr in cArgs {
        if let p = ptr {
          free(p)
        }
      }
    }

    var outPipe: [Int32] = [-1, -1]
    if pipe(&outPipe) != 0 {
      return ["ok": false, "error": "创建进程通信管道失败"]
    }

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
    posix_spawn_file_actions_addclose(&fileActions, outPipe[1])

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    _ = posix_spawnattr_set_persona_np(&attr, 99, kPersonaFlagsOverride)
    _ = posix_spawnattr_set_persona_uid_np(&attr, 0)
    _ = posix_spawnattr_set_persona_gid_np(&attr, 0)

    var pid: pid_t = 0
    let spawnErr = cArgs.withUnsafeMutableBufferPointer { buf -> Int32 in
      guard let base = buf.baseAddress else { return -1 }
      return posix_spawn(&pid, helperPath, &fileActions, &attr, base, nil)
    }

    posix_spawnattr_destroy(&attr)
    posix_spawn_file_actions_destroy(&fileActions)
    close(outPipe[1])

    if spawnErr != 0 {
      close(outPipe[0])
      return ["ok": false, "error": "posix_spawn 调用失败 (errno=\(spawnErr))"]
    }

    var outputData = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let bytesRead = read(outPipe[0], &buffer, buffer.count)
      if bytesRead <= 0 {
        break
      }
      outputData.append(buffer, count: bytesRead)
    }
    close(outPipe[0])

    var status: Int32 = 0
    waitpid(pid, &status, 0)

    let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let jsonData = outputString.data(using: .utf8),
       let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
      return dict
    }

    let exitCode = (status & 0x7f) == 0 ? ((status >> 8) & 0xff) : -1
    if exitCode == 0 {
      return ["ok": true, "raw": outputString]
    }
    return ["ok": false, "error": outputString.isEmpty ? "Helper 异常退出 (code=\(exitCode))" : outputString]
  }

  private func checkLocalPortOpen(port: UInt16) -> Bool {
    if port == 0 { return false }
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    if sock < 0 { return false }
    defer { close(sock) }

    var tv = timeval(tv_sec: 0, tv_usec: 250_000)
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let connectResult = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return connectResult == 0
  }

  private func resolveLocalWiFiIPv4() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
      return nil
    }
    defer { freeifaddrs(ifaddr) }

    var fallbackIP: String?
    var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let current = ptr {
      let interface = current.pointee
      if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
        let name = String(cString: interface.ifa_name)
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(
          addr,
          socklen_t(addr.pointee.sa_len),
          &hostname,
          socklen_t(hostname.count),
          nil,
          0,
          NI_NUMERICHOST
        ) == 0 {
          let ip = String(cString: hostname)
          if name == "en0" {
            return ip
          } else if name != "lo0" && fallbackIP == nil {
            fallbackIP = ip
          }
        }
      }
      ptr = interface.ifa_next
    }
    return fallbackIP
  }

  private func presentBinaryDocumentPicker(result: @escaping FlutterResult) {
    if self.pendingPickerResult != nil {
      result(nil)
      return
    }
    guard let rootVC = self.activeRootViewController() else {
      result(nil)
      return
    }
    self.pendingPickerResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    rootVC.present(picker, animated: true)
  }

  private func activeRootViewController() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene {
        for window in windowScene.windows where window.isKeyWindow {
          return window.rootViewController
        }
        if let firstWindow = windowScene.windows.first {
          return firstWindow.rootViewController
        }
      }
    }
    return nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let callback = self.pendingPickerResult else { return }
    self.pendingPickerResult = nil
    guard let firstUrl = urls.first else {
      callback(nil)
      return
    }
    callback(firstUrl.path)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let callback = self.pendingPickerResult else { return }
    self.pendingPickerResult = nil
    callback(nil)
  }
}
