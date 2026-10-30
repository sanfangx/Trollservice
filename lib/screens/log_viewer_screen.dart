import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import '../services/daemon_controller.dart';

class LogViewerScreen extends StatefulWidget {
  final DaemonController controller;
  final ServiceItem service;

  const LogViewerScreen({
    super.key,
    required this.controller,
    required this.service,
  });

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _logContent = '正在加载日志...';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadLogs(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final text = await widget.controller.readLogs(widget.service.id);
    if (mounted && text != _logContent) {
      setState(() {
        _logContent = text;
      });
    }
  }

  Future<void> _clearLogs() async {
    HapticFeedback.mediumImpact();
    await widget.controller.clearLogs(widget.service.id);
    await _loadLogs();
  }

  Future<void> _copyLogs() async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: _logContent));
    if (!mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('已复制'),
        content: const Text('日志内容已复制到剪贴板'),
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
    final logPath =
        widget.service.stdoutLogPath(widget.controller.serviceRootPath);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('${widget.service.name} 运行日志'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _copyLogs,
              child: const Icon(CupertinoIcons.doc_on_doc, size: 20),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _clearLogs,
              child: const Icon(
                CupertinoIcons.trash,
                size: 20,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: CupertinoColors.secondarySystemBackground
                  .resolveFrom(context),
              child: Text(
                '日志文件: $logPath',
                style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFF141619),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: Text(
                    _logContent,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      height: 1.45,
                      color: Color(0xFFE6EDF3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
