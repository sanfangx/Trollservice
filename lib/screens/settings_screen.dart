import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import '../services/daemon_controller.dart';

class SettingsScreen extends StatefulWidget {
  final DaemonController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _changeRootPath() async {
    HapticFeedback.selectionClick();
    final editCtrl = TextEditingController(
      text: widget.controller.serviceRootPath,
    );

    final newPath = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('自定义服务安装根路径'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '修改后，所有新安装及受管服务的数据均存放在此目录下。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: editCtrl,
                placeholder: kDefaultServiceRoot,
                style: const TextStyle(fontSize: 13, fontFamily: 'Courier'),
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              editCtrl.text = kDefaultServiceRoot;
            },
            child: const Text('默认路径'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(editCtrl.text.trim()),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );

    if (newPath != null && newPath.isNotEmpty && mounted) {
      final ok = await widget.controller.setCustomServiceRootPath(newPath);
      if (mounted) {
        if (ok) {
          HapticFeedback.heavyImpact();
          _showToast('根路径已更新为:\n$newPath');
        } else {
          _showToast('无法应用该路径，请确保路径有效且具有写入权限');
        }
      }
    }
  }

  Future<void> _openInFilza() async {
    HapticFeedback.selectionClick();
    final path = widget.controller.serviceRootPath;
    final opened = await widget.controller.bridge.openUrl('filza://$path');
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: path));
      _showToast('未能直接调起 Filza，路径已复制到剪贴板:\n$path');
    }
  }

  Future<void> _copyText(String text, String label) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: text));
    _showToast('$label 已复制到剪贴板');
  }

  Future<void> _confirmStopAll() async {
    HapticFeedback.selectionClick();
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('停止所有服务？'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('此操作将安全停止当前正在运行的全部受管后台进程。'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认停止全部'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      HapticFeedback.mediumImpact();
      await widget.controller.stopAllServices();
      _showToast('所有服务已安全停止');
    }
  }

  Future<void> _confirmClearLogs() async {
    HapticFeedback.selectionClick();
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清空所有运行日志？'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('此操作将清空所有服务的 stdout.log 日志内容，释放存储空间。'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空日志'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final cleared = await widget.controller.clearAllLogs();
      _showToast('已清空 $cleared 个服务的运行日志');
    }
  }

  void _showToast(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final root = widget.controller.serviceRootPath;
        final ip = widget.controller.localIp;
        final interval = widget.controller.refreshIntervalSeconds;

        return CupertinoPageScaffold(
          backgroundColor:
              CupertinoColors.systemGroupedBackground.resolveFrom(context),
          navigationBar: const CupertinoNavigationBar(
            middle: Text('设置'),
          ),
          child: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                CupertinoListSection.insetGrouped(
                  header: const Text('存储与网络'),
                  children: [
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.folder,
                        color: CupertinoColors.activeBlue,
                      ),
                      title: const Text('服务安装根路径'),
                      subtitle: Text(
                        root,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Courier',
                        ),
                      ),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _changeRootPath,
                    ),
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.square_arrow_right,
                        color: CupertinoColors.activeBlue,
                      ),
                      title: const Text('在 Filza 中打开目录'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _openInFilza,
                    ),
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.wifi,
                        color: CupertinoColors.activeGreen,
                      ),
                      title: const Text('本机局域网 IP'),
                      additionalInfo: Text(ip),
                      onTap: () => _copyText(ip, '局域网 IP'),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('全局操作'),
                  children: [
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.stop_circle,
                        color: CupertinoColors.systemOrange,
                      ),
                      title: const Text('一键停止所有服务'),
                      onTap: _confirmStopAll,
                    ),
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.trash,
                        color: CupertinoColors.destructiveRed,
                      ),
                      title: const Text('清空所有运行日志'),
                      onTap: _confirmClearLogs,
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('偏好设置'),
                  children: [
                    CupertinoListTile(
                      leading: const Icon(
                        CupertinoIcons.timer,
                        color: CupertinoColors.systemPurple,
                      ),
                      title: const Text('状态刷新频率'),
                      additionalInfo: Text(
                        interval == 0
                            ? '仅手动'
                            : interval == 5
                                ? '5 秒'
                                : '2 秒 (默认)',
                      ),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        showCupertinoModalPopup<void>(
                          context: context,
                          builder: (ctx) => CupertinoActionSheet(
                            title: const Text('选择状态刷新频率'),
                            actions: [
                              CupertinoActionSheetAction(
                                isDefaultAction: interval == 2,
                                onPressed: () {
                                  widget.controller.setRefreshInterval(2);
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('2 秒 (默认)'),
                              ),
                              CupertinoActionSheetAction(
                                isDefaultAction: interval == 5,
                                onPressed: () {
                                  widget.controller.setRefreshInterval(5);
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('5 秒 (更省电)'),
                              ),
                              CupertinoActionSheetAction(
                                isDefaultAction: interval == 0,
                                onPressed: () {
                                  widget.controller.setRefreshInterval(0);
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('仅手动刷新'),
                              ),
                            ],
                            cancelButton: CupertinoActionSheetAction(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('取消'),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('关于'),
                  children: [
                    const CupertinoListTile(
                      title: Text('应用版本'),
                      additionalInfo: Text('1.0.0 (TrollStore)'),
                    ),
                    CupertinoListTile(
                      title: const Text('GitHub 仓库'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () {
                        widget.controller.bridge.openUrl(
                          'https://github.com/sanfangx/Trollservice',
                        );
                      },
                    ),
                    const CupertinoListTile(
                      title: Text('开源协议'),
                      additionalInfo: Text('MIT License'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
