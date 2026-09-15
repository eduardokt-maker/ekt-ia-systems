import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum VuStatus { processing, success, error }

/// The single visual implementation used by all EKT wait states.
class VuMeter extends StatelessWidget {
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
  Widget build(BuildContext context) {
    const primary = Color(0xFF173449);
    const success = Color(0xFF247A4D);
    const error = Color(0xFF9C2828);
    final label = status == VuStatus.success ? 'Concluído' : message;
    final value = progress?.clamp(0.0, 1.0);
    final content = Semantics(
      liveRegion: true,
      label:
          '${status == VuStatus.error ? 'Erro' : status == VuStatus.success ? 'Concluído' : 'O sistema está processando'}. $label',
      value: value == null ? null : '${(value * 100).round()}%',
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? math.min(constraints.maxWidth, compact ? 156.0 : 280.0)
            : (compact ? 156.0 : 280.0);
        final tiny = width < 80 ||
            (constraints.hasBoundedHeight && constraints.maxHeight < 64);
        final indicatorSize = compact ? 24.0 : 42.0;
        Widget indicator;
        if (status == VuStatus.success) {
          indicator = Icon(Icons.check_circle_rounded,
              key: const Key('progress-success'),
              size: indicatorSize,
              color: success);
        } else if (status == VuStatus.error) {
          indicator = Icon(Icons.error_rounded,
              key: const Key('progress-error'),
              size: indicatorSize,
              color: error);
        } else if (value == null) {
          indicator = SizedBox.square(
              dimension: indicatorSize,
              child: const CircularProgressIndicator(
                  key: Key('progress-indeterminate'),
                  strokeWidth: 3,
                  color: primary));
        } else {
          indicator = SizedBox(
              width: width,
              child: LinearProgressIndicator(
                  key: const Key('progress-determinate'),
                  value: value,
                  minHeight: compact ? 5 : 7,
                  borderRadius: BorderRadius.circular(99),
                  color: primary,
                  backgroundColor: const Color(0xFFD7E0E6)));
        }
        return SizedBox(
            width: width,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              indicator,
              if (!tiny) ...[
                const SizedBox(height: 10),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.w600,
                        color: status == VuStatus.error ? error : primary)),
                if (value != null && status == VuStatus.processing)
                  Text('${(value * 100).round()}%',
                      style: const TextStyle(color: primary)),
                if (status == VuStatus.error && onRetry != null)
                  TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente')),
              ],
            ]));
      }),
    );
    return fullScreen ? Center(child: content) : content;
  }
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
