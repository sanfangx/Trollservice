import 'dart:convert';

/// 默认服务安装根目录（TrollStore 免沙盒持久化路径）
const String kDefaultServiceRoot = '/var/mobile/Documents/service';

/// 实时运行状态快照
class ServiceRuntimeStatus {
  final bool isRunning;
  final bool isPortOpen;
  final int pid;
  final int memoryBytes;
  final int uptimeSeconds;

  const ServiceRuntimeStatus({
    this.isRunning = false,
    this.isPortOpen = false,
    this.pid = 0,
    this.memoryBytes = 0,
    this.uptimeSeconds = 0,
  });

  ServiceRuntimeStatus copyWith({
    bool? isRunning,
    bool? isPortOpen,
    int? pid,
    int? memoryBytes,
    int? uptimeSeconds,
  }) {
    return ServiceRuntimeStatus(
      isRunning: isRunning ?? this.isRunning,
      isPortOpen: isPortOpen ?? this.isPortOpen,
      pid: pid ?? this.pid,
      memoryBytes: memoryBytes ?? this.memoryBytes,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
    );
  }

  /// 格式化物理内存为易读的 MB 字符串
  String get formattedMemory {
    if (!isRunning || memoryBytes <= 0) return '-';
    final mb = memoryBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 格式化持续运行时长
  String get formattedUptime {
    if (!isRunning || uptimeSeconds <= 0) return '-';
    final days = uptimeSeconds ~/ 86400;
    final hours = (uptimeSeconds % 86400) ~/ 3600;
    final minutes = (uptimeSeconds % 3600) ~/ 60;
    final seconds = uptimeSeconds % 60;
    if (days > 0) {
      return '$days天 $hours小时';
    } else if (hours > 0) {
      return '$hours小时 $minutes分';
    } else if (minutes > 0) {
      return '$minutes分 $seconds秒';
    }
    return '$seconds秒';
  }
}

/// 预设模板定义
class ServicePreset {
  final String key;
  final String title;
  final String subtitle;
  final String defaultId;
  final String defaultBinaryName;
  final int defaultPort;
  final List<String> defaultArgs;
  final Map<String, String> defaultEnv;

  const ServicePreset({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.defaultId,
    required this.defaultBinaryName,
    required this.defaultPort,
    required this.defaultArgs,
    required this.defaultEnv,
  });

  static const List<ServicePreset> builtInPresets = [
    ServicePreset(
      key: 'aistudio2api',
      title: 'AIStudio2API',
      subtitle: 'Google AI Studio 转 OpenAI / Claude / Gemini API（内置无浏览器 WAA）',
      defaultId: 'aistudio2api',
      defaultBinaryName: 'aistudio2api',
      defaultPort: 2048,
      defaultArgs: ['-open-ui=false'],
      defaultEnv: {},
    ),
    ServicePreset(
      key: 'alist',
      title: 'Alist 网盘聚合',
      subtitle: '多网盘挂载与本地 WebDAV 服务',
      defaultId: 'alist',
      defaultBinaryName: 'alist',
      defaultPort: 5244,
      defaultArgs: ['server'],
      defaultEnv: {},
    ),
    ServicePreset(
      key: 'singbox',
      title: 'Sing-Box 核心',
      subtitle: '通用代理路由网关与 Clash API 面板',
      defaultId: 'sing-box',
      defaultBinaryName: 'sing-box',
      defaultPort: 9090,
      defaultArgs: ['run', '-c', 'config.json'],
      defaultEnv: {},
    ),
    ServicePreset(
      key: 'cloudflared',
      title: 'Cloudflared 穿透',
      subtitle: 'Cloudflare Tunnel 免公网 IP 暴露内网服务',
      defaultId: 'cloudflared',
      defaultBinaryName: 'cloudflared',
      defaultPort: 0,
      defaultArgs: ['tunnel', 'run'],
      defaultEnv: {},
    ),
    ServicePreset(
      key: 'custom',
      title: '自定义程序',
      subtitle: '任意编译为 iOS/Darwin ARM64 的单二进制服务',
      defaultId: 'custom_service',
      defaultBinaryName: 'service_bin',
      defaultPort: 8080,
      defaultArgs: [],
      defaultEnv: {},
    ),
  ];
}

/// 受管微服务配置与状态模型
class ServiceItem {
  final String id;
  final String name;
  final String binaryName;
  final int port;
  final List<String> args;
  final Map<String, String> envVars;
  final DateTime installedAt;
  final DateTime updatedAt;
  final ServiceRuntimeStatus status;

