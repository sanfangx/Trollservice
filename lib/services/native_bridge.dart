import 'dart:io';
import 'package:flutter/services.dart';
import '../models/service_item.dart';

/// 底层 RootHelper 与原生系统能力桥接接口
abstract class ServiceNativeBridge {
  /// 服务安装根路径（真机固定为 /var/mobile/Documents/service）
  String get serviceRootPath;

  /// 初始化 /var/mobile/Documents/service 工作目录
  Future<Map<String, dynamic>> initWorkspace();

  /// 安装程序：创建目录、复制二进制、执行 ldid -S 赋权与 fastPathSign CoreTrust 签名
  Future<Map<String, dynamic>> installService({
    required String id,
    required String srcPath,
    required String binaryName,
  });

  /// 更新程序：停止运行中进程、仅替换 `bin/<binaryName>` 并重新执行 ldid -S + fastPathSign，100% 保留程序数据
  Future<Map<String, dynamic>> updateService({
    required String id,
    required String srcPath,
    required String binaryName,
  });

  /// 启动服务（以 persona-mgmt UID 0 + POSIX_SPAWN_SETSID 后台常驻运行）
  Future<Map<String, dynamic>> startService({
    required String id,
    required String binaryName,
    required bool keepAlive,
    required List<String> args,
  });

  /// 停止服务
  Future<Map<String, dynamic>> stopService(String id);

  /// 查询服务进程存活、PID、物理内存、运行时长及 TCP 端口连通性
  Future<ServiceRuntimeStatus> getServiceStatus({
    required String id,
    required int port,
  });

  /// 卸载服务并清理目录
  Future<Map<String, dynamic>> uninstallService(String id);

  /// 获取本机局域网 IPv4 地址
  Future<String> getLocalIpAddress();

  /// 调起系统文件选择器挑选二进制文件
  Future<String?> pickBinaryFile();

  /// 在系统浏览器打开管理面板 URL
  Future<bool> openUrl(String url);
}

/// iOS 真机 MethodChannel 实现
class MethodChannelServiceBridge implements ServiceNativeBridge {
  static const MethodChannel _channel =
      MethodChannel('com.magicfall.trollservice/bridge');

  @override
  final String serviceRootPath;

  const MethodChannelServiceBridge({
    this.serviceRootPath = kDefaultServiceRoot,
  });

