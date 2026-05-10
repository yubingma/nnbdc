import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

class UpdatePage extends ConsumerWidget {
  const UpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateServiceProvider);
    final updateNotifier = ref.read(updateServiceProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('检查更新'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(context, updateState, updateNotifier),
    );
  }

  Widget _buildBody(BuildContext context, UpdateState state, UpdateNotifier notifier) {
    if (state.isChecking) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在检查更新...'),
          ],
        ),
      );
    }

    if (state.updateInfo != null) {
      final updateInfo = state.updateInfo!;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发现新版本 ${updateInfo.version}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('当前版本: ${state.currentVersion}'),
                    Text('最新版本: ${updateInfo.version}'),
                    if (updateInfo.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '更新内容:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(updateInfo.releaseNotes),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              notifier.downloadUpdate(updateInfo);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('立即更新'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('稍后提醒'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '当前已是最新版本',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('版本: ${state.currentVersion}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      notifier.checkForUpdate();
                    },
                    child: const Text('重新检查'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '自动更新设置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('启用自动检查更新'),
                    subtitle: const Text('应用启动时自动检查更新'),
                    value: true, // 这里可以绑定到设置
                    onChanged: (value) {
                      // 更新设置
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
