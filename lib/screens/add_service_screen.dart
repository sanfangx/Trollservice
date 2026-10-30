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
  late final TextEditingController _srcPathCtrl;

  bool _keepAlive = true;
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
    });
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
      keepAlive: _keepAlive,
    );

    final ok = await widget.controller.installService(
      item: item,
      srcBinaryPath: srcPath,
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
    final targetInstallDir =
        '${widget.controller.serviceRootPath}/${_idCtrl.text.trim()}';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('安装并赋权新程序'),
        trailing: _installing
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _handleInstall,
                child: const Text(
                  '完成安装',
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
            _buildSectionTitle('1. 快速预设模板'),
            const SizedBox(height: 8),
            Wrap(
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
                      horizontal: 12,
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
            const SizedBox(height: 6),
            Text(
              _selectedPreset.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('2. 选择待安装的 ARM64 程序文件'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CupertinoTextField(
                    controller: _srcPathCtrl,
                    placeholder: '源程序文件路径 (例如 /var/mobile/Downloads/...)',
                    padding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  onPressed: _pickFile,
                  child: const Text('选择文件', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground
                    .resolveFrom(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '目标安装目录: $targetInstallDir\n'
                '安装时自动执行:\n'
                '① ldid -S 注入免沙盒 (no-sandbox) 与防 Jetsam 强杀权限\n'
                '② fastPathSign 注入 CoreTrust 根证书绕过签名',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('3. 服务基本参数'),
            const SizedBox(height: 8),
            _buildLabeledField('服务目录标识 (ID)', _idCtrl, '如 aistudio2api'),
            const SizedBox(height: 10),
            _buildLabeledField('显示名称', _nameCtrl, '如 AIStudio2API'),
            const SizedBox(height: 10),
            _buildLabeledField('可执行文件名', _binaryNameCtrl, '如 aistudio2api'),
            const SizedBox(height: 10),
            _buildLabeledField(
              '监听端口 (0 表示无端口)',
              _portCtrl,
              '如 2048',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            _buildLabeledField(
              '启动命令行参数',
              _argsCtrl,
              '如 -open-ui=false',
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('崩溃后自动重启保活 (KeepAlive)', style: TextStyle(fontSize: 14)),
                CupertinoSwitch(
                  value: _keepAlive,
                  onChanged: (val) => setState(() => _keepAlive = val),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('4. 环境变量 (.env 每行一个 KEY=VALUE)'),
            const SizedBox(height: 8),
            CupertinoTextField(
              controller: _envCtrl,
              maxLines: 6,
              placeholder: 'LISTEN_ADDR=0.0.0.0:2048\nWAA_BACKEND=spidermonkey',
              padding: const EdgeInsets.all(12),
              style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _installing ? null : _handleInstall,
                child: Text(_installing ? '正在签名与赋权...' : '立即安装并自动签名赋权'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildLabeledField(
    String label,
    TextEditingController controller,
    String placeholder, {
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
          placeholder: placeholder,
          keyboardType: keyboardType,
          padding: const EdgeInsets.all(11),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