  Map<String, dynamic> _normalizeMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'ok': false, 'error': '未知返回格式: $raw'};
  }

  @override
  Future<Map<String, dynamic>> initWorkspace() async {
    try {
      final res = await _channel.invokeMethod<Object?>('initWorkspace');
      return _normalizeMap(res);
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    } on MissingPluginException {
      final dir = Directory(serviceRootPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return {'ok': true, 'root': serviceRootPath};
    }
  }

  @override
  Future<Map<String, dynamic>> installService({
    required String id,
    required String srcPath,
    required String binaryName,
  }) async {
    try {
      final res = await _channel.invokeMethod<Object?>('installService', {
        'id': id,
        'srcPath': srcPath,
        'binaryName': binaryName,
      });
      return _normalizeMap(res);
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    }
  }

  @override
  Future<Map<String, dynamic>> updateService({
    required String id,
    required String srcPath,
    required String binaryName,
  }) async {
    try {
      final res = await _channel.invokeMethod<Object?>('updateService', {
        'id': id,
        'srcPath': srcPath,
        'binaryName': binaryName,
      });
      return _normalizeMap(res);
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    }
  }

  @override
  Future<Map<String, dynamic>> startService({
    required String id,
    required String binaryName,
    required bool keepAlive,
    required List<String> args,
  }) async {
    try {
      final res = await _channel.invokeMethod<Object?>('startService', {
        'id': id,
        'binaryName': binaryName,
        'keepAlive': keepAlive,
        'args': args,
      });
      return _normalizeMap(res);
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    }
  }

  @override
  Future<Map<String, dynamic>> stopService(String id) async {
    try {
      final res = await _channel.invokeMethod<Object?>('stopService', {
        'id': id,
      });
      return _normalizeMap(res);
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    }
  }

  @override
  Future<ServiceRuntimeStatus> getServiceStatus({
    required String id,
    required int port,
  }) async {
    try {
      final res = await _channel.invokeMethod<Object?>('getServiceStatus', {
        'id': id,
        'port': port,
      });
      final map = _normalizeMap(res);
      final running = (map['running'] as bool?) ?? false;
      final portOpen = (map['port_open'] as bool?) ?? false;
      final pid = (map['pid'] as num?)?.toInt() ?? 0;
      final memBytes = (map['memory_bytes'] as num?)?.toInt() ?? 0;
      final uptimeSec = (map['uptime_sec'] as num?)?.toInt() ?? 0;
      return ServiceRuntimeStatus(
        isRunning: running,
        isPortOpen: portOpen,
        pid: pid,
        memoryBytes: memBytes,
        uptimeSeconds: uptimeSec,
      );
    } catch (_) {
      return const ServiceRuntimeStatus();
    }
  }

  @override
  Future<Map<String, dynamic>> uninstallService(String id) async {
    try {
      final res = await _channel.invokeMethod<Object?>('uninstallService', {
        'id': id,
      });
      return _normalizeMap(res);
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    }
  }

  @override
  Future<String> getLocalIpAddress() async {
    try {
      final ip = await _channel.invokeMethod<String>('getLocalIpAddress');
      return (ip != null && ip.isNotEmpty) ? ip : '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }

  @override
  Future<String?> pickBinaryFile() async {
    try {
      return await _channel.invokeMethod<String>('pickBinaryFile');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openUrl(String url) async {
    try {
      final ok = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// 用于本地开发、桌面预览及自动化单元测试的本地文件系统实现（完全复刻 daemon_root_helper 的目录与保留数据行为）
class FileSystemMockServiceBridge implements ServiceNativeBridge {
  @override
  final String serviceRootPath;

  final Map<String, ServiceRuntimeStatus> _runningStates = {};
  final List<String> executedSignCommands = [];
  String? mockPickedFilePath;

  FileSystemMockServiceBridge({required this.serviceRootPath});

  @override
  Future<Map<String, dynamic>> initWorkspace() async {
    final dir = Directory(serviceRootPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return {'ok': true, 'root': serviceRootPath};
  }

  @override
  Future<Map<String, dynamic>> installService({
    required String id,
    required String srcPath,
    required String binaryName,
  }) async {
    final srcFile = File(srcPath);
    if (!srcFile.existsSync()) {
      return {'ok': false, 'error': '源二进制文件不存在: $srcPath'};
    }

    final baseDir = Directory('$serviceRootPath/$id');
    final binDir = Directory('${baseDir.path}/bin');
    final cfgDir = Directory('${baseDir.path}/config');
    final runDir = Directory('${baseDir.path}/runtime');
    binDir.createSync(recursive: true);
    cfgDir.createSync(recursive: true);
    runDir.createSync(recursive: true);

    final dstBin = File('${binDir.path}/$binaryName');
    srcFile.copySync(dstBin.path);

    final entsFile = File('${cfgDir.path}/entitlements.plist');
    entsFile.writeAsStringSync(ServiceItem.generateServiceEntitlementsXml(id));

    executedSignCommands.add('ldid -S${entsFile.path} ${dstBin.path}');
    executedSignCommands.add('fastPathSign ${dstBin.path}');

    return {'ok': true, 'action': 'install', 'binary': dstBin.path};
  }

  @override
  Future<Map<String, dynamic>> updateService({
    required String id,
    required String srcPath,
    required String binaryName,
  }) async {
    final srcFile = File(srcPath);
    if (!srcFile.existsSync()) {
      return {'ok': false, 'error': '新二进制文件不存在: $srcPath'};
    }

    final wasRunning = _runningStates[id]?.isRunning ?? false;
    if (wasRunning) {
      await stopService(id);
    }

    final baseDir = Directory('$serviceRootPath/$id');
    final binDir = Directory('${baseDir.path}/bin');
    final cfgDir = Directory('${baseDir.path}/config');
    final runDir = Directory('${baseDir.path}/runtime');
    binDir.createSync(recursive: true);
    cfgDir.createSync(recursive: true);
    runDir.createSync(recursive: true);

    /* 仅覆盖替换 bin/<binaryName>，绝不删除或清空 config/, runtime/ 或其他数据子目录 */
    final dstBin = File('${binDir.path}/$binaryName');
    srcFile.copySync(dstBin.path);

    final entsFile = File('${cfgDir.path}/entitlements.plist');
    if (!entsFile.existsSync()) {
      entsFile.writeAsStringSync(ServiceItem.generateServiceEntitlementsXml(id));
    }

    executedSignCommands.add('ldid -S${entsFile.path} ${dstBin.path}');
    executedSignCommands.add('fastPathSign ${dstBin.path}');

    return {
      'ok': true,
      'action': 'update',
      'was_running': wasRunning,
      'preserved_data': true,
      'binary': dstBin.path,
    };
  }

  @override
  Future<Map<String, dynamic>> startService({
    required String id,
    required String binaryName,
    required bool keepAlive,
    required List<String> args,
  }) async {
    final baseDir = '$serviceRootPath/$id';
    final envCfg = File('$baseDir/config/.env');
    final envWork = File('$baseDir/.env');
    if (envCfg.existsSync()) {
      envCfg.copySync(envWork.path);
    }

    final logFile = File('$baseDir/runtime/stdout.log');
    logFile.parent.createSync(recursive: true);
    final timestamp = DateTime.now().toIso8601String();
    logFile.writeAsStringSync(
      '[$timestamp] [INFO] 服务 $id ($binaryName) 已由 TrollService 启动 | 参数=${args.join(" ")}\n',
      mode: FileMode.append,
    );

    final pid = 4000 + id.hashCode.abs() % 5000;
    _runningStates[id] = ServiceRuntimeStatus(
      isRunning: true,
      isPortOpen: true,
      pid: pid,
      memoryBytes: 38 * 1024 * 1024,
      uptimeSeconds: 12,
    );
    return {'ok': true, 'pid': pid};
  }

  @override
  Future<Map<String, dynamic>> stopService(String id) async {
    _runningStates[id] = const ServiceRuntimeStatus(isRunning: false);
    final logFile = File('$serviceRootPath/$id/runtime/stdout.log');
    if (logFile.existsSync()) {
      final timestamp = DateTime.now().toIso8601String();
      logFile.writeAsStringSync(
        '[$timestamp] [INFO] 服务 $id 已停止\n',
        mode: FileMode.append,
      );
    }
    return {'ok': true, 'action': 'stop'};
  }

  @override
  Future<ServiceRuntimeStatus> getServiceStatus({
    required String id,
    required int port,
  }) async {
    final current = _runningStates[id];
    if (current == null || !current.isRunning) {
      return const ServiceRuntimeStatus();
    }
    final nextUptime = current.uptimeSeconds + 2;
    final updated = current.copyWith(
      uptimeSeconds: nextUptime,
      isPortOpen: port > 0,
    );
    _runningStates[id] = updated;
    return updated;
  }

  @override
  Future<Map<String, dynamic>> uninstallService(String id) async {
    await stopService(id);
    final dir = Directory('$serviceRootPath/$id');
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    return {'ok': true, 'action': 'uninstall'};
  }

  @override
  Future<String> getLocalIpAddress() async => '192.168.1.50';

  @override
  Future<String?> pickBinaryFile() async => mockPickedFilePath;

  @override
  Future<bool> openUrl(String url) async => true;
}
