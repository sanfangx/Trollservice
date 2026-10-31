import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import '../services/daemon_controller.dart';

class ServiceDetailScreen extends StatefulWidget {
  final DaemonController controller;
  final ServiceItem service;

  const ServiceDetailScreen({
    super.key,
    required this.controller,
    required this.service,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _argsCtrl;
  late final TextEditingController _envCtrl;
  late final TextEditingController _entsCtrl;
  late final TextEditingController _updateSrcPathCtrl;

  bool _showCustomEnts = false;
  bool _updatingBinary = false;
  bool _savingConfig = false;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s.name);
    _portCtrl = TextEditingController(text: s.port.toString());
    _argsCtrl = TextEditingController(text: s.args.join(' '));
    _envCtrl = TextEditingController(
      text: s.envVars.entries.map((e) => '${e.key}=${e.value}').join('\n'),
    );
    _entsCtrl = TextEditingController(
      text: ServiceItem.generateServiceEntitlementsXml(s.id),
    );
    _updateSrcPathCtrl = TextEditingController();

    _loadDiskConfig();
  }

  Future<void> _loadDiskConfig() async {
    final envRaw = await widget.controller.readServiceEnvRaw(widget.service.id);
    final entsRaw =
        await widget.controller.readServiceEntitlementsRaw(widget.service.id);
    if (mounted) {
      setState(() {
        if (envRaw.isNotEmpty) {
          _envCtrl.text = envRaw;
        }
        if (entsRaw.isNotEmpty) {
          _entsCtrl.text = entsRaw;
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _portCtrl.dispose();
    _argsCtrl.dispose();
    _envCtrl.dispose();
    _entsCtrl.dispose();
    _updateSrcPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickUpdateBinary() async {
    HapticFeedback.selectionClick();
    final path = await widget.controller.bridge.pickBinaryFile();
    if (path != null && path.isNotEmpty && mounted) {
      setState(() {
        _updateSrcPathCtrl.text = path;
      });
    }
  }

  Future<void> _pickEntitlementsFile() async {
    HapticFeedback.selectionClick();
    final path = await widget.controller.bridge.pickBinaryFile();
    if (path != null && path.isNotEmpty && mounted) {
      try {
        final content = File(path).readAsStringSync();
        setState(() {
          _entsCtrl.text = content;
          _showCustomEnts = true;
        });
      } catch (e) {
        _showMessage('读取 entitlements 文件失败: $e');
      }
    }
  }

  void _resetDefaultEntitlements() {
    setState(() {
      _entsCtrl.text =
          ServiceItem.generateServiceEntitlementsXml(widget.service.id);
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _handleUpdateBinary() async {
    final newPath = _updateSrcPathCtrl.text.trim();
    if (newPath.isEmpty) {
      _showMessage('请先选择或输入新版程序文件路径');
      return;
    }

    setState(() => _updatingBinary = true);
    HapticFeedback.mediumImpact();

    final customEnts = _entsCtrl.text.trim();
    final ok = await widget.controller.updateServiceBinary(
      serviceId: widget.service.id,
      newBinaryPath: newPath,
      customEntitlementsXml: customEnts.isNotEmpty ? customEnts : null,
    );

    if (!mounted) return;
    setState(() => _updatingBinary = false);

    if (ok) {
      HapticFeedback.heavyImpact();
      _showMessage('程序已成功更新并重新签名赋权，数据完好保留。');
    } else {
      _showMessage(widget.controller.lastError ?? '更新程序失败');
    }
  }

  Future<void> _handleSaveConfig() async {
    setState(() => _savingConfig = true);
    HapticFeedback.lightImpact();

    final port = int.tryParse(_portCtrl.text.trim()) ?? widget.service.port;
    final args = _argsCtrl.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final envMap = ServiceItem.parseDotEnv(_envCtrl.text);

    final updated = widget.service.copyWith(
      name: _nameCtrl.text.trim().isEmpty
          ? widget.service.name
          : _nameCtrl.text.trim(),
      port: port,
      args: args,
      envVars: envMap,
    );

    await widget.controller.updateServiceConfig(
      updated,
      rawEnvContent: _envCtrl.text,
    );
    if (!mounted) return;
    setState(() => _savingConfig = false);
    Navigator.of(context).pop(true);
  }

  void _confirmUninstall() {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('确认卸载 ${widget.service.name}？'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '将停止服务并清理目录:\n${widget.service.serviceDir(widget.controller.serviceRootPath)}',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.controller.uninstallService(widget.service.id);
              if (mounted) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('确认卸载'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.controller.serviceRootPath;
    final dataDir = widget.service.serviceDir(root);
    final status = widget.service.status;

    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.service.name),
        trailing: _savingConfig
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _handleSaveConfig,
                child: const Text(
                  '保存',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
      ),
      child: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('服务信息'),
              children: [
                CupertinoListTile(
                  title: const Text('运行状态'),
                  additionalInfo: Text(
                    status.isRunning ? '正在运行 (PID: ${status.pid})' : '已停止',
                    style: TextStyle(
                      color: status.isRunning
                          ? CupertinoColors.activeGreen
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
                CupertinoListTile(
                  title: const Text('工作目录'),
                  subtitle: Text(
                    dataDir,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier',
                    ),
                  ),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(text: dataDir));
                    _showMessage('工作目录路径已复制到剪贴板:\n$dataDir');
                  },
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('版本更新 (自动保留数据)'),
              children: [
                CupertinoListTile(
                  title: const Text('新版二进制文件'),
                  subtitle: Text(
                    _updateSrcPathCtrl.text.isEmpty
                        ? '请选择新版 Mach-O 文件'
                        : _updateSrcPathCtrl.text,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily:
                          _updateSrcPathCtrl.text.isEmpty ? null : 'Courier',
                    ),
                  ),
                  trailing: CupertinoButton.filled(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: _pickUpdateBinary,
                    child: const Text('浏览', style: TextStyle(fontSize: 13)),
                  ),
                ),
                CupertinoListTile(
                  title: const Text('自定义更新权限 (可选)'),
                  trailing: Icon(
                    _showCustomEnts
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                  onTap: () =>
                      setState(() => _showCustomEnts = !_showCustomEnts),
                ),
                if (_showCustomEnts)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              color: CupertinoColors.tertiarySystemFill
                                  .resolveFrom(context),
                              onPressed: _pickEntitlementsFile,
                              child: Text(
                                '导入 .plist',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.label
                                      .resolveFrom(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              color: CupertinoColors.tertiarySystemFill
                                  .resolveFrom(context),
                              onPressed: _resetDefaultEntitlements,
                              child: Text(
                                '重置默认',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.label
                                      .resolveFrom(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: _entsCtrl,
                          maxLines: 6,
                          padding: const EdgeInsets.all(10),
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onPressed: _updatingBinary ? null : _handleUpdateBinary,
                      child: Text(
                        _updatingBinary ? '正在更新与签名...' : '更新程序',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('运行参数与环境变量'),
              children: [
                _buildFieldTile('显示名称', _nameCtrl),
                _buildFieldTile(
                  '监听端口',
                  _portCtrl,
                  keyboardType: TextInputType.number,
                ),
                _buildFieldTile('启动命令行参数', _argsCtrl),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '环境变量 (.env)',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      CupertinoTextField(
                        controller: _envCtrl,
                        maxLines: 5,
                        padding: const EdgeInsets.all(10),
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: const Center(
                    child: Text(
                      '卸载此服务并清除数据',
                      style: TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: _confirmUninstall,
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldTile(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return CupertinoListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 170,
        child: CupertinoTextField(
          controller: controller,
          keyboardType: keyboardType,
          textAlign: TextAlign.end,
          decoration: null,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
