import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bt_client.dart';
import 'main.dart';
import 'widgets/dpad.dart';
import 'widgets/numpad.dart';

class RemotePage extends StatefulWidget {
  final BtClient client;
  final String initialSerial;
  final int? initialDisplay;
  final VoidCallback onToggleTheme;

  const RemotePage({
    super.key,
    required this.client,
    required this.initialSerial,
    required this.initialDisplay,
    required this.onToggleTheme,
  });

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  late String _serial;
  int? _display;

  List<AdbDevice> _devices = [];
  List<AdbDisplay> _displays = [];
  bool _refreshing = false;

  bool _showNumpad = false;
  String? _toast;
  bool _toastIsError = false;

  @override
  void initState() {
    super.initState();
    _serial = widget.initialSerial;
    _display = widget.initialDisplay;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final devs = await widget.client.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devs;
        if (!devs.any((d) => d.serial == _serial) && devs.isNotEmpty) {
          _serial = devs.firstWhere((d) => d.online, orElse: () => devs.first).serial;
          _display = null;
        }
      });
      await _loadDisplays();
    } catch (e, st) {
      debugPrint('dpadr: refresh failed: $e\n$st');
      _flash('refresh failed', true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadDisplays() async {
    try {
      final list = await widget.client.listDisplays(_serial);
      if (!mounted) return;
      setState(() {
        _displays = list;
        if (_display != null && !list.any((d) => d.id == _display)) {
          _display = null;
        }
      });
    } catch (e, st) {
      debugPrint('dpadr: listDisplays failed: $e\n$st');
      if (mounted) setState(() => _displays = []);
    }
  }

  void _send(String key) {
    HapticFeedback.selectionClick();
    widget.client.sendKey(_serial, key, display: _display).then((_) {
      _flash(key, false);
    }).catchError((Object e, StackTrace st) {
      debugPrint('dpadr: sendKey failed (key=$key): $e\n$st');
      _flash('send failed', true);
    });
  }

  Future<void> _sendText(String text) async {
    if (text.isEmpty) return;
    try {
      await widget.client.sendText(_serial, text, display: _display);
      _flash('sent ${text.length} chars', false);
    } catch (e, st) {
      debugPrint('dpadr: sendText failed: $e\n$st');
      _flash('send failed', true);
    }
  }

  Future<void> _openTextSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DpadrThemeProvider.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _TypeSheet(),
    );
    if (result != null && result.isNotEmpty) {
      await _sendText(result);
    }
  }

  void _flash(String msg, bool err) {
    if (!mounted) return;
    setState(() {
      _toast = msg;
      _toastIsError = err;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _toast == msg) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _RemoteHeader(
                peer: widget.client.peerName ?? 'unknown',
                connected: widget.client.state == BtState.connected,
                isDark: isDark,
                onBack: () {
                  widget.client.disconnect();
                  Navigator.of(context).pop();
                },
                onToggleTheme: widget.onToggleTheme,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SelectorBar(
                devices: _devices,
                serial: _serial,
                displays: _displays,
                display: _display,
                refreshing: _refreshing,
                onRefresh: _refreshing ? null : _refresh,
                onSelectSerial: (v) {
                  if (v == null || v == _serial) return;
                  setState(() {
                    _serial = v;
                    _display = null;
                  });
                  _loadDisplays();
                },
                onSelectDisplay: (v) => setState(() => _display = v),
              ),
            ),
            const SizedBox(height: 12),
            _ToastSlot(
              text: _toast,
              isError: _toastIsError,
              accent: p.accent,
              muted: p.muted,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Center(child: Dpad(onKey: _send)),
                    const SizedBox(height: 24),
                    _NavRow(onKey: _send),
                    const SizedBox(height: 18),
                    _ActionPills(
                      numpadActive: _showNumpad,
                      onToggleNumpad: () => setState(() => _showNumpad = !_showNumpad),
                      onOpenType: _openTextSheet,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _showNumpad
                          ? Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Numpad(onKey: _send),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────── HEADER ───────────

class _RemoteHeader extends StatelessWidget {
  final String peer;
  final bool connected;
  final bool isDark;
  final VoidCallback onBack;
  final VoidCallback onToggleTheme;
  const _RemoteHeader({
    required this.peer,
    required this.connected,
    required this.isDark,
    required this.onBack,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        _MiniBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: connected ? const Color(0xFF22C55E) : p.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    connected ? 'Connected' : 'Offline',
                    style: t.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                peer,
                style: t.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _MiniBtn(
          icon: isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          onTap: onToggleTheme,
        ),
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: dpadrShadows(context, depth: 0.4),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: p.ink),
        ),
      ),
    );
  }
}

// ─────────── SELECTOR ───────────

class _SelectorBar extends StatelessWidget {
  final List<AdbDevice> devices;
  final String serial;
  final List<AdbDisplay> displays;
  final int? display;
  final bool refreshing;
  final VoidCallback? onRefresh;
  final ValueChanged<String?> onSelectSerial;
  final ValueChanged<int?> onSelectDisplay;

  const _SelectorBar({
    required this.devices,
    required this.serial,
    required this.displays,
    required this.display,
    required this.refreshing,
    required this.onRefresh,
    required this.onSelectSerial,
    required this.onSelectDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final hasDevices = devices.isNotEmpty;
    final showDisplays = displays.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: dpadrShadows(context, depth: 0.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: hasDevices
                ? _Drop<String>(
                    value: devices.any((d) => d.serial == serial) ? serial : devices.first.serial,
                    onChanged: onSelectSerial,
                    items: [
                      for (final d in devices)
                        _DropEntry(
                          value: d.serial,
                          label: d.serial,
                          enabled: d.online,
                          dot: d.online ? const Color(0xFF22C55E) : p.muted,
                        ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text('No devices', style: Theme.of(context).textTheme.bodySmall),
                  ),
          ),
          if (showDisplays) ...[
            Container(width: 1, height: 22, color: p.line),
            Expanded(
              child: _Drop<int?>(
                value: display,
                onChanged: onSelectDisplay,
                items: [
                  _DropEntry(value: null, label: 'Default', dot: p.muted),
                  for (final d in displays)
                    _DropEntry(value: d.id, label: '${d.name} · ${d.id}', dot: p.accent),
                ],
              ),
            ),
          ],
          Material(
            color: p.sunken,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: refreshing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8, color: p.muted),
                        )
                      : Icon(Icons.refresh_rounded, size: 16, color: p.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropEntry<T> {
  final T value;
  final String label;
  final Color dot;
  final bool enabled;
  _DropEntry({
    required this.value,
    required this.label,
    required this.dot,
    this.enabled = true,
  });
}

class _Drop<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T?> onChanged;
  final List<_DropEntry<T>> items;
  const _Drop({required this.value, required this.onChanged, required this.items});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: items.any((it) => it.value == value) ? value : items.first.value,
        isExpanded: true,
        isDense: true,
        icon: Icon(Icons.unfold_more_rounded, size: 18, color: p.muted),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: p.card,
        style: GoogleFonts.dmMono(fontSize: 12.5, color: p.ink, letterSpacing: 0.3),
        items: [
          for (final it in items)
            DropdownMenuItem<T>(
              value: it.value,
              enabled: it.enabled,
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: it.dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      it.label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmMono(
                        fontSize: 12.5,
                        color: it.enabled ? p.ink : p.muted,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

// ─────────── TOAST ───────────

class _ToastSlot extends StatelessWidget {
  final String? text;
  final bool isError;
  final Color accent;
  final Color muted;
  const _ToastSlot({
    required this.text,
    required this.isError,
    required this.accent,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: text == null
            ? const SizedBox.shrink()
            : Row(
                key: ValueKey(text),
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isError ? accent : muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    text!,
                    style: GoogleFonts.dmMono(
                      fontSize: 11.5,
                      color: isError ? accent : muted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─────────── NAV ROW ───────────

class _NavRow extends StatelessWidget {
  final void Function(String key) onKey;
  const _NavRow({required this.onKey});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _NavCard(label: 'Back', icon: Icons.arrow_back_rounded, onTap: () => onKey('BACK'))),
        const SizedBox(width: 10),
        Expanded(child: _NavCard(label: 'Home', icon: Icons.home_rounded, onTap: () => onKey('HOME'))),
        const SizedBox(width: 10),
        Expanded(child: _NavCard(label: 'Recents', icon: Icons.dashboard_rounded, onTap: () => onKey('RECENTS'))),
      ],
    );
  }
}

class _NavCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NavCard({required this.label, required this.icon, required this.onTap});

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    return Listener(
      onPointerDown: (_) {
        setState(() => _pressed = true);
        HapticFeedback.lightImpact();
      },
      onPointerUp: (_) {
        if (_pressed) {
          setState(() => _pressed = false);
          widget.onTap();
        }
      },
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _pressed ? p.sunken : p.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: _pressed ? null : dpadrShadows(context, depth: 0.35),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20, color: p.ink),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────── ACTION PILLS ───────────

class _ActionPills extends StatelessWidget {
  final bool numpadActive;
  final VoidCallback onToggleNumpad;
  final VoidCallback onOpenType;
  const _ActionPills({
    required this.numpadActive,
    required this.onToggleNumpad,
    required this.onOpenType,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Pill(
          active: numpadActive,
          icon: Icons.dialpad_rounded,
          label: 'Numpad',
          onTap: onToggleNumpad,
        ),
        const SizedBox(width: 10),
        _Pill(
          active: false,
          icon: Icons.keyboard_rounded,
          label: 'Type',
          onTap: onOpenType,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Pill({required this.active, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final fg = active ? p.accent : p.ink;
    return Material(
      color: active ? p.accentSoft : p.card,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: active ? null : dpadrShadows(context, depth: 0.3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      color: fg,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────── TYPE SHEET ───────────

class _TypeSheet extends StatefulWidget {
  @override
  State<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<_TypeSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_sending) return;
    final text = _ctrl.text;
    setState(() => _sending = true);
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.keyboard_rounded, size: 18, color: p.accent),
                const SizedBox(width: 10),
                Text('Type to device', style: t.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Send text to whatever field is focused on the device.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              maxLines: 4,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.dmMono(fontSize: 14, color: p.ink),
              decoration: const InputDecoration(hintText: 'Type something…'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
