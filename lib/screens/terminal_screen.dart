import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import '../models/device.dart';
import '../ssh/persistent_terminal.dart';
import '../ssh/native_terminal.dart';
import '../ssh/ssh_session.dart';

int? terminalCtrlCode(int rune) {
  if (rune >= 65 && rune <= 90) return rune - 64;
  if (rune >= 97 && rune <= 122) return rune - 96;
  return const {32: 0, 64: 0, 91: 27, 92: 28, 93: 29, 94: 30, 95: 31}[rune];
}

List<int> terminalModifiedInput(
  String data, {
  required bool ctrl,
  required bool alt,
}) => [
  if (alt) 27,
  for (final rune in data.runes)
    ...ctrl && terminalCtrlCode(rune) != null
        ? [terminalCtrlCode(rune)!]
        : utf8.encode(String.fromCharCode(rune)),
];

String terminalComposerCommand(String text, {required bool windows}) {
  if (windows && text.contains('\n')) {
    final encoded = base64Encode(utf8.encode(text));
    return "& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded'))))\r";
  }
  return '${text.replaceAll('\r\n', '\n').replaceAll('\n', '\r')}\r';
}

class TerminalScreen extends StatefulWidget {
  final Device device;
  final SshSession? session;
  const TerminalScreen({super.key, required this.device, this.session});
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _controller = TerminalController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _viewKey = GlobalKey<TerminalViewState>();
  bool _showExtraKeys = true;
  late final SshSession _session;
  PersistentTerminal? _persistent;
  Terminal? get _terminal => _persistent?.terminal;
  bool _starting = true, _ctrl = false, _alt = false;
  bool _windows = false;
  double _fontSize = 13;
  String? _error;
  bool get _ready =>
      !_starting && _session.isConnected && (_persistent?.isStarted ?? false);
  List<String> get _history => _persistent?.recentCommands ?? <String>[];

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? sshSession;
    _session.addListener(_connectionChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _fontSize = prefs.getDouble('terminal_font_size') ?? 13;
      _windows = widget.device.shellStyle == 'windows';
      if (widget.device.shellStyle == 'auto') {
        final output = await _session.run(
          'uname -s',
          timeout: const Duration(seconds: 10),
        );
        _windows = !utf8
            .decode(output, allowMalformed: true)
            .toLowerCase()
            .contains('linux');
      }
      if (!mounted) return;
      final persistent = _session.terminalFor(isWindows: _windows);
      _persistent = persistent;
      persistent.state.addListener(_terminalChanged);
      persistent.terminal.native?.onPasteRequest = _paste;
      persistent.terminal.onOutput = _sendOutput;
      persistent.terminal.onResize = (w, h, pw, ph) => persistent.resize(
        width: w,
        height: h,
        pixelWidth: pw,
        pixelHeight: ph,
      );
      await _start();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _starting = false;
        });
      }
    }
  }

  void _connectionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session.isConnected &&
        !_starting &&
        (_persistent?.isClosed ?? false)) {
      unawaited(_start());
    }
  }

  void _terminalChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (_persistent == null) {
        await _initialize();
        return;
      }
      await _persistent!.start();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  void _sendOutput(String data) {
    if (!_ready || data.isEmpty) return;
    _persistent!.writeBytes(
      terminalModifiedInput(data, ctrl: _ctrl, alt: _alt),
    );
    if (_ctrl || _alt) {
      setState(() {
        _ctrl = false;
        _alt = false;
      });
    }
  }

  void _key(TerminalKey key) {
    if (!_ready) return;
    final ctrl = _ctrl, alt = _alt;
    // keyInput already encodes modifiers. Clear them before onOutput to avoid
    // doubling ESC or rewriting the escape sequence of an arrow key.
    setState(() {
      _ctrl = false;
      _alt = false;
    });
    _terminal!.keyInput(key, ctrl: ctrl, alt: alt);
  }

  void _interrupt() {
    if (!_ready) return;
    setState(() {
      _ctrl = false;
      _alt = false;
    });
    _persistent!.writeBytes([3]);
  }

  void _literal(String text) {
    if (_ready) _sendOutput(text);
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _copy({bool all = false}) async {
    final terminal = _terminal;
    if (terminal == null) return;
    if (_persistent?.terminal.native != null) {
      final text = await _persistent!.terminal.native!.text(all: all);
      if (text.isEmpty) {
        if (mounted) _notice('Long-press and drag to select text first.');
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _notice(all ? 'Scrollback copied' : 'Selection copied');
      return;
    }
    final selection = _controller.selection;
    if (!all && selection == null) {
      _notice('Long-press and drag to select text first.');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: terminal.buffer.getText(all ? null : selection)),
    );
    if (mounted) _notice(all ? 'Scrollback copied' : 'Selection copied');
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted || !_ready || text == null || text.isEmpty) return;
    if (text.contains('\n') || text.contains('\r')) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paste multiple lines?'),
          content: const Text(
            'Newlines can execute commands immediately in the remote shell. Use the command composer to review or edit them first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Paste'),
            ),
          ],
        ),
      );
      if (!mounted || !_ready || confirmed != true) return;
    }
    setState(() {
      _ctrl = false;
      _alt = false;
    });
    _terminal!.paste(text.replaceAll('\r\n', '\n'));
    if (_persistent?.terminal.native != null) {
      _persistent!.terminal.native!.send('keyboard', {'show': true});
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _compose() async {
    final editor = TextEditingController();
    final result = await showDialog<({String text, bool run})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('Command composer'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editor,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => update(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Edit a command or paste a script',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_history.isNotEmpty)
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Recent commands (this session)'),
                    items: _history
                        .map(
                          (text) => DropdownMenuItem(
                            value: text,
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (text) {
                      if (text != null) {
                        update(() {
                          editor.text = text;
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  editor.text.contains('\n') || editor.text.contains('\r')
                  ? null
                  : () =>
                        Navigator.pop(context, (text: editor.text, run: false)),
              child: const Text('Insert'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (text: editor.text, run: true)),
              child: const Text('Run'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    editor.dispose();
    if (!mounted || !_ready || result == null || result.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _ctrl = false;
      _alt = false;
    });
    if (result.run) {
      _persistent!.write(
        terminalComposerCommand(result.text, windows: _windows),
      );
      _history.remove(result.text);
      _history.insert(0, result.text);
      if (_history.length > 20) _history.removeLast();
    } else {
      _terminal!.paste(result.text);
    }
    if (_persistent?.terminal.native != null) {
      _persistent!.terminal.native!.send('keyboard', {'show': true});
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _restart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart shell?'),
        content: const Text(
          'This closes the current shell and its running commands. Scrollback stays available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _persistent?.close();
    if (mounted) await _start();
  }

  Future<void> _setFont(double size) async {
    setState(() {
      _fontSize = size.clamp(9, 24);
    });
    _persistent?.terminal.native?.send('style', {'fontSize': _fontSize});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_font_size', _fontSize);
  }

  Future<void> _clear() async {
    _controller.clearSelection();
    if (_windows && _ready) {
      // Clear ConPTY's remote buffer as well; otherwise keyboard resize can
      // repaint the previous screen and undo a local-only clear.
      _persistent!.writeBytes([3, 21]);
      _persistent!.write("[Console]::Clear()\r");
    } else if (_ready) {
      _persistent!.writeBytes([12]);
    }
    _terminal?.write('\x1b[2J\x1b[H\x1b[3J');
  }

  @override
  void dispose() {
    _session.removeListener(_connectionChanged);
    _persistent?.state.removeListener(_terminalChanged);
    if (_persistent != null) {
      _persistent!.terminal.native?.onPasteRequest = null;
      _terminal!.onOutput = null;
      _terminal!.onResize = null;
    }
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _button(String label, VoidCallback callback, {bool active = false}) =>
      Expanded(
        child: ExcludeFocus(
          child: Semantics(
            button: true,
            label: label,
            selected: active,
            child: SizedBox(
              height: 36,
              child: Material(
                color: active
                    ? const Color(0xFF454545)
                    : const Color(0xFF202020),
                child: InkWell(
                  onTap: _ready ? callback : null,
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _ready ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _extraKeys() => Column(
    key: const ValueKey('terminal-extra-keys'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          _button('ESC', () => _key(TerminalKey.escape)),
          _button('/', () => _literal('/')),
          _button('-', () => _literal('-')),
          _button('HOME', () => _key(TerminalKey.home)),
          _button('↑', () => _key(TerminalKey.arrowUp)),
          _button('END', () => _key(TerminalKey.end)),
          _button('PGUP', () => _key(TerminalKey.pageUp)),
        ],
      ),
      Row(
        children: [
          _button('TAB', () => _key(TerminalKey.tab)),
          _button(
            'CTRL',
            () => setState(() {
              _ctrl = !_ctrl;
            }),
            active: _ctrl,
          ),
          _button(
            'ALT',
            () => setState(() {
              _alt = !_alt;
            }),
            active: _alt,
          ),
          _button('←', () => _key(TerminalKey.arrowLeft)),
          _button('↓', () => _key(TerminalKey.arrowDown)),
          _button('→', () => _key(TerminalKey.arrowRight)),
          _button('PGDN', () => _key(TerminalKey.pageDown)),
        ],
      ),
    ],
  );

  PopupMenuItem<String> _menuItem(
    String value,
    String label,
    IconData icon, {
    bool enabled = true,
  }) => PopupMenuItem(
    value: value,
    enabled: enabled,
    child: Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    ),
  );

  Future<void> _terminalOptions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Terminal options'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Text size')),
                    IconButton(
                      tooltip: 'Smaller text',
                      onPressed: () {
                        _setFont(_fontSize - 1);
                        updateDialog(() {});
                      },
                      icon: const Icon(Icons.remove),
                    ),
                    Text('${_fontSize.round()}'),
                    IconButton(
                      tooltip: 'Larger text',
                      onPressed: () {
                        _setFont(_fontSize + 1);
                        updateDialog(() {});
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Extra keys'),
                  value: _showExtraKeys,
                  onChanged: (value) {
                    setState(() => _showExtraKeys = value);
                    updateDialog(() {});
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.clear_all),
                  title: const Text('Clear screen'),
                  enabled: _ready,
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _clear();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Restart shell'),
                  enabled: !_starting && _session.isConnected,
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _restart();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Open-source licenses'),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    showLicensePage(context: this.context);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final status = _starting
        ? 'Starting…'
        : !_session.isConnected
        ? 'Disconnected'
        : _ready
        ? '${widget.device.username} · ${_windows ? 'PowerShell' : 'Shell'}'
        : 'Shell closed';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.name, style: const TextStyle(fontSize: 15)),
            Text(
              status,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'keyboard':
                  if (_persistent?.terminal.native != null) {
                    _persistent!.terminal.native!.send('keyboard', {
                      'show': !keyboardVisible,
                    });
                  } else if (keyboardVisible) {
                    _viewKey.currentState?.closeKeyboard();
                  } else {
                    _viewKey.currentState?.requestKeyboard();
                  }
                case 'extra':
                  setState(() {
                    _showExtraKeys = !_showExtraKeys;
                  });
                case 'interrupt':
                  _interrupt();
                case 'enter':
                  _key(TerminalKey.enter);
                case 'paste':
                  _paste();
                case 'copy':
                  _copy();
                case 'copyAll':
                  _copy(all: true);
                case 'compose':
                  _compose();
                case 'clear':
                  _clear();
                case 'restart':
                  _restart();
                case 'larger':
                  _setFont(_fontSize + 1);
                case 'smaller':
                  _setFont(_fontSize - 1);
                case 'settings':
                  _terminalOptions();
                case 'licenses':
                  showLicensePage(context: context);
                case 'bottom':
                  if (_persistent?.terminal.native != null) {
                    _persistent!.terminal.native!.send('bottom');
                  } else if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
              }
            },
            itemBuilder: (_) => [
              _menuItem(
                'keyboard',
                keyboardVisible ? 'Hide keyboard' : 'Show keyboard',
                Icons.keyboard,
                enabled: _ready,
              ),
              _menuItem(
                'compose',
                'Command composer',
                Icons.edit_note,
                enabled: _ready,
              ),
              _menuItem('paste', 'Paste', Icons.content_paste, enabled: _ready),
              const PopupMenuDivider(),
              _menuItem('copy', 'Copy selection', Icons.content_copy),
              _menuItem('copyAll', 'Copy scrollback', Icons.copy_all),
              _menuItem('bottom', 'Latest output', Icons.vertical_align_bottom),
              const PopupMenuDivider(),
              _menuItem(
                'interrupt',
                'Interrupt · Ctrl+C',
                Icons.stop_circle_outlined,
                enabled: _ready,
              ),
              _menuItem(
                'enter',
                'Send Enter',
                Icons.keyboard_return,
                enabled: _ready,
              ),
              _menuItem('settings', 'Terminal options', Icons.tune),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_starting) const LinearProgressIndicator(),
            if (_error != null || (!_starting && !_ready))
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error ??
                              _persistent?.error ??
                              'Shell closed. Reopen it to continue.',
                        ),
                      ),
                      TextButton(
                        onPressed: _starting || !_session.isConnected
                            ? null
                            : _start,
                        child: const Text('Reopen'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _terminal == null
                  ? const Center(
                      child: Text(
                        'Opening terminal…',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : nativeTerminalSupported
                  ? PlatformViewLink(
                      viewType: 'remote_control/termux_terminal',
                      surfaceFactory: (context, controller) =>
                          AndroidViewSurface(
                            controller: controller as AndroidViewController,
                            gestureRecognizers: const {},
                            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                          ),
                      onCreatePlatformView: (params) {
                        final controller =
                            PlatformViewsService.initExpensiveAndroidView(
                              id: params.id,
                              viewType: 'remote_control/termux_terminal',
                              layoutDirection: TextDirection.ltr,
                              creationParams: {
                                'id': _persistent!.terminal.native!.id,
                                'fontSize': _fontSize,
                              },
                              creationParamsCodec: const StandardMessageCodec(),
                              onFocus: () => params.onFocusChanged(true),
                            );
                        controller.addOnPlatformViewCreatedListener(
                          params.onPlatformViewCreated,
                        );
                        unawaited(controller.create());
                        return controller;
                      },
                    )
                  : TerminalView(
                      _terminal!,
                      key: _viewKey,
                      theme: TerminalThemes.whiteOnBlack,
                      controller: _controller,
                      focusNode: _focus,
                      scrollController: _scroll,
                      textStyle: TerminalStyle(fontSize: _fontSize),
                      textScaler: TextScaler.noScaling,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      readOnly: !_ready,
                      deleteDetection: true,
                      keyboardType: TextInputType.visiblePassword,
                      alwaysShowCursor: true,
                    ),
            ),
            if (_showExtraKeys) _extraKeys(),
          ],
        ),
      ),
    );
  }
}
