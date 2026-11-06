import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';

import '../models/service_item.dart';
import 'native_bridge.dart';

/// 全局微服务控制器（管理 /var/mobile/Documents/service 下的所有程序生命周期）
class DaemonController extends ChangeNotifier with WidgetsBindingObserver {
  final ServiceNativeBridge bridge;

  List<ServiceItem> _services = [];
  String _localIp = '127.0.0.1';
  bool _initialized = false;
  bool _pollingEnabled = false;
  bool _isRefreshing = false;
  bool _observerAttached = false;
  String? _lastError;
  Timer? _statusTimer;
  final Set<String> _busyServiceIds = {};

  DaemonController({ServiceNativeBridge? bridge})
      : bridge = bridge ?? MethodChannelServiceBridge();

  List<ServiceItem> get services => List.unmodifiable(_services);
  String get localIp => _localIp;
  bool get initialized => _initialized;
  String? get lastError => _lastError;
  String get serviceRootPath => bridge.serviceRootPath;

  int _refreshIntervalSeconds = 2;
  int get refreshIntervalSeconds => _refreshIntervalSeconds;

  int get runningCount =>
      _services.where((item) => item.status.isRunning).length;

  bool isBusy(String serviceId) => _busyServiceIds.contains(serviceId);

  String get _registryFilePath => '$serviceRootPath/services.json';

