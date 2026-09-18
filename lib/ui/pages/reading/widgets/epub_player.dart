import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:i_reader/config/app_config.dart';
import 'package:i_reader/data/enums/reading_info.dart';
import 'package:i_reader/data/enums/translation_enums.dart';
import 'package:i_reader/data/models/book.dart';
import 'package:i_reader/data/models/book_note.dart';
import 'package:i_reader/data/models/book_style.dart';
import 'package:i_reader/data/models/font_model.dart';
import 'package:i_reader/data/models/reading_info.dart';
import 'package:i_reader/data/models/reading_theme.dart';
import 'package:i_reader/data/models/toc.dart';
import 'package:i_reader/providers/book_toc.dart';
import 'package:i_reader/providers/booknote_provider.dart';
import 'package:i_reader/providers/bookshelf_provider.dart';
import 'package:i_reader/providers/chapter_content_provider.dart';
import 'package:i_reader/providers/repository_providers.dart';
import 'package:i_reader/providers/service_registry.dart';
import 'package:i_reader/services/statusbar/statusbar_service.dart';
import 'package:i_reader/ui/pages/reading/models/diagram.dart';
import 'package:i_reader/ui/pages/reading/models/types_and_icons.dart';
import 'package:i_reader/ui/pages/reading/reading_page.dart';
import 'package:i_reader/ui/pages/reading/widgets/context_menu/excerpt_menu.dart';
import 'package:i_reader/ui/pages/reading/widgets/minute_clock.dart';
import 'package:i_reader/utils/color_utils.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:i_reader/core/webview/generate_url.dart';

class EpubPlayer extends ConsumerStatefulWidget {
  final Book book;
  final String? cfi;
  final Function showOrHideAppBarAndBottomBar;
  final Function onLoadEnd;
  final List<ReadingTheme> initialThemes;
  final Function updateParent;

  const EpubPlayer({
    super.key,
    required this.showOrHideAppBarAndBottomBar,
    required this.book,
    this.cfi,
    required this.onLoadEnd,
    required this.initialThemes,
    required this.updateParent,
  });

  @override
  ConsumerState<EpubPlayer> createState() => EpubPlayerState();
}

