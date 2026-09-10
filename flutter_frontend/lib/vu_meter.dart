import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum VuStatus { processing, success, error }

/// The single visual implementation used by all EKT wait states.
class VuMeter extends StatefulWidget {
  const VuMeter(
      {super.key,
      this.message = 'Aguarde…',
      this.progress,
      this.compact = false,
      this.status = VuStatus.processing,
      this.onRetry,
      this.fullScreen = false});
  final String message;
  final double? progress;
  final bool compact, fullScreen;
  final VuStatus status;
  final VoidCallback? onRetry;
  @override
  State<VuMeter> createState() => _VuMeterState();
}

class _VuMeterState extends State<VuMeter> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2300));
  double _progress = 0, _from = 0, _to = .45;
  bool _reduceMotion = false;
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final previous = _needle;
    _reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    _configure(previous: previous);
  }

  @override
  void didUpdateWidget(VuMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.progress != widget.progress) {
      _configure(previous: _needleFor(oldWidget));
    }
  }

  double get _needle => _needleFor(widget);

  double _needleFor(VuMeter configuration) {
    if (_reduceMotion)
      return configuration.status == VuStatus.success
          ? 1
          : configuration.progress == null
              ? .45
              : _progress;
    if (configuration.status == VuStatus.processing &&
        configuration.progress == null) {
      // A smooth, non-periodic-looking envelope. No synthetic percentage.
      final t = _motion.value * math.pi * 2;
      return .46 + .21 * math.sin(t) + .07 * math.sin(3 * t + .7);
    }
    return _from +
        (_to - _from) * Curves.easeInOutCubic.transform(_motion.value);
  }

  void _configure({required double previous}) {
    _motion.stop();
    _motion.duration = widget.status == VuStatus.success
        ? const Duration(milliseconds: 350)
        : widget.progress != null
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 2300);
    if (widget.progress != null)
      _progress = math.max(_progress, widget.progress!.clamp(0, 1));
    if (widget.status == VuStatus.error) {
      _from = _to = previous;
    } else if (widget.status == VuStatus.processing &&
        widget.progress == null) {
      if (!_reduceMotion) _motion.repeat();
    } else {
      _from = previous;
      _to = widget.status == VuStatus.success ? 1 : _progress;
      if (!_reduceMotion) _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.status == VuStatus.success ? 'Concluído' : widget.message;
    final content = Semantics(
      liveRegion: true,
      label:
          '${widget.status == VuStatus.error ? 'Erro' : widget.status == VuStatus.success ? 'Concluído' : 'O sistema está processando'}. $label',
      value: widget.progress == null ? null : '${(_progress * 100).round()}%',
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? math.min(constraints.maxWidth, widget.compact ? 156.0 : 280.0)
            : (widget.compact ? 156.0 : 280.0);
        final tiny = width < 80 ||
            (constraints.hasBoundedHeight && constraints.maxHeight < 64);
        final textBudget = tiny
            ? 0.0
            : (widget.compact ? 48.0 : 54.0) +
                (widget.progress != null ? 22 : 0) +
                (widget.status == VuStatus.error && widget.onRetry != null
                    ? 48
                    : 0);
        final dialHeight = math.min(
            width * .58,
            constraints.hasBoundedHeight
                ? math.max(0.0, constraints.maxHeight - textBudget)
                : width * .58);
        return SizedBox(
            width: width,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RepaintBoundary(
                  child: SizedBox(
                      width: width,
                      height: dialHeight,
                      child: AnimatedBuilder(
                          animation: _motion,
                          builder: (context, _) => CustomPaint(
                              painter: _VuPainter(_needle, widget.status))))),
              if (!tiny) ...[
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: widget.compact ? 14 : 16,
                        fontWeight: FontWeight.w600,
                        color: widget.status == VuStatus.error
                            ? const Color(0xFF9C2828)
                            : const Color(0xFF173449))),
                if (widget.progress != null &&
                    widget.status == VuStatus.processing)
                  Text('${(_progress * 100).round()}%',
                      style: const TextStyle(color: Color(0xFF173449))),
                if (widget.status == VuStatus.error && widget.onRetry != null)
                  TextButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente')),
              ],
            ]));
      }),
    );
    return widget.fullScreen ? Center(child: content) : content;
  }
}

