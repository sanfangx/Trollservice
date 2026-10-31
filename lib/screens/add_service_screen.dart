import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import '../services/daemon_controller.dart';

class AddServiceScreen extends StatefulWidget {
  final DaemonController controller;

  const AddServiceScreen({super.key, required this.controller});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  ServicePreset _selectedPreset = ServicePreset.builtInPresets.first;

  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _binaryNameCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _argsCtrl;
  late final TextEditingController _envCtrl;
  late final TextEditingController _entsCtrl;
  late final TextEditingController _srcPathCtrl;

  bool _showCustomEnts = false;
  bool _showEnv = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController();
    _nameCtrl = TextEditingController();
    _binaryNameCtrl = TextEditingController();
    _portCtrl = TextEditingController();
    _argsCtrl = TextEditingController();
    _envCtrl = TextEditingController();
    _entsCtrl = TextEditingController();
    _srcPathCtrl = TextEditingController();
    _applyPreset(_selectedPreset);
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _binaryNameCtrl.dispose();
    _portCtrl.dispose();
    _argsCtrl.dispose();
    _envCtrl.dispose();
    _entsCtrl.dispose();
    _srcPathCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(ServicePreset preset) {
    setState(() {
      _selectedPreset = preset;
      _idCtrl.text = preset.defaultId;
      _nameCtrl.text = preset.title;
      _binaryNameCtrl.text = preset.defaultBinaryName;
      _portCtrl.text = preset.defaultPort.toString();
      _argsCtrl.text = preset.defaultArgs.join(' ');
      _envCtrl.text = preset.defaultEnv.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n');
      _entsCtrl.text =
          ServiceItem.generateServiceEntitlementsXml(preset.defaultId);
    });
  }

  void _resetDefaultEntitlements() {
    final id = _idCtrl.text.trim().isEmpty
        ? _selectedPreset.defaultId
        : _idCtrl.text.trim();
    setState(() {
      _entsCtrl.text = ServiceItem.generateServiceEntitlementsXml(id);
    });
    HapticFeedback.selectionClick();
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
        _showAlert('读取 entitlements 文件失败: $e');
      }
    }
  }

  Future<void> _pickFile() async {
    HapticFeedback.selectionClick();
    final path = await widget.controller.bridge.pickBinaryFile();
    if (path != null && path.isNotEmpty && mounted) {
      setState(() {
        _srcPathCtrl.text = path;
      });
    }
  }

  Future<void> _handleInstall() async {
    final id = _idCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final binName = _binaryNameCtrl.text.trim();
    final srcPath = _srcPathCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 0;

    if (id.isEmpty || name.isEmpty || binName.isEmpty || srcPath.isEmpty) {
      _showAlert('请填写完整的服务标识、名称、可执行文件名及源文件路径');
      return;
    }

    setState(() => _installing = true);
    HapticFeedback.mediumImpact();

    final argsList = _argsCtrl.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final envMap = ServiceItem.parseDotEnv(_envCtrl.text);

    final item = ServiceItem(
      id: id,
      name: name,
      binaryName: binName,
      port: port,
      args: argsList,
      envVars: envMap,
    );

    final customEnts = _entsCtrl.text.trim();

    final ok = await widget.controller.installService(
      item: item,
      srcBinaryPath: srcPath,
      customEntitlementsXml: customEnts.isNotEmpty ? customEnts : null,
    );

    if (!mounted) return;
    setState(() => _installing = false);

    if (ok) {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(true);
    } else {
      _showAlert(widget.controller.lastError ?? '安装与签名赋权失败');
    }
  }

  void _showAlert(String message) {
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
    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        middle: const Text('安装新服务'),
        trailing: _installing
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _handleInstall,
                child: const Text(
                  '完成',
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
              header: const Text('快速预设模板'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ServicePreset.builtInPresets.map((preset) {
                      final selected = preset.key == _selectedPreset.key;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _applyPreset(preset);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? CupertinoColors.activeBlue
                                : CupertinoColors.tertiarySystemFill
                                    .resolveFrom(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            preset.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? CupertinoColors.white
                                  : CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('程序文件'),
              children: [
                CupertinoListTile(
                  title: const Text('可执行文件 (ARM64)'),
                  subtitle: Text(
                    _srcPathCtrl.text.isEmpty
                        ? '请选择待安装的 Mach-O 文件'
                        : _srcPathCtrl.text,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: _srcPathCtrl.text.isEmpty ? null : 'Courier',
                    ),
                  ),
                  trailing: CupertinoButton.filled(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: _pickFile,
                    child: const Text('浏览', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('基本参数'),
              children: [
                _buildFieldTile('服务标识', _idCtrl, '如 aistudio2api'),
                _buildFieldTile('显示名称', _nameCtrl, '如 AIStudio2API'),
                _buildFieldTile('可执行文件名', _binaryNameCtrl, '如 aistudio2api'),
                _buildFieldTile(
                  '监听端口',
                  _portCtrl,
                  '如 2048 (0 表示无端口)',
                  keyboardType: TextInputType.number,
                ),
                _buildFieldTile('启动命令行参数', _argsCtrl, '如 -open-ui=false'),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('高级配置 (可选)'),
              children: [
                CupertinoListTile(
                  title: const Text('环境变量 (.env)'),
                  subtitle: Text(
                    _envCtrl.text.trim().isEmpty ? '默认留空' : '已配置环境变量',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Icon(
                    _showEnv
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                  onTap: () => setState(() => _showEnv = !_showEnv),
                ),
                if (_showEnv)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: CupertinoTextField(
                      controller: _envCtrl,
                      maxLines: 5,
                      placeholder: '# 环境变量（可选，按需填写）\n# 如: LISTEN_ADDR=0.0.0.0:2048',
                      padding: const EdgeInsets.all(10),
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 12,
                      ),
                    ),
                  ),
                CupertinoListTile(
                  title: const Text('签名权限 (Entitlements)'),
                  subtitle: const Text(
                    '已注入免沙盒与防 Jetsam 强杀权限',
                    style: TextStyle(fontSize: 12),
                  ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                '恢复默认',
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
                          maxLines: 8,
                          padding: const EdgeInsets.all(10),
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton.filled(
                onPressed: _installing ? null : _handleInstall,
                child: Text(_installing ? '正在安装并签名...' : '完成安装'),
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldTile(
    String label,
    TextEditingController controller,
    String placeholder, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return CupertinoListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 170,
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          keyboardType: keyboardType,
          textAlign: TextAlign.end,
          decoration: null,
          style: const TextStyle(fontSize: 14),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }
}