class EpubPlayerState extends ConsumerState<EpubPlayer>
    with TickerProviderStateMixin {
  late InAppWebViewController webViewController;
  late ContextMenu contextMenu;
  String cfi = '';
  double percentage = 0.0;
  String chapterTitle = '';
  String chapterHref = '';
  int chapterCurrentPage = 0;
  int chapterTotalPages = 0;
  OverlayEntry? contextMenuEntry;
  AnimationController? _animationController;
  Animation<double>? _animation;
  bool showHistory = false;
  bool canGoBack = false;
  bool canGoForward = false;
  late Book book;
  String? backgroundColor;
  String? textColor;
  Timer? styleTimer;
  String bookmarkCfi = '';
  bool bookmarkExists = false;
  String? _lastSelectionContextText;
  bool _selectionClearLocked = false;
  bool _selectionClearPending = false;

  // Scroll wheel debounce
  Timer? _scrollDebounceTimer;

  // to know anytime if we are on top of navigation stack
  bool get _isTopOfNavigationStack =>
      ModalRoute.of(context)?.isCurrent ?? false;

  void prevPage() {
    webViewController.evaluateJavascript(source: 'prevPage()');
  }

  void nextPage() {
    webViewController.evaluateJavascript(source: 'nextPage()');
  }

  void prevChapter() {
    webViewController.evaluateJavascript(source: 'prevSection()');
  }

  void nextChapter() {
    webViewController.evaluateJavascript(source: 'nextSection()');
  }

  void setTranslationMode(TranslationModeEnum mode) {
    webViewController.evaluateJavascript(
      source:
          '''
      if (typeof reader.view !== 'undefined' && reader.view.setTranslationMode) {
        reader.view.setTranslationMode('${mode.code}');
      }
      ''',
    );
  }

  Future<void> goToPercentage(double value) async {
    await webViewController.evaluateJavascript(source: 'goToPercent($value);');
  }

  void setSelectionClearLocked(bool locked) {
    _selectionClearLocked = locked;
    if (!locked && _selectionClearPending) {
      _selectionClearPending = false;
      _lastSelectionContextText = null;
      removeOverlay();
    }
  }

  void changeTheme(ReadingTheme readTheme) {
    textColor = readTheme.textColor;
    backgroundColor = readTheme.backgroundColor;

    // 让 webview 内部背景透明，由 Flutter 底层 Container 显示真实背景
    const bc = '00000000';
    final tc = ColorUtils.convertDartColorToJs(readTheme.textColor);

    webViewController.evaluateJavascript(
      source:
          '''
      changeStyle({
        backgroundColor: '#$bc',
        fontColor: '#$tc',
      })
      ''',
    );
  }

  void changeStyle(BookStyle? bookStyle) {
    styleTimer?.cancel();

    styleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      BookStyle style =
          bookStyle ??
          BookStyle(
            fontSize: 1.4,
            fontFamily: 'Arial',
            fontWeight: 400,
            lineHeight: 1.8,
            letterSpacing: 0.0,
            wordSpacing: 0.0,
            paragraphSpacing: 1.0,
            sideMargin: 6.0,
            topMargin: 90.0,
            bottomMargin: 50.0,
            indent: 0,
            maxColumnCount: 0,
            headingFontSize: 1.0,
            columnThreshold: 720.0,
          );
      webViewController.evaluateJavascript(
        source:
            '''
      changeStyle({
        fontSize: ${style.fontSize},
        spacing: ${style.lineHeight},
        fontWeight: ${style.fontWeight},
        paragraphSpacing: ${style.paragraphSpacing},
        topMargin: ${style.topMargin},
        bottomMargin: ${style.bottomMargin},
        sideMargin: ${style.sideMargin},
        letterSpacing: ${style.letterSpacing},
        textIndent: ${style.indent},
        maxColumnCount: ${style.maxColumnCount},
        columnThreshold: ${style.columnThreshold},
        useBookStyles: true,
        headingFontSize: ${style.headingFontSize},
      })
      ''',
      );
    });
  }

  void changeFont(FontModel font) {
    webViewController.evaluateJavascript(
      source:
          '''
      changeStyle({
        fontName: '${font.name}',
        fontPath: '${font.path}',
      })
    ''',
    );
  }

  void goToHref(String href) =>
      webViewController.evaluateJavascript(source: "goToHref('$href')");

  void goToCfi(String cfi) =>
      webViewController.evaluateJavascript(source: "goToCfi('$cfi')");

  void addAnnotation(BookNote bookNote) {
    final noteContent = (bookNote.content)
        .replaceAll('\n', ' ')
        .replaceAll("'", "\\'");
    webViewController.evaluateJavascript(
      source:
          '''
      addAnnotation({
        id: ${bookNote.id},
        type: '${bookNote.type}',
        value: '${bookNote.cfi}',
        color: '#${bookNote.color}',
        note: '$noteContent',
      })
      ''',
    );
  }

  void addBookmark(BookNote bookmark) {
    webViewController.evaluateJavascript(
      source:
          '''
      addAnnotation({
        id: ${bookmark.id},
        type: 'bookmark',
        value: '${bookmark.cfi}',
        color: '#000000',
        note: 'None',
      })
      ''',
    );
  }

  void addBookmarkHere() {
    webViewController.evaluateJavascript(source: 'addBookmarkHere()');
  }

  void removeAnnotation(String cfi) =>
      webViewController.evaluateJavascript(source: "removeAnnotation('$cfi')");

  void clearSearch() {
    _clearSearchHighlights();
  }

  void search(String text) {
    final sanitized = text.trim();
    if (sanitized.isEmpty) {
      clearSearch();
      return;
    }
    _clearSearchHighlights();
    webViewController.evaluateJavascript(
      source:
          '''
      search('$sanitized', {
        'scope': 'book',
        'matchCase': false,
        'matchDiacritics': false,
        'matchWholeWords': false,
      })
    ''',
    );
  }

  void _clearSearchHighlights() {
    webViewController.evaluateJavascript(source: "clearSearch()");
  }

  Future<void> initTts({String? fromCfi}) async {
    if (fromCfi != null && fromCfi.isNotEmpty) {
      await webViewController.evaluateJavascript(
        source: "window.ttsFromCfi('$fromCfi')",
      );
    } else {
      await webViewController.evaluateJavascript(source: "window.ttsHere()");
    }
  }

  void ttsStop() => webViewController.evaluateJavascript(source: "ttsStop()");

  Future<String> ttsNext() async =>
      (await webViewController.callAsyncJavaScript(
        functionBody: "return await ttsNext()",
      ))?.value;

  Future<String> ttsPrev() async =>
      (await webViewController.callAsyncJavaScript(
        functionBody: "return await ttsPrev()",
      ))?.value;

  Future<String> ttsPrevSection() async =>
      (await webViewController.callAsyncJavaScript(
        functionBody: "return await ttsPrevSection()",
      ))?.value;

  Future<String> ttsNextSection() async =>
      (await webViewController.callAsyncJavaScript(
        functionBody: "return await ttsNextSection()",
      ))?.value;

  Future<String> ttsPrepare() async =>
      (await webViewController.evaluateJavascript(source: "ttsPrepare()"));

  Future<bool> isFootNoteOpen() async => (await webViewController
      .evaluateJavascript(source: "window.isFootNoteOpen()"));

  void backHistory() {
    webViewController.evaluateJavascript(source: "back()");
  }

  void forwardHistory() {
    webViewController.evaluateJavascript(source: "forward()");
  }

  void refreshToc() {
    webViewController.evaluateJavascript(source: "refreshToc()");
  }

  Future<String> theChapterContent() async =>
      await webViewController.evaluateJavascript(source: "theChapterContent()");

  Future<String> _getCurrentChapterContent({int? maxCharacters}) async {
    final raw = await theChapterContent();
    return _normalizeChapterContent(raw, maxCharacters);
  }

  Future<String> _getChapterContentByHref(
    String href, {
    int? maxCharacters,
  }) async {
    if (href.isEmpty) {
      return '';
    }

    final result = await webViewController.callAsyncJavaScript(
      functionBody:
          'return await getChapterContentByHref("${href.replaceAll('"', '\\"')}")',
    );

    final value = result?.value;
    if (value is String) {
      return _normalizeChapterContent(value, maxCharacters);
    }
    return '';
  }

  String _normalizeChapterContent(String? content, int? maxCharacters) {
    if (content == null || content.isEmpty) {
      return '';
    }
    final trimmed = content.trim();
    if (maxCharacters != null &&
        maxCharacters > 0 &&
        trimmed.length > maxCharacters) {
      return trimmed.substring(0, maxCharacters);
    }
    return trimmed;
  }

  void _registerChapterContentBridge() {
    ref
        .read(chapterContentBridgeProvider.notifier)
        .state = ChapterContentHandlers(
      fetchCurrentChapter: ({int? maxCharacters}) =>
          _getCurrentChapterContent(maxCharacters: maxCharacters),
      fetchChapterByHref: (href, {int? maxCharacters}) =>
          _getChapterContentByHref(href, maxCharacters: maxCharacters),
    );
  }

  Future<void> _handleExternalLink(dynamic rawLink) async {
    String? normalizeExternalLink(dynamic raw) {
      if (raw == null) return null;
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is Map && raw['href'] is String) {
        final href = raw['href'].toString().trim();
        return href.isEmpty ? null : href;
      }
      return null;
    }

    final link = normalizeExternalLink(rawLink);
    if (!mounted || link == null) return;

    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme.isEmpty || uri.scheme == 'javascript') return;

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("打开外部链接"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("是否打开以下链接？"),
              const SizedBox(height: 8),
              SelectableText(link),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("打开"),
            ),
          ],
        );
      },
    );

    if (shouldOpen == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void onClick(Map<String, dynamic> location) {
    readingPageKey.currentState?.resetAwakeTimer();
    if (contextMenuEntry != null) {
      removeOverlay();
      return;
    }
    final x = location['x'];
    final y = location['y'];
    final part = coordinatesToPart(x, y);

    PageTurningType action;
    final currentPageTurningType = AppConfig.getPageTurningType();
    final pageTurningType = pageTurningTypes[currentPageTurningType];
    action = pageTurningType[part];

    // 简单的逻辑处理
    if (action == PageTurningType.prev) {
      prevPage();
    } else if (action == PageTurningType.next) {
      nextPage();
    } else if (action == PageTurningType.menu) {
      widget.showOrHideAppBarAndBottomBar(true);
    }
  }

  Future<void> renderAnnotations(InAppWebViewController controller) async {
    List<BookNote> annotationList = await ref
        .read(bookNoteRepositoryProvider)
        .selectBookNotesByBookId(widget.book.id);
    String allAnnotations = jsonEncode(
      annotationList.map((e) => e.toFoliateJson()).toList(),
    ).replaceAll('\'', '\\\'');

    // 直接将 allAnnotations 作为参数传递给 renderAnnotations 函数
    controller.evaluateJavascript(source: 'renderAnnotations($allAnnotations)');
  }

  void getThemeColor() {
    textColor = "FF343434";
    backgroundColor = "00FFFFFF";
  }

  Future<void> setHandler(InAppWebViewController controller) async {
    controller.addJavaScriptHandler(
      handlerName: 'onLoadEnd',
      callback: (args) => widget.onLoadEnd(),
    );

    controller.addJavaScriptHandler(
      handlerName: 'onRelocated',
      callback: (args) {
        Map<String, dynamic> location = args[0];
        if (cfi == location['cfi']) return;
        setState(() {
          cfi = location['cfi'] ?? '';
          percentage =
              double.tryParse(location['percentage'].toString()) ?? 0.0;
          chapterTitle = location['chapterTitle'] ?? '';
          chapterHref = location['chapterHref'] ?? '';
          chapterCurrentPage = location['chapterCurrentPage'] ?? 0;
          chapterTotalPages = location['chapterTotalPages'] ?? 0;
          bookmarkExists = location['bookmark']['exists'] ?? false;
          bookmarkCfi = location['bookmark']['cfi'] ?? '';
        });
        widget.updateParent();
        saveReadingProgress();
        readingPageKey.currentState?.resetAwakeTimer();
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onClick',
      callback: (args) => onClick(args[0]),
    );

    controller.addJavaScriptHandler(
      handlerName: 'onSetToc',
      callback: (args) {
        List<dynamic> t = args[0];
        final tocList = t.map((i) => Toc.fromJson(i)).toList();
        ref.read(bookTocProvider.notifier).setToc(tocList);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onSelectionEnd',
      callback: (args) {
        if (!mounted) return;
        removeOverlay();
        Map<String, dynamic> location = args[0];
        String cfi = location['cfi'];
        String text = location['text'];
        bool footnote = location['footnote'];
        final rawContextText = location['contextText']?.toString();
        _lastSelectionContextText = (rawContextText?.trim().isEmpty ?? true)
            ? null
            : rawContextText;
        double left = (location['pos']['left'] as num).toDouble();
        double top = (location['pos']['top'] as num).toDouble();
        double right = (location['pos']['right'] as num).toDouble();
        double bottom = (location['pos']['bottom'] as num).toDouble();

        // TODO: Get writing mode from book settings or detect automatically
        // For now, default to horizontal axis
        showContextMenu(
          context,
          left,
          top,
          right,
          bottom,
          text,
          cfi,
          null,
          footnote,
          Axis.horizontal, // writingMode.isVertical ? Axis.vertical : Axis.horizontal,
          contextText: _lastSelectionContextText,
        );
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onSelectionCleared',
      callback: (args) {
        if (!mounted) return;
        if (_selectionClearLocked) {
          _selectionClearPending = true;
          return;
        }
        _lastSelectionContextText = null;
        removeOverlay();
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'renderAnnotations',
      callback: (args) {
        renderAnnotations(controller);
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onAnnotationClick',
      callback: (args) {
        if (!mounted) return;
        Map<String, dynamic> annotation = args[0];

        // TODO: Implement TTS functionality
        // if (annotation['annotation'] == null) {
        //   // Check if TTS is active and the click is on the currently read text
        //   final currentTtsState = TtsHandler().ttsStateNotifier.value;
        //   if (currentTtsState == TtsStateEnum.playing ||
        //       currentTtsState == TtsStateEnum.paused) {
        //     if (currentTtsState == TtsStateEnum.playing) {
        //       audioHandler.pause();
        //     } else {
        //       audioHandler.play();
        //     }
        //     return;
        //   }
        // }

        int id = annotation['annotation']['id'];
        String cfi = annotation['annotation']['value'];
        String note = annotation['annotation']['note'];
        final rawContextText = annotation['contextText']?.toString();
        _lastSelectionContextText = (rawContextText?.trim().isEmpty ?? true)
            ? null
            : rawContextText;
        double left = (annotation['pos']['left'] as num).toDouble();
        double top = (annotation['pos']['top'] as num).toDouble();
        double right = (annotation['pos']['right'] as num).toDouble();
        double bottom = (annotation['pos']['bottom'] as num).toDouble();

        // TODO: Get writing mode from book settings or detect automatically
        // For now, default to horizontal axis
        showContextMenu(
          context,
          left,
          top,
          right,
          bottom,
          note,
          cfi,
          id,
          false,
          Axis.horizontal, // writingMode.isVertical ? Axis.vertical : Axis.horizontal,
          contextText: _lastSelectionContextText,
        );
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'handleBookmark',
      callback: (args) async {
        if (!mounted) return;
        Map<String, dynamic> detail = args[0]['detail'];
        bool remove = args[0]['remove'];
        String bookmarkCfiVal = detail['cfi'] ?? '';
        String content = detail['content'];

        // 关键修复点：使用带 bookId 的 bookmarkProvider
        final bookmarkNotifier = ref.read(
          bookNoteNotifierProvider(widget.book.id).notifier,
        );

        if (remove) {
          await bookmarkNotifier.removeNote(cfi: bookmarkCfiVal);
          if (!mounted) return;
          setState(() {
            bookmarkCfi = '';
            bookmarkExists = false;
          });
        } else {
          final bookmark = BookNote(
            bookId: widget.book.id,
            cfi: bookmarkCfiVal,
            content: content,
            type: 'bookmark',
            chapter: chapterTitle,
            color: "0",
            createTime: DateTime.now(),
            updateTime: DateTime.now(),
          );
          final realBookmark = await bookmarkNotifier.addNote(bookmark);
          if (!mounted) return;
          setState(() {
            bookmarkCfi = bookmarkCfiVal;
            bookmarkExists = true;
          });
          addBookmark(realBookmark);
        }
      },
    );

    // 其他 handler 保持原样，省略部分以保证响应简洁
  }

  Future<void> onWebViewCreated(InAppWebViewController controller) async {
    webViewController = controller;
    setHandler(controller);
    _registerChapterContentBridge();
  }

  void removeOverlay() {
    if (contextMenuEntry != null && contextMenuEntry!.mounted) {
      contextMenuEntry!.remove();
      contextMenuEntry = null;
    }
  }

  @override
  void initState() {
    super.initState();
    readService(AppServices.statusbarService).hideStatusBar();
    book = widget.book;
    getThemeColor();
    contextMenu = ContextMenu(
      settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true),
    );
  }

  Future<void> saveReadingProgress() async {
    if (cfi == '' || widget.cfi != null) return;
    Book updatedBook = widget.book.copyWith(
      lastReadPosition: cfi,
      readingPercentage: percentage,
    );
    await ref.read(bookshelfBooksProvider.notifier).updateBook(updatedBook);
  }

  Widget readingInfoWidget() {
    if (chapterCurrentPage == 0 && percentage == 0.0) {
      return const SizedBox();
    }

    final readingInfoColor = Color(int.parse('0x$textColor')).withAlpha(150);
    final iconColor = Color(int.parse('0x$textColor'));

    Widget getWidget(ReadingInfoEnum readingInfoEnum, TextStyle textStyle) {
      final batteryTextStyle = TextStyle(
        color: iconColor,
        fontSize: (textStyle.fontSize ?? 10) - 1,
      );
      final batteryIconSize = (textStyle.fontSize ?? 10) * 2.7;

      final chapterTitleWidget = Text(
        (chapterCurrentPage == 1 ? widget.book.title : chapterTitle),
        style: textStyle,
      );

      final chapterProgressWidget = Text(
        '$chapterCurrentPage/$chapterTotalPages',
        style: textStyle,
      );

      final bookProgressWidget = Text(
        '${(percentage * 100).toStringAsFixed(2)}%',
        style: textStyle,
      );

      final timeWidget = MinuteClock(textStyle: textStyle);

      final batteryWidget = FutureBuilder(
        future: Battery().batteryLevel,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    (textStyle.fontSize ?? 10) * 0.08,
                    2,
                    0,
                  ),
                  child: Text('${snapshot.data}', style: batteryTextStyle),
                ),
                Icon(
                  HeroIcons.battery_0,
                  size: batteryIconSize,
                  color: iconColor,
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        },
      );

      Widget batteryAndTimeWidget() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [batteryWidget, const SizedBox(width: 5), timeWidget],
      );

      switch (readingInfoEnum) {
        case ReadingInfoEnum.chapterTitle:
          return chapterTitleWidget;
        case ReadingInfoEnum.chapterProgress:
          return chapterProgressWidget;
        case ReadingInfoEnum.bookProgress:
          return bookProgressWidget;
        case ReadingInfoEnum.battery:
          return batteryWidget;
        case ReadingInfoEnum.time:
          return timeWidget;
        case ReadingInfoEnum.batteryAndTime:
          return batteryAndTimeWidget();
        case ReadingInfoEnum.none:
          return const SizedBox(width: 30);
      }
    }

    final readingInfo = ReadingInfoModel();

    final headerTextStyle = TextStyle(
      color: readingInfoColor,
      fontSize: readingInfo.header.fontSize,
    );
    final footerTextStyle = TextStyle(
      color: readingInfoColor,
      fontSize: readingInfo.footer.fontSize,
    );

    List<Widget> headerWidgets = [
      getWidget(readingInfo.header.left, headerTextStyle),
      getWidget(readingInfo.header.center, headerTextStyle),
      getWidget(readingInfo.header.right, headerTextStyle),
    ];

    List<Widget> footerWidgets = [
      getWidget(readingInfo.footer.left, footerTextStyle),
      getWidget(readingInfo.footer.center, footerTextStyle),
      getWidget(readingInfo.footer.right, footerTextStyle),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: readingInfo.header.verticalMargin,
            left: readingInfo.header.leftMargin,
            right: readingInfo.header.rightMargin,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: headerWidgets,
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.only(
            bottom: readingInfo.footer.verticalMargin,
            left: readingInfo.footer.leftMargin,
            right: readingInfo.footer.rightMargin,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: footerWidgets,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    StatusbarService.instance.showStatusBar();
    saveReadingProgress();
    removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String uri = Uri.encodeComponent(widget.book.fileFullPath);
    String url = 'http://127.0.0.1:${AppConfig.getLastServerPort()}/book/$uri';
    String initialCfi = widget.cfi ?? widget.book.lastReadPosition;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            color: Colors.transparent,
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(generateUrl(url, initialCfi)),
              ),
              initialSettings: InAppWebViewSettings(
                transparentBackground: true,
                backgroundColor: 0x00000000,
              ),
              onLoadStop: (controller, uri) => onWebViewCreated(controller),
              contextMenu: contextMenu, // 确保应用自定义的 ContextMenu 配置以隐藏系统菜单
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
          ),
          readingInfoWidget(),
        ],
      ),
    );
  }

  int coordinatesToPart(double x, double y) {
    int row = (y * 3).floor().clamp(0, 2);
    int col = (x * 3).floor().clamp(0, 2);
    return row * 3 + col;
  }
}
