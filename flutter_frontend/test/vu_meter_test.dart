import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekt_ia_flutter_frontend/vu_meter.dart';

void main() {
  testWidgets('usa círculo, barra e ícones conforme o estado', (tester) async {
    Future<void> show(VuStatus status, {double? progress}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: VuMeter(status: status, progress: progress)),
        ));

    await show(VuStatus.processing);
    expect(find.byKey(const Key('progress-indeterminate')), findsOneWidget);

    await show(VuStatus.processing, progress: .6);
    expect(find.byKey(const Key('progress-determinate')), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('progress-determinate')));
    expect(bar.value, .6);
    expect(find.text('60%'), findsOneWidget);

    await show(VuStatus.success, progress: 1);
    expect(find.byKey(const Key('progress-success')), findsOneWidget);
    await show(VuStatus.error);
    expect(find.byKey(const Key('progress-error')), findsOneWidget);
  });

  Future<void> host(WidgetTester tester,
      {Widget? child, bool reduced = false}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, content) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: VuTaskHost(child: content!)),
        home: Scaffold(body: child ?? const Text('Conteúdo preservado'))));
  }

  testWidgets(
      'não pisca antes de 300 ms nem anuncia sucesso falso em tarefa rápida',
      (tester) async {
    await host(tester);
    final done = Completer<void>();
    final future = VuTasks.run(
        owner: Object(),
        key: 'fast',
        message: 'Salvando…',
        action: () => done.future);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(VuMeter), findsNothing);
    done.complete();
    await tester.pump();
    await future;
    expect(find.byType(VuMeter), findsNothing);
    expect(VuTasks.instance.tasks, isEmpty);
  });
  testWidgets('mantém visível e conclui sem ficar preso', (tester) async {
    await host(tester);
    final done = Completer<void>();
    final future = VuTasks.run(
        owner: Object(),
        key: 'slow',
        message: 'Carregando dados…',
        action: () => done.future);
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(find.byType(VuMeter), findsOneWidget);
    done.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 601));
    await tester.pump();
    expect(find.text('Concluído'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    await future;
    expect(find.byType(VuMeter), findsNothing);
    expect(VuTasks.instance.tasks, isEmpty);
  });
  testWidgets('progresso real é monotônico', (tester) async {
    final task = VuTask(message: 'Importando…');
    task.reportProgress(.6);
    task.reportProgress(.2);
    expect(task.progress, .6);
    task.reportProgress(2);
    expect(task.progress, 1);
    task.reportProgress(double.nan);
    expect(task.progress, 1);
    task.dispose();
  });
  testWidgets('erro interrompe, preserva formulário e permite nova tentativa',
      (tester) async {
    final input = TextEditingController(text: 'Dados preenchidos');
    await host(tester, child: TextField(controller: input));
    var attempts = 0;
    await VuTasks.run(
        owner: Object(),
        key: 'error',
        message: 'Salvando…',
        action: () async {
          attempts++;
          if (attempts == 1)
            VuTasks.fail('Servidor indisponível. Tente novamente.');
        });
    await tester.pump();
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(input.text, 'Dados preenchidos');
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(VuTasks.instance.tasks, isEmpty);
    await tester.pumpWidget(const SizedBox());
    input.dispose();
  });
  testWidgets('envios duplicados não executam ação duas vezes', (tester) async {
    await host(tester);
    var calls = 0;
    final owner = Object();
    final done = Completer<void>();
    Future<void> action() {
      calls++;
      return done.future;
    }

    final a = VuTasks.run(
        owner: owner, key: 'save', message: 'Salvando…', action: action);
    final b = VuTasks.run(
        owner: owner, key: 'save', message: 'Salvando…', action: action);
    expect(calls, 1);
    done.complete();
    await tester.pump();
    await Future.wait([a, b]);
  });
  testWidgets('diálogo de usuário pausa a espera e retoma após confirmação',
      (tester) async {
    await host(tester);
    final input = Completer<void>();
    final work = Completer<void>();
    final future = VuTasks.run(
        owner: Object(),
        key: 'dialog',
        message: 'Excluindo…',
        blocking: true,
        action: () async {
          await VuTasks.awaitUser(() => input.future);
          await work.future;
        });
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(VuMeter), findsNothing);
    expect(find.byKey(const Key('vu-blocking-barrier')), findsNothing);
    input.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(find.byType(VuMeter), findsOneWidget);
    work.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 601));
    await tester.pump(const Duration(milliseconds: 501));
    await future;
    await tester.pump();
    expect(VuTasks.instance.tasks, isEmpty);
  });
  testWidgets(
      'seção não bloqueia outros controles; modo bloqueante impede toques',
      (tester) async {
    var clicks = 0;
    await host(tester,
        child: TextButton(
            onPressed: () => clicks++, child: const Text('Outro módulo')));
    final done = Completer<void>();
    final f = VuTasks.run(
        owner: Object(),
        key: 'section',
        message: 'Atualizando…',
        action: () => done.future);
    await tester.pump();
    await tester.tap(find.text('Outro módulo'));
    expect(clicks, 1);
    done.complete();
    await tester.pump();
    await f;
    final blocked = Completer<void>();
    final b = VuTasks.run(
        owner: Object(),
        key: 'block',
        message: 'Aguarde…',
        blocking: true,
        action: () => blocked.future);
    await tester.pump();
    expect(find.byKey(const Key('vu-blocking-barrier')), findsOneWidget);
    blocked.complete();
    await tester.pump();
    await b;
  });
  testWidgets('respeita redução de movimento e tamanhos compacto e normal',
      (tester) async {
    await host(tester,
        reduced: true,
        child: const Column(children: [
          SizedBox(width: 58, height: 30, child: VuMeter(compact: true)),
          VuMeter(message: 'Processando…'),
        ]));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(VuMeter), findsNWidgets(2));
  });
  testWidgets('não anuncia percentual no modo indeterminado', (tester) async {
    await host(tester,
        reduced: true, child: const VuMeter(message: 'Consultando a nuvem…'));
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Consultando a nuvem…'), findsOneWidget);
  });
  testWidgets('nova tentativa de atualização não duplica gravação confirmada',
      (tester) async {
    await host(tester);
    var writes = 0, reads = 0;
    final owner = Object();
    await VuTasks.run(
        owner: owner,
        key: 'save',
        message: 'Salvando…',
        action: () async {
          writes++;
          VuTasks.mutationAccepted();
          await VuTasks.run(
              owner: owner,
              key: 'load',
              message: 'Atualizando…',
              action: () async {
                reads++;
                if (reads == 1)
                  VuTasks.fail('Não foi possível atualizar a lista.');
              });
        });
    await tester.pump();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(reads, 2);
    expect(VuTasks.instance.tasks, isEmpty);
  });
  testWidgets('texto de diálogo é recuperado após erro', (tester) async {
    await host(tester);
    var attempts = 0;
    String? recovered;
    await VuTasks.run(
        owner: Object(),
        key: 'draft',
        message: 'Salvando…',
        action: () async {
          final c = VuTasks.draftController(
              'description', () => TextEditingController(text: 'Original'));
          attempts++;
          if (attempts == 1) {
            c.text = 'Edição preservada';
            VuTasks.fail('Falha ao salvar.');
          } else {
            recovered = c.text;
          }
          VuTasks.disposeController(c);
        });
    await tester.pump();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(recovered, 'Edição preservada');
    expect(VuTasks.instance.tasks, isEmpty);
  });
}
