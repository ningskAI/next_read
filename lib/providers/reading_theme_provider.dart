import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:i_reader/data/models/reading_theme.dart';

/// 白天主题列表
const _dayThemes = [
  // 白色
  ReadingTheme(
    id: 1,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: '',
  ),
  // 米黄（羊皮纸）
  ReadingTheme(
    id: 2,
    backgroundColor: 'fff5e6c8',
    textColor: 'ff3e2723',
    backgroundImagePath: '',
  ),
  // 护眼绿
  ReadingTheme(
    id: 3,
    backgroundColor: 'ffe8f5e9',
    textColor: 'ff1b5e20',
    backgroundImagePath: '',
  ),
  // 淡蓝
  ReadingTheme(
    id: 4,
    backgroundColor: 'ffe3f2fd',
    textColor: 'ff0d47a1',
    backgroundImagePath: '',
  ),
  // 背景图 1
  ReadingTheme(
    id: 11,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: 'assets/images/bgimg/bg1.jpg',
  ),
  // 背景图 2
  ReadingTheme(
    id: 12,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: 'assets/images/bgimg/bg2.jpg',
  ),
  // 背景图 3
  ReadingTheme(
    id: 13,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: 'assets/images/bgimg/bg3.jpg',
  ),
  // 背景图 4
  ReadingTheme(
    id: 14,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: 'assets/images/bgimg/bg4.jpg',
  ),
  // 背景图 5
  ReadingTheme(
    id: 15,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: 'assets/images/bgimg/bg5.jpg',
  ),
  // 背景图 6
  ReadingTheme(
    id: 16,
    backgroundColor: 'ffffffff',
    textColor: 'ff222222',
    backgroundImagePath: 'assets/images/bgimg/bg6.jpg',
  ),
];

/// 夜间主题列表
const _nightThemes = [
  // 纯黑
  ReadingTheme(
    id: 101,
    backgroundColor: 'ff000000',
    textColor: 'ffcccccc',
    backgroundImagePath: '',
  ),
  // 深灰
  ReadingTheme(
    id: 102,
    backgroundColor: 'ff1c1c1c',
    textColor: 'ffbfbfbf',
    backgroundImagePath: '',
  ),
  // 暗蓝
  ReadingTheme(
    id: 103,
    backgroundColor: 'ff1a2332',
    textColor: 'ffb0bec5',
    backgroundImagePath: '',
  ),
];

final readingThemesProvider =
    StateNotifierProvider<ReadingThemesNotifier, List<ReadingTheme>>(
      (ref) => ReadingThemesNotifier(),
    );

final currentReadingThemeProvider =
    StateNotifierProvider<CurrentReadingThemeNotifier, ReadingTheme>(
      (ref) => CurrentReadingThemeNotifier(),
    );

final isNightModeProvider = StateNotifierProvider<IsNightModeNotifier, bool>(
  (ref) => IsNightModeNotifier(),
);

class ReadingThemesNotifier extends StateNotifier<List<ReadingTheme>> {
  ReadingThemesNotifier() : super([..._dayThemes, ..._nightThemes]);

  /// 获取白天主题
  List<ReadingTheme> get dayThemes => _dayThemes;

  /// 获取夜间主题
  List<ReadingTheme> get nightThemes => _nightThemes;

  void addTheme(ReadingTheme theme) {
    state = [...state, theme];
  }

  void updateTheme(ReadingTheme theme) {
    state = [
      for (final t in state)
        if (t.id == theme.id) theme else t,
    ];
  }

  void removeTheme(int id) {
    state = state.where((t) => t.id != id).toList();
  }
}

class CurrentReadingThemeNotifier extends StateNotifier<ReadingTheme> {
  CurrentReadingThemeNotifier() : super(_dayThemes.first);

  void setTheme(ReadingTheme theme) {
    state = theme;
  }
}

class IsNightModeNotifier extends StateNotifier<bool> {
  IsNightModeNotifier() : super(false);

  void toggle() {
    state = !state;
  }

  void setNightMode(bool value) {
    state = value;
  }
}
