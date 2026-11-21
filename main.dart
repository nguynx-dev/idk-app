import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản lý app',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const AppListPage(),
    );
  }
}

class AppInfo {
  final String name;
  final String packageName;
  final int size;
  final bool isSystem;

  const AppInfo({
    required this.name,
    required this.packageName,
    required this.size,
    required this.isSystem,
  });
}

class NativeApi {
  static const MethodChannel _channel = MethodChannel('app_manager/native');

  static Future<List<AppInfo>> getApps() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>('getApps') ?? <dynamic>[];
    return raw.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return AppInfo(
        name: map['name'] as String,
        packageName: map['package'] as String,
        size: (map['size'] as num).toInt(),
        isSystem: map['isSystem'] as bool,
      );
    }).toList();
  }

  static Future<Uint8List?> getIcon(String pkg) {
    return _channel.invokeMethod<Uint8List>('getIcon', {'package': pkg});
  }

  static Future<bool> openApp(String pkg) async {
    return await _channel.invokeMethod<bool>('openApp', {'package': pkg}) ??
        false;
  }

  static Future<bool> uninstall(String pkg) async {
    return await _channel.invokeMethod<bool>('uninstall', {'package': pkg}) ??
        false;
  }
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class AppIcon extends StatelessWidget {
  static final Map<String, Future<Uint8List?>> _cache = {};

  final String packageName;
  const AppIcon(this.packageName, {super.key});

  @override
  Widget build(BuildContext context) {
    final future =
        _cache.putIfAbsent(packageName, () => NativeApi.getIcon(packageName));
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.android),
          );
        }
        return Image.memory(bytes, width: 44, height: 44, gaplessPlayback: true);
      },
    );
  }
}

enum SortMode { name, size }

class AppListPage extends StatefulWidget {
  const AppListPage({super.key});

  @override
  State<AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<AppListPage> with WidgetsBindingObserver {
  static const String _trashKey = 'trash_apps';

  List<AppInfo> _apps = [];
  Set<String> _trash = {};
  bool _loading = true;
  String? _error;

  SortMode _sort = SortMode.name;
  bool _showSystem = false;
  bool _onlyTrash = false;
  bool _refreshAfterReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _refreshAfterReturn) {
      _refreshAfterReturn = false;
      _loadApps(showSpinner: false);
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _trash = (prefs.getStringList(_trashKey) ?? <String>[]).toSet();
    await _loadApps();
  }

  Future<void> _loadApps({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final apps = await NativeApi.getApps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<AppInfo> get _visible {
    final list = _apps.where((a) {
      if (!_showSystem && a.isSystem) return false;
      if (_onlyTrash && !_trash.contains(a.packageName)) return false;
      return true;
    }).toList();

    if (_sort == SortMode.name) {
      list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      list.sort((a, b) => b.size.compareTo(a.size));
    }
    return list;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleTrash(AppInfo app) async {
    setState(() {
      if (!_trash.add(app.packageName)) {
        _trash.remove(app.packageName);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_trashKey, _trash.toList());
  }

  Future<void> _open(AppInfo app) async {
    final ok = await NativeApi.openApp(app.packageName);
    if (!ok && mounted) _snack('Không mở được ${app.name}');
  }

  Future<void> _uninstall(AppInfo app) async {
    if (app.isSystem) {
      _snack('${app.name} là app hệ thống, không gỡ được theo cách này.');
      return;
    }
    _refreshAfterReturn = true;
    final ok = await NativeApi.uninstall(app.packageName);
    if (!ok) {
      _refreshAfterReturn = false;
      if (mounted) _snack('Không mở được màn hình gỡ cài đặt');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text('Quản lý app (${visible.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: () => _loadApps(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Theo tên'),
                  selected: _sort == SortMode.name,
                  onSelected: (_) => setState(() => _sort = SortMode.name),
                ),
                ChoiceChip(
                  label: const Text('Theo dung lượng'),
                  selected: _sort == SortMode.size,
                  onSelected: (_) => setState(() => _sort = SortMode.size),
                ),
                FilterChip(
                  label: const Text('App hệ thống'),
                  selected: _showSystem,
                  onSelected: (v) => setState(() => _showSystem = v),
                ),
                FilterChip(
                  label: const Text('Chỉ app rác'),
                  selected: _onlyTrash,
                  onSelected: (v) => setState(() => _onlyTrash = v),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(visible)),
        ],
      ),
    );
  }

  Widget _buildBody(List<AppInfo> visible) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lỗi: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadApps(),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return const Center(child: Text('Không có app nào để hiển thị'));
    }

    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final app = visible[index];
        final isTrash = _trash.contains(app.packageName);

        return ListTile(
          tileColor:
              isTrash ? Theme.of(context).colorScheme.errorContainer : null,
          leading: AppIcon(app.packageName),
          title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${formatSize(app.size)}${app.isSystem ? ' · hệ thống' : ''}\n${app.packageName}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: () => _open(app),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(isTrash ? Icons.flag : Icons.flag_outlined),
                tooltip: 'Đánh dấu rác',
                onPressed: () => _toggleTrash(app),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Gỡ cài đặt',
                onPressed: () => _uninstall(app),
              ),
            ],
          ),
        );
      },
    );
  }
}