  ServiceItem({
    required this.id,
    required this.name,
    required this.binaryName,
    required this.port,
    this.args = const [],
    this.envVars = const {},
    DateTime? installedAt,
    DateTime? updatedAt,
    this.status = const ServiceRuntimeStatus(),
  })  : installedAt = installedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 服务安装目录（例如 /var/mobile/Documents/service/aistudio2api）
  String serviceDir([String root = kDefaultServiceRoot]) => '$root/$id';

  /// 可执行文件路径（例如 /var/mobile/Documents/service/aistudio2api/bin/aistudio2api）
  String binaryPath([String root = kDefaultServiceRoot]) =>
      '${serviceDir(root)}/bin/$binaryName';

  /// 配置目录（更新二进制时完好保留）
  String configDir([String root = kDefaultServiceRoot]) =>
      '${serviceDir(root)}/config';

  /// .env 文件路径（更新二进制时完好保留）
  String envFilePath([String root = kDefaultServiceRoot]) =>
      '${configDir(root)}/.env';

  /// entitlements.plist 路径
  String entitlementsFilePath([String root = kDefaultServiceRoot]) =>
      '${configDir(root)}/entitlements.plist';

  /// 运行时数据与日志目录（更新二进制时完好保留）
  String runtimeDir([String root = kDefaultServiceRoot]) =>
      '${serviceDir(root)}/runtime';

  /// 标准输出日志路径
  String stdoutLogPath([String root = kDefaultServiceRoot]) =>
      '${runtimeDir(root)}/stdout.log';

  ServiceItem copyWith({
    String? id,
    String? name,
    String? binaryName,
    int? port,
    List<String>? args,
    Map<String, String>? envVars,
    DateTime? installedAt,
    DateTime? updatedAt,
    ServiceRuntimeStatus? status,
  }) {
    return ServiceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      binaryName: binaryName ?? this.binaryName,
      port: port ?? this.port,
      args: args ?? this.args,
      envVars: envVars ?? this.envVars,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'binaryName': binaryName,
      'port': port,
      'args': args,
      'envVars': envVars,
      'installedAt': installedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    final rawArgs = (json['args'] as List<dynamic>?) ?? const [];
    final rawEnv = (json['envVars'] as Map<String, dynamic>?) ?? const {};
    return ServiceItem(
      id: (json['id'] as String?) ?? 'unknown',
      name: (json['name'] as String?) ?? '未命名服务',
      binaryName: (json['binaryName'] as String?) ?? 'binary',
      port: (json['port'] as num?)?.toInt() ?? 0,
      args: rawArgs.map((e) => e.toString()).toList(),
      envVars: rawEnv.map((k, v) => MapEntry(k, v.toString())),
      installedAt: DateTime.tryParse((json['installedAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// 将环境变量键值对序列化为标准 .env 文件内容
  static String formatDotEnv(Map<String, String> envVars) {
    final buffer = StringBuffer();
    buffer.writeln('# Generated by TrollService');
    for (final entry in envVars.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      final value = entry.value.replaceAll('\n', '');
      buffer.writeln('$key=$value');
    }
    return buffer.toString();
  }

  /// 解析 .env 文件文本为键值对映射
  static Map<String, String> parseDotEnv(String content) {
    final result = <String, String>{};
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  /// 生成受管微服务的专属 Entitlements Plist（严格遵循 TrollStore 规则，不含任何 Banned Keys）
  static String generateServiceEntitlementsXml(String serviceId) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>application-identifier</key>
\t<string>com.magicfall.trollservice.svc.$serviceId</string>
\t<key>com.apple.developer.team-identifier</key>
\t<string>TROLLSTORE</string>
\t<key>platform-application</key>
\t<true/>
\t<key>com.apple.private.security.container-required</key>
\t<false/>
\t<key>com.apple.private.security.no-sandbox</key>
\t<true/>
\t<key>com.apple.private.security.storage.AppDataContainers</key>
\t<true/>
\t<key>com.apple.security.exception.files.absolute-path.read-write</key>
\t<array>
\t\t<string>/</string>
\t</array>
\t<key>com.apple.multitasking.unlimitedassertions</key>
\t<true/>
\t<key>com.apple.multitasking.systemappassertions</key>
\t<true/>
\t<key>com.apple.private.kernel.jetsam</key>
\t<true/>
\t<key>com.apple.private.memorystatus</key>
\t<true/>
\t<key>com.apple.private.network.socket-delegate</key>
\t<true/>
</dict>
</plist>
''';
  }
}
