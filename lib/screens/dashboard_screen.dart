import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import '../services/daemon_controller.dart';
import 'add_service_screen.dart';
import 'log_viewer_screen.dart';
import 'service_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  final DaemonController controller;

  const DashboardScreen({super.key, required this.controller});

  Future<void> _openAddScreen(BuildContext context) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (_) => AddServiceScreen(controller: controller),
      ),
    );
  }

  Future<void> _openDetailScreen(
    BuildContext context,
    ServiceItem service,
  ) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (_) => ServiceDetailScreen(
          controller: controller,
          service: service,
        ),
      ),
    );
  }

  Future<void> _openLogScreen(
    BuildContext context,
    ServiceItem service,
  ) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => LogViewerScreen(
          controller: controller,
          service: service,
        ),
      ),
    );
  }

  Future<void> _openWebPanel(ServiceItem service) async {
    if (service.port <= 0) return;
    HapticFeedback.lightImpact();
    await controller.bridge.openUrl('http://127.0.0.1:${service.port}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final services = controller.services;
        return CupertinoPageScaffold(
          backgroundColor:
              CupertinoColors.systemGroupedBackground.resolveFrom(context),
          navigationBar: CupertinoNavigationBar(
            middle: const Text('TrollService 服务管理'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _openAddScreen(context),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.add_circled_solid, size: 20),
                  SizedBox(width: 4),
                  Text('安装程序', style: TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildOverviewHeader(context),
                ),
                if (controller.lastError != null)
                  SliverToBoxAdapter(
                    child: _buildErrorBanner(context, controller.lastError!),
                  ),
                if (services.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(context),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    sliver: SliverList.separated(
                      itemCount: services.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _buildServiceCard(
                        context,
                        services[index],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverviewHeader(BuildContext context) {
    final total = controller.services.length;
    final running = controller.runningCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running > 0
                      ? CupertinoColors.activeGreen
                      : CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '运行状态: $running / $total 个服务正在运行',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Clipboard.setData(ClipboardData(text: controller.localIp));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemFill
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '局域网 IP: ${controller.localIp}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '默认安装根目录: ${controller.serviceRootPath}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Courier',
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.destructiveRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: CupertinoColors.destructiveRed,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(24, 24),
            onPressed: controller.clearError,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 18,
              color: CupertinoColors.destructiveRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.cube_box,
              size: 54,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 14),
            const Text(
              '尚未安装任何后台服务',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角「安装程序」导入 AIStudio2API 或同类单二进制程序。\n'
              '软件将自动安装至 /var/mobile/Documents/service 并执行 ldid + fastPathSign 签名赋权。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: () => _openAddScreen(context),
              child: const Text('立即安装第一个服务'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard(BuildContext context, ServiceItem service) {
    final status = service.status;
    final busy = controller.isBusy(service.id);

    final Color dotColor;
    final String statusText;
    if (status.isRunning) {
      if (service.port <= 0 || status.isPortOpen) {
        dotColor = CupertinoColors.activeGreen;
        statusText = service.port > 0
            ? '运行中 · 端口 :${service.port} 已开启'
            : '运行中 (PID: ${status.pid})';
      } else {
        dotColor = CupertinoColors.systemOrange;
        statusText = '启动中 · 等待端口 :${service.port}';
      }
    } else {
      dotColor = CupertinoColors.systemGrey;
      statusText = '已停止';
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: status.isRunning
                            ? dotColor
                            : CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: CupertinoActivityIndicator(),
                )
              else
                CupertinoSwitch(
                  value: status.isRunning,
                  onChanged: (_) {
                    HapticFeedback.mediumImpact();
                    controller.toggleService(service.id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PID: ${status.isRunning ? status.pid : "-"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '内存: ${status.formattedMemory}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '运行时长: ${status.formattedUptime}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '路径: ${service.serviceDir(controller.serviceRootPath)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Courier',
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                if (service.port > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '访问地址: http://${controller.localIp}:${service.port}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Courier',
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (service.port > 0) ...[
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 34),
                    color: status.isRunning
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.quaternarySystemFill
                            .resolveFrom(context),
                    onPressed: status.isRunning
                        ? () => _openWebPanel(service)
                        : null,
                    child: Text(
                      '打开面板',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: status.isRunning
                            ? CupertinoColors.white
                            : CupertinoColors.tertiaryLabel
                                .resolveFrom(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 34),
                  color:
                      CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  onPressed: () => _openLogScreen(context, service),
                  child: Text(
                    '实时日志',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 34),
                  color:
                      CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  onPressed: () => _openDetailScreen(context, service),
                  child: Text(
                    '更新 / 配置',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
