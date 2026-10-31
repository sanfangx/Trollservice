import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import '../services/daemon_controller.dart';
import 'add_service_screen.dart';
import 'log_viewer_screen.dart';
import 'service_detail_screen.dart';
import 'settings_screen.dart';

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

  Future<void> _openSettings(BuildContext context) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => SettingsScreen(controller: controller),
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
        final total = services.length;
        final running = controller.runningCount;

        return CupertinoPageScaffold(
          backgroundColor:
              CupertinoColors.systemGroupedBackground.resolveFrom(context),
          navigationBar: CupertinoNavigationBar(
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _openSettings(context),
              child: const Icon(CupertinoIcons.gear_alt, size: 22),
            ),
            middle: const Text('TrollService'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _openAddScreen(context),
              child: const Icon(CupertinoIcons.plus_circle_fill, size: 24),
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                if (controller.lastError != null)
                  SliverToBoxAdapter(
                    child: _buildErrorBanner(context, controller.lastError!),
                  ),
                if (services.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(context),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '受管服务 ($running 运行中 / $total 共计)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                          if (controller.refreshIntervalSeconds == 0)
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                controller.refreshAllStatuses();
                              },
                              child: Text(
                                '点击刷新',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.activeBlue
                                      .resolveFrom(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorBanner(BuildContext context, String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.destructiveRed.withValues(alpha: 0.12),
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
              size: 56,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 14),
            const Text(
              '尚未添加任何后台服务',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '点击右上角「+」导入待管理的单二进制程序。',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              onPressed: () => _openAddScreen(context),
              child: const Text('安装第一个服务', style: TextStyle(fontSize: 14)),
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
    if (status.isRunning) {
      dotColor = (service.port <= 0 || status.isPortOpen)
          ? CupertinoColors.activeGreen
          : CupertinoColors.systemOrange;
    } else {
      dotColor = CupertinoColors.systemGrey3;
    }

    return Container(
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
                  color: dotColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
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
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              status.isRunning
                  ? '${service.port > 0 ? "端口 :${service.port} · " : ""}PID: ${status.pid} · ${status.formattedMemory} · 运行 ${status.formattedUptime}'
                  : (service.port > 0 ? '端口 :${service.port} · 已停止' : '已停止'),
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (service.port > 0 && status.isRunning) ...[
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 30),
                  color: CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () => _openWebPanel(service),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.compass, size: 14, color: CupertinoColors.white),
                      SizedBox(width: 4),
                      Text(
                        '打开面板',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 30),
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _openLogScreen(context, service),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.doc_text,
                      size: 13,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '日志',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 30),
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _openDetailScreen(context, service),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.slider_horizontal_3,
                      size: 13,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '配置',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
