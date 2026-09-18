import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:i_reader/config/app_config.dart';
import 'package:i_reader/data/models/book.dart';
import 'package:i_reader/data/models/reading_theme.dart';
import 'package:i_reader/providers/reading_theme_provider.dart';
import 'package:i_reader/providers/service_registry.dart';
import 'package:i_reader/ui/pages/reading/widgets/epub_player.dart';
import 'package:i_reader/ui/pages/reading/widgets/reading_theme_panel.dart';
import 'package:i_reader/ui/pages/reading/widgets/toc_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReadingPage extends ConsumerStatefulWidget {
  final Book book;
  final String? initialCfi;
  final List<ReadingTheme> initialThemes;

  const ReadingPage({
    super.key,
    required this.book,
    this.initialCfi,
    required this.initialThemes,
  });

  @override
  ConsumerState<ReadingPage> createState() => ReadingPageState();
}

final GlobalKey<ReadingPageState> readingPageKey =
    GlobalKey<ReadingPageState>();
final epubPlayerKey = GlobalKey<EpubPlayerState>();

class ReadingPageState extends ConsumerState<ReadingPage> {
  static const empty = SizedBox.shrink();

  // 控制整个 Overlay 层是否可见
  bool bottomBarOffstage = true;
  // 独立控制 AppBar 的显示（当点击底部按钮时隐藏）
  bool _isAppBarVisible = true;

  Timer? _awakeTimer;

  Future<void> setAwakeTimer(int minutes) async {
    _awakeTimer?.cancel();
    _awakeTimer = null;
    WakelockPlus.enable();
    _awakeTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      WakelockPlus.disable();
      _awakeTimer?.cancel();
      _awakeTimer = null;
    });
  }

  void resetAwakeTimer() {
    setAwakeTimer(AppConfig.getAwakeTime());
  }

  void showBottomBar() {
    setState(() {
      readService(AppServices.statusbarService).showStatusBarWithoutResize();
      bottomBarOffstage = false;
      _isAppBarVisible = true; // 唤起时默认重置 AppBar 为可见
    });
  }

  void hideBottomBar() {
    setState(() {
      readService(AppServices.statusbarService).hideStatusBar();
      bottomBarOffstage = true;
    });
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  Future<void> onLoadEnd() async {
    // 加载完后，应用当前主题
    final theme = ref.read(currentReadingThemeProvider);
    epubPlayerKey.currentState?.changeTheme(theme);
  }

  void updateState() {
    if (mounted) {}
  }

  @override
  Widget build(BuildContext context) {
    // 监听主题变化，同步给 epub player
    ref.listen<ReadingTheme>(currentReadingThemeProvider, (prev, next) {
      if (prev?.id != next.id) {
        epubPlayerKey.currentState?.changeTheme(next);
      }
    });

    final currentTheme = ref.watch(currentReadingThemeProvider);

    return Scaffold(
      body: Stack(
        children: [
          // 0. 底层背景（颜色或图片）
          _ReadingBackground(theme: currentTheme),

          // 1. 底层阅读器
          EpubPlayer(
            key: epubPlayerKey,
            showOrHideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
            book: widget.book,
            onLoadEnd: onLoadEnd,
            initialThemes: widget.initialThemes,
            updateParent: updateState,
          ),

          // 2. 控制层 Overlay
          Offstage(
            offstage: bottomBarOffstage,
            child: SafeArea(
              top: false,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                extendBodyBehindAppBar: true,
                // 根据 _isAppBarVisible 决定是否显示 AppBar
                appBar: _isAppBarVisible
                    ? AppBar(
                        backgroundColor: Colors.transparent,
                        title: Text(
                          widget.book.title,
                          style: const TextStyle(fontSize: 16),
                        ),
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.auto_awesome),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.bookmark_outline),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_horiz_outlined),
                            onPressed: () {},
                          ),
                          const SizedBox(width: 8),
                        ],
                      )
                    : null,
                body: Column(
                  children: [
                    // 中间透明占位区域：点击关闭整个控制层
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          showOrHideAppBarAndBottomBar(false);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: // 底部操作面板
                    _buildBottomBar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isNight = ref.watch(isNightModeProvider);
    return Container(
      color: isNight ? const Color(0xFF1C1C1E) : Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomAction(
                icon: Icons.menu_outlined,
                label: '目录',
                onPressed: () {
                  // 点击菜单：先隐藏 AppBar，再弹出目录
                  setState(() => _isAppBarVisible = false);

                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                    ),
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.9,
                        child: TocWidget(
                          currentHref: "",
                          onTocTap: (toc) {
                            Navigator.pop(context);
                            epubPlayerKey.currentState?.goToHref(toc.href);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
              _buildBottomAction(
                icon: Icons.bookmark_outline,
                label: '书签',
                onPressed: () => setState(() => _isAppBarVisible = false),
              ),
              _buildBottomAction(
                icon: Icons.nightlight_round,
                label: '昼夜',
                onPressed: () {
                  ref.read(isNightModeProvider.notifier).toggle();
                  final isNight = ref.read(isNightModeProvider);
                  final notifier = ref.read(readingThemesProvider.notifier);
                  final list = isNight ? notifier.nightThemes : notifier.dayThemes;
                  final theme = list.first;
                  ref.read(currentReadingThemeProvider.notifier).setTheme(theme);
                },
              ),
              _buildBottomAction(
                icon: Icons.color_lens,
                label: '背景',
                onPressed: () {
                  setState(() => _isAppBarVisible = false);
                  _showThemePanel();
                },
              ),
              _buildBottomAction(
                icon: Icons.text_format,
                label: '字体',
                onPressed: () => setState(() => _isAppBarVisible = false),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final isNight = ref.watch(isNightModeProvider);
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isNight ? Colors.grey[300] : Colors.grey[800],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isNight ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            return ReadingThemePanel(
              onThemeSelected: (theme) {
                epubPlayerKey.currentState?.changeTheme(theme);
              },
            );
          },
        );
      },
    );
  }
}

/// 底层阅读背景，支持颜色和图片
class _ReadingBackground extends ConsumerWidget {
  final ReadingTheme theme;

  const _ReadingBackground({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (theme.backgroundImagePath.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(theme.backgroundImagePath),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      color: Color(int.parse('0x${theme.backgroundColor}')),
    );
  }
}