class _VuPainter extends CustomPainter {
  const _VuPainter(this.value, this.status);
  final double value;
  final VuStatus status;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(size.width / 280, size.height / 162);
    canvas.save();
    canvas.translate(
        (size.width - 280 * scale) / 2, (size.height - 162 * scale) / 2);
    canvas.scale(scale);
    final frame = RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 278, 160), const Radius.circular(16));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF203B4D));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(6, 6, 268, 150), const Radius.circular(12)),
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF7E4), Color(0xFFE9D8B4)])
              .createShader(const Rect.fromLTWH(6, 6, 268, 150)));
    const pivot = Offset(140, 132);
    const radius = 108.0;
    const start = -math.pi * .92, sweep = math.pi * .84;
    final arc = Rect.fromCircle(center: pivot, radius: radius);
    canvas.drawArc(
        arc,
        start,
        sweep,
        false,
        Paint()
          ..color = const Color(0xFF252B2D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawArc(
        arc,
        start + sweep * .8,
        sweep * .2,
        false,
        Paint()
          ..color = const Color(0xFFB32F2F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
    for (var i = 0; i <= 20; i++) {
      final a = start + sweep * i / 20;
      final major = i % 4 == 0;
      final p = Paint()
        ..color = i >= 16 ? const Color(0xFFAC2828) : const Color(0xFF252B2D)
        ..strokeWidth = major ? 2 : 1;
      Offset point(double r) =>
          pivot + Offset(math.cos(a) * r, math.sin(a) * r);
      canvas.drawLine(point(radius - 2), point(radius - (major ? 14 : 8)), p);
      if (major)
        _text(canvas, '${i * 5}', point(radius - 25), 10,
            const Color(0xFF252B2D));
    }
    _text(canvas, 'VU', const Offset(140, 86), 18, const Color(0xFF203B4D));
    _text(canvas, 'EKT IA Systems', const Offset(140, 150), 10,
        const Color(0xFF203B4D));
    final a = start + sweep * value.clamp(0, 1);
    final tip = pivot + Offset(math.cos(a) * 99, math.sin(a) * 99);
    canvas.drawLine(
        pivot + const Offset(1, 2),
        tip + const Offset(1, 2),
        Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = 4);
    canvas.drawLine(
        pivot,
        tip,
        Paint()
          ..color = const Color(0xFFB52626)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(pivot, 6, Paint()..color = const Color(0xFF203B4D));
    canvas.drawCircle(pivot, 2, Paint()..color = const Color(0xFFDBC79F));
    canvas.restore();
  }

  void _text(
      Canvas canvas, String text, Offset center, double size, Color color) {
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: size, color: color, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_VuPainter old) =>
      old.value != value || old.status != status;
}

/// Task lifecycle is separate from the dial: no synthetic progress or HTTP retries.
class VuTask extends ChangeNotifier {
  VuTask(
      {required this.message, this.blocking = false, this.onRetry, this.alive});
  String message;
  final bool blocking;
  final bool Function()? alive;
  final Future<void> Function()? onRetry;
  VuStatus status = VuStatus.processing;
  double? progress;
  bool visible = false, finished = false;
  int inlineViews = 0, pauses = 0;
  bool mutationAccepted = false;
  Future<void> Function()? recovery;
  final Map<String, String> drafts = {};
  final Map<TextEditingController, String> draftControllers = {};
  DateTime? _shown;
  Timer? _delay;
  void start() {
    _delay?.cancel();
    _delay = Timer(const Duration(milliseconds: 300), () {
      if (!finished && pauses == 0) {
        visible = true;
        _shown = DateTime.now();
        notifyListeners();
      }
    });
  }

  void reportProgress(double value) {
    if (finished || !value.isFinite) return;
    progress = math.max(progress ?? 0, value.clamp(0, 1));
    notifyListeners();
  }

  void fail(Object error) {
    if (finished) return;
    _delay?.cancel();
    status = VuStatus.error;
    for (final entry in draftControllers.entries) {
      drafts[entry.value] = entry.key.text;
    }
    message = error is String
        ? error
        : error.toString().replaceFirst(
            RegExp(r'^(Exception|ApiFailure|TradeApiException):\s*'), '');
    if (message.isEmpty || message == '_')
      message = 'Não foi possível concluir. Tente novamente.';
    visible = true;
    notifyListeners();
  }

  Future<void> complete() async {
    _delay?.cancel();
    finished = true;
    if (status == VuStatus.error) {
      notifyListeners();
      return;
    }
    if (!visible) {
      notifyListeners();
      return;
    }
    final elapsed = DateTime.now().difference(_shown ?? DateTime.now());
    if (elapsed < const Duration(milliseconds: 600))
      await Future<void>.delayed(const Duration(milliseconds: 600) - elapsed);
    status = VuStatus.success;
    progress = 1;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    visible = false;
    notifyListeners();
  }

  void pause() {
    pauses++;
    visible = false;
    _delay?.cancel();
    notifyListeners();
  }

  void resume() {
    pauses = math.max(0, pauses - 1);
    if (pauses == 0 && !finished) start();
  }

  void dismiss() {
    visible = false;
    _delay?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }
}

class VuTasks extends ChangeNotifier {
  VuTasks._();
  static final instance = VuTasks._();
  static final _zoneKey = Object();
  final List<VuTask> tasks = [];
  final Map<(Object, String), Future<void>> _running = {};
  final Map<VuTask, Object> _owners = {};
  static VuTask? get current => Zone.current[_zoneKey] as VuTask?;
  static void fail(Object error) => current?.fail(error);
  static void mutationAccepted() {
    current?.mutationAccepted = true;
  }

  static TextEditingController draftController(
      String key, TextEditingController Function() create) {
    final controller = create();
    final task = current;
    if (task != null) {
      if (task.drafts.containsKey(key)) controller.text = task.drafts[key]!;
      task.draftControllers[controller] = key;
    }
    return controller;
  }

  static void disposeController(TextEditingController controller) {
    final task = current;
    final key = task?.draftControllers.remove(controller);
    if (key != null) task!.drafts[key] = controller.text;
    controller.dispose();
  }

  static void progress(double value) => current?.reportProgress(value);
  static Future<T> awaitUser<T>(Future<T> Function() action) async {
    final task = current;
    task?.pause();
    try {
      return await runZoned(action, zoneValues: {_zoneKey: null});
    } finally {
      task?.resume();
    }
  }

  static Future<void> run(
      {required Object owner,
      required String key,
      required String message,
      required Future<void> Function() action,
      bool blocking = false,
      bool silent = false,
      bool Function()? alive,
      Map<String, String>? retainedDrafts}) {
    final parent = current;
    if (parent != null) {
      if (parent.mutationAccepted && key.toLowerCase().contains('load'))
        parent.recovery = action;
      return action();
    }
    if (silent) return action();
    final registry = instance;
    final identity = (owner, key);
    final existing = registry._running[identity];
    if (existing != null) return existing;
    final done = Completer<void>();
    registry._running[identity] = done.future;
    late VuTask task;
    task = VuTask(
        message: message,
        blocking: blocking,
        alive: alive,
        onRetry: () async {
          final draftCopy = Map<String, String>.from(task.drafts);
          final retryAction = task.mutationAccepted ? task.recovery : action;
          task.dismiss();
          if (task.finished) registry._remove(task);
          if ((alive?.call() ?? true) && retryAction != null)
            await run(
                owner: owner,
                key: key,
                message: message,
                action: retryAction,
                blocking: blocking,
                alive: alive,
                retainedDrafts: draftCopy);
        });
    if (retainedDrafts != null) task.drafts.addAll(retainedDrafts);
    registry.tasks.add(task);
    registry._owners[task] = owner;
    task.addListener(registry._changed);
    task.start();
    registry._changed();
    () async {
      try {
        await runZoned(action, zoneValues: {_zoneKey: task});
      } catch (error, stack) {
        task.fail(error);
        if (!done.isCompleted) done.completeError(error, stack);
      } finally {
        await task.complete();
        registry._running.remove(identity);
        if (!task.visible) registry._remove(task);
        if (!done.isCompleted) done.complete();
      }
    }();
    return done.future;
  }

  void _changed() {
    // Task starts can occur in initState while the widget tree is building.
    scheduleMicrotask(() {
      notifyListeners();
    });
  }

  void _remove(VuTask task) {
    tasks.remove(task);
    _owners.remove(task);
    task.removeListener(_changed);
    if (task.inlineViews == 0) task.dispose();
    _changed();
  }

  void dismiss(VuTask task) {
    task.dismiss();
    if (task.finished) _remove(task);
  }

  VuTask? forContext(BuildContext context) {
    VuTask? match;
    context.visitAncestorElements((element) {
      if (element is StatefulElement) {
        for (final task in tasks.reversed) {
          if ((_owners[task] == element.state || _owners[task] == element) &&
              !task.finished) {
            match = task;
            return false;
          }
        }
      }
      return true;
    });
    return match;
  }
}

/// Inline placeholder; lifecycle is shared with the surrounding operation.
class VuLoading extends StatefulWidget {
  const VuLoading(
      {super.key, this.message = 'Carregando dados…', this.compact = false});
  final String message;
  final bool compact;
  @override
  State<VuLoading> createState() => _VuLoadingState();
}

class _VuLoadingState extends State<VuLoading> {
  VuTask? _task;
  bool _own = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_task == null) {
      _task = VuTasks.instance.forContext(context);
      _own = _task == null;
      _task ??= VuTask(message: widget.message)..start();
      _task!.inlineViews++;
      VuTasks.instance._changed();
    }
  }

  @override
  void dispose() {
    _task!.inlineViews--;
    if (_own || (_task!.finished && !VuTasks.instance.tasks.contains(_task)))
      _task!.dispose();
    VuTasks.instance._changed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _task!,
      builder: (context, _) => _task!.visible && !_task!.blocking
          ? VuMeter(
              message: _task!.message,
              progress: _task!.progress,
              compact: widget.compact,
              status: _task!.status,
              onRetry: _task!.onRetry == null
                  ? null
                  : () => unawaited(_task!.onRetry!()))
          : SizedBox(
              width: widget.compact ? 60 : 220,
              height: widget.compact ? 30 : 130));
}

/// Mounted once in MaterialApp.builder; only modal tasks absorb outside taps.
class VuTaskHost extends StatelessWidget {
  const VuTaskHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: VuTasks.instance,
      builder: (context, _) {
        final visible = VuTasks.instance.tasks
            .where((t) =>
                t.visible &&
                t.pauses == 0 &&
                (t.inlineViews == 0 || t.blocking))
            .toList();
        final blocking = VuTasks.instance.tasks.any((t) =>
            t.blocking &&
            !t.finished &&
            t.pauses == 0 &&
            t.status == VuStatus.processing);
        return Stack(children: [
          child,
          if (blocking)
            const Positioned.fill(
                child: ModalBarrier(
                    key: Key('vu-blocking-barrier'),
                    dismissible: false,
                    color: Color(0x550C2132))),
          if (visible.isNotEmpty)
            Positioned(
              top: blocking ? 16 : null,
              bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
              right: 16,
              left: blocking ? 16 : null,
              child: SafeArea(
                  child: Align(
                      alignment:
                          blocking ? Alignment.center : Alignment.bottomRight,
                      child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: 320,
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * .65),
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                for (final task in visible)
                                  Material(
                                      key: ObjectKey(task),
                                      color: const Color(0xFFFFFCF5),
                                      elevation: 8,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                VuMeter(
                                                    message: task.message,
                                                    progress: task.progress,
                                                    compact: !task.blocking,
                                                    status: task.status,
                                                    onRetry: task.onRetry ==
                                                            null
                                                        ? null
                                                        : () => unawaited(
                                                            task.onRetry!())),
                                                if (task.status ==
                                                    VuStatus.error)
                                                  TextButton(
                                                      onPressed: () => VuTasks
                                                          .instance
                                                          .dismiss(task),
                                                      child:
                                                          const Text('Fechar')),
                                              ]))),
                              ]))))),
            ),
        ]);
      });
}
