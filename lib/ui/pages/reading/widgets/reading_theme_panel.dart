import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:i_reader/data/models/reading_theme.dart';
import 'package:i_reader/providers/reading_theme_provider.dart';

/// 阅读背景切换面板，类似番茄小说的设置面板
class ReadingThemePanel extends ConsumerStatefulWidget {
  final ValueChanged<ReadingTheme> onThemeSelected;

  const ReadingThemePanel({
    super.key,
    required this.onThemeSelected,
  });

  @override
  ConsumerState<ReadingThemePanel> createState() => _ReadingThemePanelState();
}

class _ReadingThemePanelState extends ConsumerState<ReadingThemePanel> {
  @override
  Widget build(BuildContext context) {
    final isNight = ref.watch(isNightModeProvider);
    final currentTheme = ref.watch(currentReadingThemeProvider);
    final themesNotifier = ref.read(readingThemesProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isNight ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日夜间模式切换
            _buildModeSwitch(isNight),
            const SizedBox(height: 16),
            // 纯色主题
            _buildColorRow(
              label: '颜色',
              themes: isNight
                  ? themesNotifier.nightThemes
                  : themesNotifier.dayThemes
                      .where((t) => t.backgroundImagePath.isEmpty)
                      .toList(),
              currentThemeId: currentTheme.id,
              isNight: isNight,
            ),
            const SizedBox(height: 16),
            // 背景图片
            if (!isNight)
              _buildBackgroundRow(
                themes: themesNotifier.dayThemes
                    .where((t) => t.backgroundImagePath.isNotEmpty)
                    .toList(),
                currentThemeId: currentTheme.id,
                isNight: isNight,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch(bool isNight) {
    final labelStyle = TextStyle(
      fontSize: 14,
      color: isNight ? Colors.grey[300] : Colors.grey[700],
    );

    return Row(
      children: [
        Icon(
          isNight ? Icons.nightlight : Icons.wb_sunny,
          size: 18,
          color: isNight ? Colors.amber : Colors.orange,
        ),
        const SizedBox(width: 8),
        Text(isNight ? '夜间模式' : '白天模式', style: labelStyle),
        const Spacer(),
        Switch(
          value: isNight,
          onChanged: (value) {
            ref.read(isNightModeProvider.notifier).setNightMode(value);
            // 切换到对应模式的第一个主题
            final notifier = ref.read(readingThemesProvider.notifier);
            final list = value ? notifier.nightThemes : notifier.dayThemes;
            final first = list.first;
            ref.read(currentReadingThemeProvider.notifier).setTheme(first);
            widget.onThemeSelected(first);
          },
          activeColor: Colors.amber,
        ),
      ],
    );
  }

  Widget _buildColorRow({
    required String label,
    required List<ReadingTheme> themes,
    required int? currentThemeId,
    required bool isNight,
  }) {
    final labelStyle = TextStyle(
      fontSize: 14,
      color: isNight ? Colors.grey[300] : Colors.grey[700],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: themes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final theme = themes[index];
              final selected = theme.id == currentThemeId;
              return _ColorThemeItem(
                theme: theme,
                selected: selected,
                isNight: isNight,
                onTap: () {
                  ref
                      .read(currentReadingThemeProvider.notifier)
                      .setTheme(theme);
                  widget.onThemeSelected(theme);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundRow({
    required List<ReadingTheme> themes,
    required int? currentThemeId,
    required bool isNight,
  }) {
    final labelStyle = TextStyle(
      fontSize: 14,
      color: isNight ? Colors.grey[300] : Colors.grey[700],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('背景', style: labelStyle),
            const Spacer(),
            // "无背景" 按钮
            GestureDetector(
              onTap: () {
                final plainTheme = ref
                    .read(readingThemesProvider.notifier)
                    .dayThemes
                    .firstWhere((t) => t.backgroundImagePath.isEmpty);
                ref
                    .read(currentReadingThemeProvider.notifier)
                    .setTheme(plainTheme);
                widget.onThemeSelected(plainTheme);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '无背景',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: themes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final theme = themes[index];
              final selected = theme.id == currentThemeId;
              return _ImageThemeItem(
                theme: theme,
                selected: selected,
                onTap: () {
                  ref
                      .read(currentReadingThemeProvider.notifier)
                      .setTheme(theme);
                  widget.onThemeSelected(theme);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColorThemeItem extends StatelessWidget {
  final ReadingTheme theme;
  final bool selected;
  final bool isNight;
  final VoidCallback onTap;

  const _ColorThemeItem({
    required this.theme,
    required this.selected,
    required this.isNight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = Color(int.parse('0x${theme.backgroundColor}'));
    final borderColor = selected
        ? (isNight ? Colors.amber : Colors.blue)
        : (isNight ? Colors.grey[600]! : Colors.grey[300]!);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor,
            width: selected ? 3 : 1.5,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                color: _isLight(bgColor) ? Colors.black : Colors.white,
                size: 20,
              )
            : null,
      ),
    );
  }

  bool _isLight(Color c) {
    return c.computeLuminance() > 0.5;
  }
}

class _ImageThemeItem extends StatelessWidget {
  final ReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _ImageThemeItem({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          image: DecorationImage(
            image: AssetImage(theme.backgroundImagePath),
            fit: BoxFit.cover,
          ),
        ),
        child: selected
            ? const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.check_circle,
                      color: Colors.blue, size: 18),
                ),
              )
            : null,
      ),
    );
  }
}
