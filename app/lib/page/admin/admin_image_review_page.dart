import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/config.dart';

class AdminImageReviewPage extends StatefulWidget {
  const AdminImageReviewPage({super.key});

  @override
  State<AdminImageReviewPage> createState() => _AdminImageReviewPageState();
}

class _AdminImageReviewPageState extends State<AdminImageReviewPage> {
  final TextEditingController _dictIdController = TextEditingController(text: '0');
  bool _isLoading = false;
  bool _isScanning = false;
  
  List<Map<String, dynamic>> _images = [];
  int _currentIndex = 0;
  
  String get _baseUrl => Api.useProdUrl ? Config.profiles["prod"]["service_url"] : Config.serviceUrl;

  @override
  void dispose() {
    _dictIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchImages() async {
    final dictId = _dictIdController.text.trim();
    if (dictId.isEmpty) {
      ToastUtil.info('请输入词典 ID'); 
      return;
    }

    setState(() {
      _isLoading = true;
      _images.clear();
      _currentIndex = 0;
    });

    try {
      final response = await Api.dio.get('$_baseUrl/admin/image/getDictImages.do', queryParameters: {'dictId': dictId});
      final res = response.data;
      if (res['success'] == true) {
        setState(() {
          _images = List<Map<String, dynamic>>.from(res['data']);
        });
        ToastUtil.success('成功获取 ${_images.length} 张配图');
      } else {
        ToastUtil.error('获取失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startScan() async {
    if (_images.isEmpty) return;
    
    setState(() {
      _isScanning = true;
      _currentIndex = 0;
    });

    for (int i = 0; i < _images.length; i++) {
        if (!mounted) break;
        if (!_isScanning) break; // Allow manual pause
        
        setState(() {
           _currentIndex = i;
        });
        
        // Only scan those not scanned yet
        if (_images[i]['aiResult'] != null) continue;
        
        try {
            final response = await Api.dio.post('$_baseUrl/admin/image/review.do', queryParameters: {'imageId': _images[i]['imageId']});
            final res = response.data;
            if (res['success'] == true && res['data'] != null) {
                if (mounted) {
                    setState(() {
                        _images[i]['aiResult'] = res['data'];
                    });
                }
            } else {
                if (mounted) {
                    setState(() {
                        _images[i]['aiResult'] = {'action': 'ERROR', 'reason': res['msg']};
                    });
                }
            }
        } catch (e) {
            if (mounted) {
                setState(() {
                    _images[i]['aiResult'] = {'action': 'ERROR', 'reason': e.toString()};
                });
            }
        }
        
        // Adding a slight delay to avoid dashing DashScope limits
        await Future.delayed(const Duration(milliseconds: 500));
    }
    
    if (mounted) {
        setState(() {
            _isScanning = false;
            ToastUtil.success('扫描完成');
        });
    }
  }

  Future<void> _deleteImage(int index, String imageId) async {
    try {
        final response = await Api.dio.post('$_baseUrl/admin/image/delete.do', data: {
            'imageId': imageId,
            'userId': Global.sysUserId,
        }, queryParameters: {
            'imageId': imageId,
            'userId': Global.sysUserId,
        });
        final res = response.data;
        if (res['success'] == true) {
            setState(() {
                _images[index]['deleted'] = true;
            });
            ToastUtil.success('删除成功');
        } else {
            ToastUtil.error('删除失败: ${res['msg']}');
        }
    } catch (e) {
        ToastUtil.error('请求异常: $e');
    }
  }

  Future<void> _bulkDelete() async {
      final toDelete = _images.asMap().entries.where((e) {
          final ai = e.value['aiResult'];
          return e.value['deleted'] != true && ai != null && ai['action'] == 'DELETE';
      }).toList();
      
      if (toDelete.isEmpty) {
          ToastUtil.info('没有需要删除的不合格图片');
          return;
      }
      
      bool? confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
              title: const Text('批量删除'),
              content: Text('您确定要删除这 ${toDelete.length} 张被确认为不合格的配图吗？'),
              actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
              ],
          ),
      );
      
      if (confirm == true) {
          int successCount = 0;
          for (var item in toDelete) {
              try {
                  final response = await Api.dio.post('$_baseUrl/admin/image/delete.do', data: {
                      'imageId': item.value['imageId'],
                      'userId': Global.sysUserId,
                  }, queryParameters: {
                      'imageId': item.value['imageId'],
                      'userId': Global.sysUserId,
                  });
                  final res = response.data;
                  if (res['success'] == true) {
                      setState(() {
                          _images[item.key]['deleted'] = true;
                      });
                      successCount++;
                  }
              } catch (e) {
                  // Ignore per-image error, show overall result
              }
          }
          ToastUtil.info('批量删除完成，共删除了 $successCount 张图片');
      }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    int badCount = _images.where((i) => i['aiResult'] != null && i['aiResult']['action'] == 'DELETE' && i['deleted'] != true).length;
    int pendingCount = _images.where((i) => i['aiResult'] == null).length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: 'AI 配图自动审核',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          if (badCount > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              tooltip: '一键删除不合格项',
              onPressed: _bulkDelete,
            )
        ]
      ),
      body: Column(
        children: [
          Container(
             padding: const EdgeInsets.all(16),
             color: isDarkMode ? Colors.grey[900] : Colors.white,
             child: Row(
                 children: [
                     Expanded(
                         child: TextField(
                             controller: _dictIdController,
                             decoration: const InputDecoration(
                                 labelText: '目标词典ID (系统词典通常为0)',
                                 border: OutlineInputBorder(),
                                 isDense: true,
                             ),
                         )
                     ),
                     const SizedBox(width: 8),
                     ElevatedButton(
                         onPressed: _isLoading || _isScanning ? null : _fetchImages,
                         child: _isLoading ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Text('加载配图'),
                     ),
                     const SizedBox(width: 8),
                     ElevatedButton.icon(
                         onPressed: _images.isEmpty || _isLoading ? null : () {
                             if (_isScanning) {
                                 setState(() => _isScanning = false);
                             } else {
                                 _startScan();
                             }
                         },
                         icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                         label: Text(_isScanning ? '停止扫描' : 'AI审查所有'),
                         style: ElevatedButton.styleFrom(
                             backgroundColor: _isScanning ? Colors.red : AppTheme.primaryColor,
                             foregroundColor: Colors.white,
                         ),
                     )
                 ],
             ),
          ),
          
          if (_images.isNotEmpty)
              Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 color: isDarkMode ? Colors.grey[850] : Colors.grey[200],
                 child: Row(
                     children: [
                         Text('总数: ${_images.length}'), const SizedBox(width: 16),
                         Text('未扫: $pendingCount'), const SizedBox(width: 16),
                         Text('不合格: $badCount', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                         if (_isScanning) ...[
                            const Spacer(),
                            const SizedBox(width:12, height:12, child: CircularProgressIndicator(strokeWidth:2)),
                            const SizedBox(width: 8),
                            Text('正在审核第 ${_currentIndex + 1} 个...', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                         ]
                     ],
                 ),
              ),
          
          Expanded(
             child: ListView.builder(
                 itemCount: _images.length,
                 padding: const EdgeInsets.all(16),
                 itemBuilder: (context, index) {
                     final img = _images[index];
                     if (img['deleted'] == true) {
                         return const SizedBox.shrink(); // Deleted items disappear
                     }
                     
                     final aiResult = img['aiResult'];
                     final bool isScanningThis = _isScanning && _currentIndex == index;
                     
                     Color cardColor = isDarkMode ? Colors.grey[800]! : Colors.white;
                     Color borderColor = Colors.transparent;
                     if (aiResult != null) {
                         if (aiResult['action'] == 'DELETE') {
                             cardColor = Colors.red.withValues(alpha: 0.1);
                             borderColor = Colors.red.withValues(alpha: 0.3);
                         } else if (aiResult['action'] == 'KEEP') {
                             cardColor = Colors.green.withValues(alpha: 0.05);
                             borderColor = Colors.green.withValues(alpha: 0.2);
                         }
                     }
                     
                     return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: borderColor),
                        ),
                        color: cardColor,
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                            '${Config.wordImageBaseUrl}${img['imageFile']}',
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                        ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                                Text(img['spell'] ?? '未知单词', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                                const SizedBox(height: 8),
                                                if (isScanningThis)
                                                    const Row(children: [SizedBox(width:12,height:12,child:CircularProgressIndicator(strokeWidth:2)), SizedBox(width:8), Text('AI 正在审阅...', style: TextStyle(color: Colors.blue))])
                                                else if (aiResult == null)
                                                    const Text('等待审核', style: TextStyle(color: Colors.grey))
                                                else if (aiResult['action'] == 'DELETE')
                                                    Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                            const Text('❌ 审核不合格 - 建议删除', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                            const SizedBox(height: 4),
                                                            Text(aiResult['reason'] ?? '', style: const TextStyle(color: Colors.red, fontSize: 13)),
                                                        ],
                                                    )
                                                else if (aiResult['action'] == 'KEEP')
                                                    const Text('✅ 审核通过', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                                else
                                                    Text('⚠️ 异常: ${aiResult['reason']}', style: const TextStyle(color: Colors.orange)),
                                            ],
                                        )
                                    ),
                                    if (aiResult != null && aiResult['action'] == 'DELETE')
                                        IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            tooltip: '单独删除此图',
                                            onPressed: () => _deleteImage(index, img['imageId']),
                                        )
                                ],
                            ),
                        ),
                     );
                 },
             ),
          )
        ],
      )
    );
  }
}
