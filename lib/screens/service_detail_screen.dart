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
      _showMessage('程序已成功更新并重新完成 ldid + fastPathSign 签名赋权，所有原有程序数据均已完整保留！');
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
            '卸载将停止该服务并删除目录:\n'
            '${widget.service.serviceDir(widget.controller.serviceRootPath)}\n'
            '如果您只想升级版本并保留数据，请使用上方的「更新程序」功能。',
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
    final binPath = widget.service.binaryPath(root);
    final dataDir = widget.service.serviceDir(root);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('${widget.service.name} 更新与配置'),
        trailing: _savingConfig
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _handleSaveConfig,
                child: const Text(
                  '保存配置',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
      ),
      child: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground
                    .resolveFrom(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        CupertinoIcons.arrow_2_circlepath_circle_fill,
                        color: CupertinoColors.activeBlue,
                        size: 20,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '更新程序（保留全部程序数据）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '仅替换可执行文件 ($binPath) 并重新执行 ldid -S 赋权与 fastPathSign 签名；'
                    '工作目录 ($dataDir) 下的数据库、账户凭证、配置文件将 100% 原样保留。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _updateSrcPathCtrl,
                          placeholder: '选择或输入新版二进制文件路径',
                          padding: const EdgeInsets.all(10),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        color: CupertinoColors.tertiarySystemFill
                            .resolveFrom(context),
                        onPressed: _pickUpdateBinary,
                        child: Text(
                          '浏览文件',
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '自定义更新权限 (Entitlements)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() => _showCustomEnts = !_showCustomEnts);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _showCustomEnts ? '收起配置' : '展开自定义',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Icon(
                              _showCustomEnts
                                  ? CupertinoIcons.chevron_up
                                  : CupertinoIcons.chevron_down,
                              size: 13,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_showCustomEnts) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          color: CupertinoColors.tertiarySystemFill
                              .resolveFrom(context),
                          onPressed: _pickEntitlementsFile,
                          child: Text(
                            '导入 .plist 文件',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          color: CupertinoColors.tertiarySystemFill
                              .resolveFrom(context),
                          onPressed: _resetDefaultEntitlements,
                          child: Text(
                            '重置默认权限',
                            style: TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _entsCtrl,
                      maxLines: 8,
                      placeholder: 'XML 格式的 Entitlements',
                      padding: const EdgeInsets.all(10),
                      style: const TextStyle(fontFamily: 'Courier', fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      onPressed: _updatingBinary ? null : _handleUpdateBinary,
                      child: Text(
                        _updatingBinary
                            ? '正在替换并重签名...'
                            : '立即更新程序（保留全部数据）',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '运行参数与环境变量配置',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _buildField('显示名称', _nameCtrl),
            const SizedBox(height: 10),
            _buildField(
              '监听端口',
              _portCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            _buildField('启动命令行参数', _argsCtrl),
            const SizedBox(height: 14),
            Text(
              '环境变量 (.env)',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 6),
            CupertinoTextField(
              controller: _envCtrl,
              maxLines: 6,
              padding: const EdgeInsets.all(12),
              style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
            ),
            const SizedBox(height: 28),
            CupertinoButton(
              color: CupertinoColors.destructiveRed.withValues(alpha: 0.12),
              onPressed: _confirmUninstall,
              child: const Text(
                '卸载此服务并清除目录',
                style: TextStyle(
                  color: CupertinoColors.destructiveRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 4),
        CupertinoTextField(
          controller: controller,
          keyboardType: keyboardType,
          padding: const EdgeInsets.all(11),
        ),
      ],
    );
  }
}