  /// 初始化工作区、读取注册表并启动实时状态轮询
  Future<void> initialize({bool enablePolling = true}) async {
    _pollingEnabled = enablePolling;
    try {
      final cfgFile = File('/var/mobile/Documents/.trollservice_root');
      if (cfgFile.existsSync()) {
        final savedRoot = cfgFile.readAsStringSync().trim();
        if (savedRoot.isNotEmpty) {
          await bridge.setServiceRootPath(savedRoot);
        }
      }
    } catch (_) {}

    await bridge.initWorkspace();
    await _loadRegistry();
    _localIp = await bridge.getLocalIpAddress();
    await refreshAllStatuses();
    _initialized = true;
    notifyListeners();

    if (!_observerAttached) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observerAttached = true;
      } catch (_) {}
    }

    _restartPollingTimerIfNeeded();
  }

  void _restartPollingTimerIfNeeded() {
    _statusTimer?.cancel();
    _statusTimer = null;
    if (_pollingEnabled && _refreshIntervalSeconds > 0) {
      _statusTimer = Timer.periodic(
        Duration(seconds: _refreshIntervalSeconds),
        (_) => refreshAllStatuses(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _statusTimer?.cancel();
      _statusTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_initialized) {
        refreshAllStatuses();
        _restartPollingTimerIfNeeded();
      }
    }
  }

  void setRefreshInterval(int seconds) {
    if (_refreshIntervalSeconds == seconds) return;
    _refreshIntervalSeconds = seconds;
    _restartPollingTimerIfNeeded();
    notifyListeners();
  }

  /// 自定义修改服务安装根路径
  Future<bool> setCustomServiceRootPath(String newPath) async {
    final cleanPath = newPath.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleanPath.isEmpty || cleanPath.contains('..')) return false;

    final ok = await bridge.setServiceRootPath(cleanPath);
    if (!ok) return false;

    await bridge.initWorkspace();
    await _loadRegistry();
    await refreshAllStatuses();
    notifyListeners();
    return true;
  }

  /// 一键停止所有正在运行的服务
  Future<void> stopAllServices() async {
    final snapshot = List<ServiceItem>.from(_services);
    for (final s in snapshot) {
      if (s.status.isRunning) {
        await stopService(s.id);
      }
    }
    await refreshAllStatuses();
  }

  /// 清理所有服务的运行日志
  Future<int> clearAllLogs() async {
    var count = 0;
    for (final s in _services) {
      final logFile = File(s.stdoutLogPath(serviceRootPath));
      if (logFile.existsSync()) {
        try {
          logFile.writeAsStringSync('');
          count++;
        } catch (_) {}
      }
    }
    notifyListeners();
    return count;
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
    super.dispose();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> _loadRegistry() async {
    try {
      final file = File(_registryFilePath);
      if (!file.existsSync()) {
        _services = [];
        return;
      }
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _services = decoded
            .whereType<Map<String, dynamic>>()
            .map(ServiceItem.fromJson)
            .toList();
      }
    } catch (e) {
      _lastError = '读取 services.json 失败: $e';
    }
  }

  Future<void> _saveRegistry() async {
    try {
      final file = File(_registryFilePath);
      file.parent.createSync(recursive: true);
      final encoded = const JsonEncoder.withIndent('  ')
          .convert(_services.map((e) => e.toJson()).toList());
      file.writeAsStringSync(encoded);
    } catch (e) {
      _lastError = '保存 services.json 失败: $e';
    }
  }

  Future<void> _writeEnvFiles(ServiceItem item, {String? rawEnvContent}) async {
    try {
      final content = rawEnvContent ?? ServiceItem.formatDotEnv(item.envVars);
      final cfgEnv = File(item.envFilePath(serviceRootPath));
      cfgEnv.parent.createSync(recursive: true);
      cfgEnv.writeAsStringSync(content);

      final workEnv = File('${item.serviceDir(serviceRootPath)}/.env');
      workEnv.parent.createSync(recursive: true);
      workEnv.writeAsStringSync(content);
    } catch (_) {
      // 在无直接文件写入权限时由 RootHelper 托管
    }
  }

  bool _hasStatusChanged(ServiceRuntimeStatus a, ServiceRuntimeStatus b) {
    return a.isRunning != b.isRunning ||
        a.isPortOpen != b.isPortOpen ||
        a.pid != b.pid ||
        a.memoryBytes != b.memoryBytes ||
        a.uptimeSeconds != b.uptimeSeconds;
  }

  /// 刷新所有受管服务的进程状态与端口连通性（防重入 + 并行探测 + 原位按 ID 合并避免覆盖新修改）
  Future<void> refreshAllStatuses() async {
    if (_services.isEmpty || _isRefreshing) return;
    _isRefreshing = true;

    try {
      final targets = _services
          .map((item) => (id: item.id, port: item.port))
          .toList(growable: false);

      final results = await Future.wait(
        targets.map((t) async {
          final status = await bridge.getServiceStatus(id: t.id, port: t.port);
          return MapEntry(t.id, status);
        }),
      );

      final statusMap = Map<String, ServiceRuntimeStatus>.fromEntries(results);
      var changed = false;

      for (var i = 0; i < _services.length; i++) {
        final current = _services[i];
        final nextStatus = statusMap[current.id];
        if (nextStatus != null && _hasStatusChanged(current.status, nextStatus)) {
          _services[i] = current.copyWith(status: nextStatus);
          changed = true;
        }
      }

      if (changed) {
        notifyListeners();
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// 从磁盘读取当前服务的真实 .env 文件原始文本（优先 .env，其次 config/.env，最后回退内存）
  Future<String> readServiceEnvRaw(String serviceId) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) return '';
    try {
      final workEnv =
          File('${_services[index].serviceDir(serviceRootPath)}/.env');
      if (workEnv.existsSync()) {
        return workEnv.readAsStringSync();
      }
      final cfgEnv = File(_services[index].envFilePath(serviceRootPath));
      if (cfgEnv.existsSync()) {
        return cfgEnv.readAsStringSync();
      }
    } catch (_) {}
    return ServiceItem.formatDotEnv(_services[index].envVars);
  }

  /// 从磁盘读取当前服务专属的 entitlements.plist 原始文本
  Future<String> readServiceEntitlementsRaw(String serviceId) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) return ServiceItem.generateServiceEntitlementsXml(serviceId);
    try {
      final entsFile =
          File(_services[index].entitlementsFilePath(serviceRootPath));
      if (entsFile.existsSync()) {
        return entsFile.readAsStringSync();
      }
    } catch (_) {}
    return ServiceItem.generateServiceEntitlementsXml(serviceId);
  }

  /// 安装新程序（落盘到 `/var/mobile/Documents/service/<id>` + ldid 赋权 + fastPathSign 签名）
  Future<bool> installService({
    required ServiceItem item,
    required String srcBinaryPath,
    String? customEntitlementsXml,
  }) async {
    if (!ServiceItem.isValidIdentifier(item.id) ||
        !ServiceItem.isValidIdentifier(item.binaryName)) {
      _lastError = '服务标识或可执行文件名包含非法字符（仅允许字母、数字、下划线、连字符和点）';
      notifyListeners();
      return false;
    }

    _busyServiceIds.add(item.id);
    _lastError = null;
    notifyListeners();

    try {
      final res = await bridge.installService(
        id: item.id,
        srcPath: srcBinaryPath,
        binaryName: item.binaryName,
        customEntitlementsXml: customEntitlementsXml,
      );
      final ok = (res['ok'] as bool?) ?? false;
      if (!ok) {
        _lastError = (res['error'] as String?) ?? '安装并签名失败';
        return false;
      }

      if (item.envVars.isNotEmpty) {
        await _writeEnvFiles(item);
      }

      final existingIndex = _services.indexWhere((s) => s.id == item.id);
      if (existingIndex >= 0) {
        _services[existingIndex] = item;
      } else {
        _services.add(item);
      }
      await _saveRegistry();
      await refreshAllStatuses();
      return true;
    } finally {
      _busyServiceIds.remove(item.id);
      notifyListeners();
    }
  }

  /// 更新已安装程序的二进制文件（自动执行 ldid + fastPathSign 重签名，100% 保留原有程序数据、配置与数据库）
  Future<bool> updateServiceBinary({
    required String serviceId,
    required String newBinaryPath,
    String? customEntitlementsXml,
  }) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) {
      _lastError = '未找到服务: $serviceId';
      notifyListeners();
      return false;
    }

    final current = _services[index];
    final wasRunningBeforeUpdate = current.status.isRunning;

    _busyServiceIds.add(serviceId);
    _lastError = null;
    notifyListeners();

    try {
      final res = await bridge.updateService(
        id: current.id,
        srcPath: newBinaryPath,
        binaryName: current.binaryName,
        customEntitlementsXml: customEntitlementsXml,
      );
      final ok = (res['ok'] as bool?) ?? false;
      if (!ok) {
        _lastError = (res['error'] as String?) ?? '更新程序失败';
        return false;
      }

      final currentIdx = _services.indexWhere((s) => s.id == serviceId);
      final updatedItem = (currentIdx >= 0 ? _services[currentIdx] : current)
          .copyWith(updatedAt: DateTime.now());
      if (currentIdx >= 0) {
        _services[currentIdx] = updatedItem;
      }
      await _saveRegistry();

      final helperReportedWasRunning = (res['was_running'] as bool?) ?? false;
      if (wasRunningBeforeUpdate || helperReportedWasRunning) {
        await bridge.startService(
          id: updatedItem.id,
          binaryName: updatedItem.binaryName,
          args: updatedItem.args,
        );
      }

      await refreshAllStatuses();
      return true;
    } finally {
      _busyServiceIds.remove(serviceId);
      notifyListeners();
    }
  }

  /// 修改服务配置（端口、启动参数、环境变量），保留所有数据
  Future<bool> updateServiceConfig(
    ServiceItem updated, {
    String? rawEnvContent,
  }) async {
    final index = _services.indexWhere((s) => s.id == updated.id);
    if (index < 0) return false;

    final wasRunning = _services[index].status.isRunning;
    _services[index] = updated.copyWith(updatedAt: DateTime.now());
    await _writeEnvFiles(_services[index], rawEnvContent: rawEnvContent);
    await _saveRegistry();

    if (wasRunning) {
      await stopService(updated.id);
      await startService(updated.id);
    } else {
      notifyListeners();
    }
    return true;
  }

  /// 开启服务
  Future<bool> startService(String serviceId) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) return false;
    final item = _services[index];

    _busyServiceIds.add(serviceId);
    _lastError = null;
    notifyListeners();

    try {
      // 启动服务时绝不覆写现有的 .env 文件！仅在完全没有 .env 文件且初始配置非空时初始化
      final workEnv = File('${item.serviceDir(serviceRootPath)}/.env');
      final cfgEnv = File(item.envFilePath(serviceRootPath));
      if (!workEnv.existsSync() &&
          !cfgEnv.existsSync() &&
          item.envVars.isNotEmpty) {
        await _writeEnvFiles(item);
      }

      final res = await bridge.startService(
        id: item.id,
        binaryName: item.binaryName,
        args: item.args,
      );
      final ok = (res['ok'] as bool?) ?? false;
      if (!ok) {
        _lastError = (res['error'] as String?) ?? '启动服务失败';
        return false;
      }
      await refreshAllStatuses();
      return true;
    } finally {
      _busyServiceIds.remove(serviceId);
      notifyListeners();
    }
  }

  /// 关闭服务
  Future<bool> stopService(String serviceId) async {
    _busyServiceIds.add(serviceId);
    _lastError = null;
    notifyListeners();

    try {
      final res = await bridge.stopService(serviceId);
      final ok = (res['ok'] as bool?) ?? false;
      if (!ok) {
        _lastError = (res['error'] as String?) ?? '停止服务失败';
        return false;
      }
      await refreshAllStatuses();
      return true;
    } finally {
      _busyServiceIds.remove(serviceId);
      notifyListeners();
    }
  }

  /// 切换服务开关
  Future<bool> toggleService(String serviceId) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) return false;
    if (_services[index].status.isRunning) {
      return stopService(serviceId);
    } else {
      return startService(serviceId);
    }
  }

  /// 卸载服务
  Future<bool> uninstallService(String serviceId) async {
    _busyServiceIds.add(serviceId);
    notifyListeners();
    try {
      final res = await bridge.uninstallService(serviceId);
      final ok = (res['ok'] as bool?) ?? true;
      if (!ok) {
        _lastError = (res['error'] as String?) ?? '卸载服务失败';
        return false;
      }
      _services.removeWhere((s) => s.id == serviceId);
      await _saveRegistry();
      return true;
    } finally {
      _busyServiceIds.remove(serviceId);
      notifyListeners();
    }
  }

  /// 读取服务运行日志（采用 RandomAccessFile 尾部流式读取 + 容错 UTF-8 解码，防止大日志 OOM 与非 UTF-8 字节崩溃）
  Future<String> readLogs(
    String serviceId, {
    int maxLines = 300,
    int maxBytes = 65536,
  }) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) return '';
    final logFile = File(_services[index].stdoutLogPath(serviceRootPath));
    if (!logFile.existsSync()) {
      return '暂无日志输出（日志文件: ${logFile.path}）';
    }
    RandomAccessFile? raf;
    try {
      raf = await logFile.open(mode: FileMode.read);
      final length = await raf.length();
      if (length <= 0) {
        return '';
      }
      final startOffset = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(startOffset);
      final bytes = await raf.read(length - startOffset);
      final decoded = utf8.decode(bytes, allowMalformed: true);
      var lines = const LineSplitter().convert(decoded);
      if (startOffset > 0 && lines.length > 1) {
        // 丢弃因按字节截断而可能不完整的首行
        lines = lines.sublist(1);
      }
      if (lines.length <= maxLines) {
        return lines.join('\n');
      }
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (e) {
      return '读取日志失败: $e';
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// 清空服务运行日志
  Future<void> clearLogs(String serviceId) async {
    final index = _services.indexWhere((s) => s.id == serviceId);
    if (index < 0) return;
    final logFile = File(_services[index].stdoutLogPath(serviceRootPath));
    if (logFile.existsSync()) {
      await logFile.writeAsString('');
    }
  }
}
