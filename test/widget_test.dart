import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:troll_service/main.dart';
import 'package:troll_service/models/service_item.dart';
import 'package:troll_service/services/daemon_controller.dart';
import 'package:troll_service/services/native_bridge.dart';

void main() {
  group('TrollService 核心路径、签名赋权与更新保留数据测试', () {
    late Directory tempRoot;
    late FileSystemMockServiceBridge mockBridge;
    late DaemonController controller;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('troll_service_test_');
      mockBridge = FileSystemMockServiceBridge(
        serviceRootPath: '${tempRoot.path}/var/mobile/Documents/service',
      );
      controller = DaemonController(bridge: mockBridge);
      await controller.initialize(enablePolling: false);
    });

    tearDown(() {
      controller.dispose();
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('1. 默认安装根路径严格为 /var/mobile/Documents/service', () {
      const defaultBridge = MethodChannelServiceBridge();
      expect(defaultBridge.serviceRootPath, equals('/var/mobile/Documents/service'));

      final item = ServiceItem(
        id: 'aistudio2api',
        name: 'AIStudio2API',
        binaryName: 'aistudio2api',
        port: 2048,
      );
      expect(
        item.serviceDir(),
        equals('/var/mobile/Documents/service/aistudio2api'),
      );
      expect(
        item.binaryPath(),
        equals('/var/mobile/Documents/service/aistudio2api/bin/aistudio2api'),
      );
      expect(
        item.envFilePath(),
        equals('/var/mobile/Documents/service/aistudio2api/config/.env'),
      );
    });

    test('2. 生成的 Entitlements.plist 包含必需免沙盒/防强杀权限且绝不含禁用键', () {
      final xml = ServiceItem.generateServiceEntitlementsXml('aistudio2api');
      expect(xml, contains('<key>platform-application</key>'));
      expect(xml, contains('<key>com.apple.private.security.no-sandbox</key>'));
      expect(xml, contains('<key>com.apple.multitasking.unlimitedassertions</key>'));
      expect(xml, contains('<key>com.apple.private.kernel.jetsam</key>'));
      expect(xml, contains('<key>com.apple.private.memorystatus</key>'));

      // 绝不能包含会导致崩溃或强制要求开发者模式的 Banned Keys
      expect(xml, isNot(contains('com.apple.private.cs.debugger')));
      expect(xml, isNot(contains('dynamic-codesigning')));
      expect(xml, isNot(contains('com.apple.private.skip-library-validation')));
      expect(xml, isNot(contains('get-task-allow')));
      expect(xml, isNot(contains('task_for_pid-allow')));
    });

    test('3. 安装与更新程序：更新时替换二进制并重签名，100% 保留原有程序数据', () async {
      // 准备 v1 二进制
      final v1Bin = File('${tempRoot.path}/aistudio2api_v1');
      v1Bin.writeAsStringSync('MACH_O_ARM64_BINARY_V1');

      final item = ServiceItem(
        id: 'aistudio2api',
        name: 'AIStudio2API',
        binaryName: 'aistudio2api',
        port: 2048,
        args: const ['-open-ui=false'],
        envVars: const {
          'LISTEN_ADDR': '0.0.0.0:2048',
          'WAA_BACKEND': 'spidermonkey',
        },
      );

      // 1) 首次安装并赋权签名
      final installed = await controller.installService(
        item: item,
        srcBinaryPath: v1Bin.path,
      );
      expect(installed, isTrue);
      expect(controller.services.length, equals(1));
      expect(
        mockBridge.executedSignCommands.any((c) => c.startsWith('ldid -S')),
        isTrue,
      );
      expect(
        mockBridge.executedSignCommands.any((c) => c.startsWith('fastPathSign ')),
        isTrue,
      );

      // 2) 开启服务
      final started = await controller.startService('aistudio2api');
      expect(started, isTrue);
      expect(controller.services.first.status.isRunning, isTrue);

      // 3) 模拟程序运行期间产生的重要数据文件（账户凭证、SQLite 数据库、自定义配置）
      final svcDir = item.serviceDir(controller.serviceRootPath);
      final accountFile = File('$svcDir/accounts/storage-state.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"cookies":[{"name":"SID","value":"SECRET_TOKEN"}]}');
      final dbFile = File('$svcDir/runtime/requests.db')
        ..createSync(recursive: true)
        ..writeAsStringSync('SQLITE_REQUEST_LEDGER_DATA_12345');

      mockBridge.executedSignCommands.clear();

      // 4) 准备 v2 新版二进制并执行“更新程序”
      final v2Bin = File('${tempRoot.path}/aistudio2api_v2');
      v2Bin.writeAsStringSync('MACH_O_ARM64_BINARY_V2_UPGRADED');

      final updated = await controller.updateServiceBinary(
        serviceId: 'aistudio2api',
        newBinaryPath: v2Bin.path,
      );
      expect(updated, isTrue);

      // 5) 验证二进制已更新为 v2 且重新执行了 ldid -S 与 fastPathSign
      final installedBin = File(item.binaryPath(controller.serviceRootPath));
      expect(installedBin.readAsStringSync(), equals('MACH_O_ARM64_BINARY_V2_UPGRADED'));
      expect(
        mockBridge.executedSignCommands.any((c) => c.startsWith('ldid -S')),
        isTrue,
      );
      expect(
        mockBridge.executedSignCommands.any((c) => c.startsWith('fastPathSign ')),
        isTrue,
      );

      // 6) 核心断言：所有程序数据（账户凭证、数据库、.env 配置）100% 完好无损！
      expect(accountFile.existsSync(), isTrue);
      expect(
        accountFile.readAsStringSync(),
        equals('{"cookies":[{"name":"SID","value":"SECRET_TOKEN"}]}'),
      );
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.readAsStringSync(), equals('SQLITE_REQUEST_LEDGER_DATA_12345'));

      final envFile = File(item.envFilePath(controller.serviceRootPath));
      expect(envFile.existsSync(), isTrue);
      expect(envFile.readAsStringSync(), contains('WAA_BACKEND=spidermonkey'));

      // 7) 验证更新前正在运行的服务在更新后已自动恢复运行
      expect(controller.services.first.status.isRunning, isTrue);
    });

    testWidgets('4. UI 仪表盘展示默认路径、服务卡片与状态开关', (WidgetTester tester) async {
      final v1Bin = File('${tempRoot.path}/aistudio2api_bin')
        ..writeAsStringSync('MACH_O_ARM64');

      await controller.installService(
        item: ServiceItem(
          id: 'aistudio2api',
          name: 'AIStudio2API',
          binaryName: 'aistudio2api',
          port: 2048,
        ),
        srcBinaryPath: v1Bin.path,
      );

      await tester.pumpWidget(TrollServiceApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('TrollService 服务管理'), findsOneWidget);
      expect(find.text('AIStudio2API'), findsOneWidget);
      expect(find.text('已停止'), findsOneWidget);
      expect(find.text('更新 / 配置'), findsOneWidget);
    });

    test('5. AIStudio2API 预设 defaultEnv 默认为空', () {
      final aistudioPreset = ServicePreset.builtInPresets.firstWhere(
        (p) => p.defaultId == 'aistudio2api',
      );
      expect(aistudioPreset.defaultEnv, isEmpty);
    });

    test('6. 启动服务绝不覆写已存在的 .env 文件', () async {
      final v1Bin = File('${tempRoot.path}/dummy_bin')
        ..writeAsStringSync('BIN');
      final item = ServiceItem(
        id: 'env_test_service',
        name: 'EnvTest',
        binaryName: 'env_test',
        port: 8080,
        envVars: const {'INITIAL_KEY': 'INITIAL_VAL'},
      );

      await controller.installService(
        item: item,
        srcBinaryPath: v1Bin.path,
      );

      // 模拟用户在 Filza 或终端手动修改工作目录下的 .env 文件
      final workEnv =
          File('${item.serviceDir(controller.serviceRootPath)}/.env');
      expect(workEnv.existsSync(), isTrue);
      workEnv.writeAsStringSync(
        'CUSTOM_USER_KEY=CUSTOM_VALUE\nWAA_BACKEND=go\n# Custom comment\n',
      );

      // 多次启动和停止服务
      await controller.startService(item.id);
      expect(
        workEnv.readAsStringSync(),
        equals(
          'CUSTOM_USER_KEY=CUSTOM_VALUE\nWAA_BACKEND=go\n# Custom comment\n',
        ),
      );

      await controller.stopService(item.id);
      await controller.startService(item.id);
      // 依然 100% 保持用户定制的内容，绝不回滚/覆写
      expect(
        workEnv.readAsStringSync(),
        equals(
          'CUSTOM_USER_KEY=CUSTOM_VALUE\nWAA_BACKEND=go\n# Custom comment\n',
        ),
      );
    });

    test('7. 安装与更新支持自定义 Entitlements XML', () async {
      final v1Bin = File('${tempRoot.path}/ents_bin')
        ..writeAsStringSync('BIN_V1');
      const customEntsXmlInstall = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>custom.install.entitlement</key>
    <true/>
</dict>
</plist>''';

      final item = ServiceItem(
        id: 'custom_ents_svc',
        name: 'CustomEntsSvc',
        binaryName: 'custom_ents',
        port: 9000,
      );

      // 1) 安装时带自定义 entitlements
      final installOk = await controller.installService(
        item: item,
        srcBinaryPath: v1Bin.path,
        customEntitlementsXml: customEntsXmlInstall,
      );
      expect(installOk, isTrue);

      final entsFile =
          File(item.entitlementsFilePath(controller.serviceRootPath));
      expect(entsFile.existsSync(), isTrue);
      expect(
        entsFile.readAsStringSync(),
        contains('<key>custom.install.entitlement</key>'),
      );

      // 2) 更新时带新的自定义 entitlements
      final v2Bin = File('${tempRoot.path}/ents_bin_v2')
        ..writeAsStringSync('BIN_V2');
      const customEntsXmlUpdate = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>custom.update.entitlement.v2</key>
    <string>enabled</string>
</dict>
</plist>''';

      final updateOk = await controller.updateServiceBinary(
        serviceId: item.id,
        newBinaryPath: v2Bin.path,
        customEntitlementsXml: customEntsXmlUpdate,
      );
      expect(updateOk, isTrue);

      expect(
        entsFile.readAsStringSync(),
        contains('<key>custom.update.entitlement.v2</key>'),
      );
      expect(
        entsFile.readAsStringSync(),
        contains('<string>enabled</string>'),
      );
    });
  });
}
