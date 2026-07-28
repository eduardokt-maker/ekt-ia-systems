import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'capital_flow_cache.dart';
import 'capital_flow_share.dart';

typedef CapitalFlowApiUriBuilder = Uri Function(String path);

const _dosNavy = Color(0xFF061A33);
const _dosPanel = Color(0xFF092847);
const _dosCyan = Color(0xFF39E7E0);
const _dosYellow = Color(0xFFFFE66B);
const _dosGreen = Color(0xFF76F7A6);
const _dosRed = Color(0xFFFF8791);
const _dosLine = Color(0xFF2E668A);
const _dosMuted = Color(0xFFA8C9D8);

enum CapitalPeriod { day, week, month, year, custom }

enum CapitalView { institutional, foreign }

class CapitalFlowConnectionException implements Exception {
  const CapitalFlowConnectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CapitalFlowEntryScreen extends StatefulWidget {
  const CapitalFlowEntryScreen({required this.apiUriBuilder, super.key});
  final CapitalFlowApiUriBuilder apiUriBuilder;

  @override
  State<CapitalFlowEntryScreen> createState() => _CapitalFlowEntryScreenState();
}

class _CapitalFlowEntryScreenState extends State<CapitalFlowEntryScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        widget.apiUriBuilder('/api/investments/login'),
        headers: const {'content-type': 'application/json; charset=utf-8'},
        body: jsonEncode(
            {'login': _login.text.trim(), 'password': _password.text}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (response.statusCode == 200 && body['ok'] == true) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => CapitalFlowScreen(
            apiUriBuilder: widget.apiUriBuilder,
            sessionToken: body['session_token'] as String? ?? '',
          ),
        ));
        return;
      }
      setState(() =>
          _error = body['message'] as String? ?? 'Não foi possível entrar.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível conectar ao sistema.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _dosNavy,
        appBar: AppBar(
          backgroundColor: _dosNavy,
          foregroundColor: Colors.white,
          title: const Text('FLUXO DE CAPITAL'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _dosPanel,
                border: Border.all(color: _dosCyan, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.table_chart_outlined,
                      color: _dosCyan, size: 42),
                  const SizedBox(height: 16),
                  const Text('ACESSO AO MONITOR B3',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _dosYellow,
                          fontFamily: 'monospace',
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Use as credenciais da área de investimentos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _dosMuted, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 22),
                  _loginField(_login, 'LOGIN', Icons.person_outline),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'SENHA',
                      labelStyle: const TextStyle(color: _dosMuted),
                      prefixIcon:
                          const Icon(Icons.lock_outline, color: _dosCyan),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _dosLine)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _dosCyan, width: 2)),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: _dosMuted),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _dosRed, fontFamily: 'monospace')),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: _dosCyan,
                        foregroundColor: _dosNavy,
                        minimumSize: const Size.fromHeight(48),
                        shape: const RoundedRectangleBorder()),
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: Text(_loading ? 'CONECTANDO...' : 'ENTRAR',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _loginField(
          TextEditingController controller, String label, IconData icon) =>
      TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _dosMuted),
          prefixIcon: Icon(icon, color: _dosCyan),
          enabledBorder:
              const OutlineInputBorder(borderSide: BorderSide(color: _dosLine)),
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _dosCyan, width: 2)),
        ),
      );
}

class CapitalFlowScreen extends StatefulWidget {
  const CapitalFlowScreen(
      {required this.apiUriBuilder, required this.sessionToken, super.key});
  final CapitalFlowApiUriBuilder apiUriBuilder;
  final String sessionToken;

  @override
  State<CapitalFlowScreen> createState() => _CapitalFlowScreenState();
}

class _CapitalFlowScreenState extends State<CapitalFlowScreen> {
  final FocusNode _gridFocus = FocusNode();
  final GlobalKey _sheetKey = GlobalKey();
  CapitalPeriod _period = CapitalPeriod.month;
  DateTime _reference = DateTime.now();
  DateTimeRange? _custom;
  List<ForeignFlowRow> _rows = [];
  bool _loading = false;
  String? _error;
  String? _notice;
  String? _lastUpdated;
  Map<String, dynamic>? _lastPayload;
  Map<String, dynamic> _syncStatus = const {};
  Timer? _pollTimer;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  CapitalView? _activeCapitalView;

  bool get _showInstitutional =>
      _activeCapitalView == CapitalView.institutional;

  String get _investorType =>
      _showInstitutional ? 'Institucional brasileiro' : 'Estrangeiro';

  Map<String, String> get _headers => {
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/json; charset=utf-8'
      };

  DateTimeRange get _range {
    final d = DateTime(_reference.year, _reference.month, _reference.day);
    return switch (_period) {
      CapitalPeriod.day => DateTimeRange(start: d, end: d),
      CapitalPeriod.week => DateTimeRange(
          start: d.subtract(Duration(days: d.weekday - 1)),
          end: d.add(Duration(days: 7 - d.weekday))),
      CapitalPeriod.month => DateTimeRange(
          start: DateTime(d.year, d.month),
          end: DateTime(d.year, d.month + 1, 0)),
      CapitalPeriod.year =>
        DateTimeRange(start: DateTime(d.year), end: DateTime(d.year, 12, 31)),
      CapitalPeriod.custom => _custom ?? DateTimeRange(start: d, end: d),
    };
  }

  double get _totalIn => _rows.fold(0, (sum, row) => sum + row.inflow);
  double get _totalOut => _rows.fold(0, (sum, row) => sum + row.outflow);
  double get _finalBalance => _rows.fold(0, (sum, row) => sum + row.balance);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _gridFocus.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false, bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uri = widget.apiUriBuilder('/api/capital-flow').replace(
        queryParameters: {
          'from': _iso(_range.start),
          'to': _iso(_range.end),
          if (force) 'refresh': 'true',
        },
      );
      final response = await _getCapitalFlow(uri);
      final body = _decodeResponse(response);
      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(body['message'] as String? ?? 'Consulta indisponível.');
      }
      saveCapitalFlowCache(body);
      final records = _capitalRows(body);
      if (!mounted) return;
      setState(() {
        _lastPayload = body;
        _rows = records;
        _notice = body['notice'] as String?;
        _lastUpdated = body['last_updated'] as String?;
        _syncStatus = (body['sync'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
        if (!silent) {
          _selectedRow = 0;
          _selectedColumn = 0;
        }
      });
      _scheduleSyncPoll();
    } catch (error) {
      if (error is CapitalFlowConnectionException) {
        final cached = loadCapitalFlowCache(
          _iso(_range.start),
          _iso(_range.end),
        );
        if (cached != null && mounted) {
          setState(() {
            _lastPayload = cached;
            _rows = _capitalRows(cached);
            _notice =
                'MODO LOCAL: dados da última consulta salva neste dispositivo. '
                'O banco do servidor continua sendo a fonte oficial.';
            _lastUpdated = cached['last_updated'] as String?;
            _syncStatus = const {'status': 'cached'};
            if (!silent) {
              _selectedRow = 0;
              _selectedColumn = 0;
            }
          });
          return;
        }
      }
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  List<ForeignFlowRow> _capitalRows(Map<String, dynamic> body) =>
      ((body['items'] as List<dynamic>?) ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((item) => item['investor_type'] == _investorType)
          .map(ForeignFlowRow.fromJson)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  Future<void> _openCapitalView(CapitalView view) async {
    setState(() {
      _activeCapitalView = view;
      _selectedRow = 0;
      _selectedColumn = 0;
    });
    if (_lastPayload != null) {
      setState(() => _rows = _capitalRows(_lastPayload!));
      return;
    }
    await _load();
  }

  void _returnToCapitalHome() {
    _pollTimer?.cancel();
    setState(() {
      _activeCapitalView = null;
      _loading = false;
      _error = null;
      _selectedRow = 0;
      _selectedColumn = 0;
    });
  }

  Future<http.Response> _getCapitalFlow(Uri uri) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 45));
        if (response.statusCode < 500) return response;
      } on TimeoutException {
        // The server may still be waking from the hosting provider's idle state.
      } on http.ClientException {
        // A temporary 503 without CORS is exposed by browsers as ClientException.
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }

    throw const CapitalFlowConnectionException(
      'O servidor de dados está iniciando ou temporariamente indisponível. '
      'Aguarde alguns segundos e tente novamente.',
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      if (response.statusCode >= 500) {
        throw const CapitalFlowConnectionException(
          'O servidor de dados está temporariamente indisponível. '
          'Tente novamente em instantes.',
        );
      }
      throw Exception('A consulta retornou uma resposta inválida.');
    }
  }

  void _scheduleSyncPoll() {
    _pollTimer?.cancel();
    if (_syncStatus['status'] != 'running') return;
    _pollTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _load(silent: true);
    });
  }

  double? get _syncProgress {
    if (_syncStatus['status'] != 'running') return null;
    final totalMonths = (_syncStatus['total_months'] as num?)?.toDouble() ?? 0;
    if (totalMonths <= 0) return null;
    final completed =
        (_syncStatus['completed_months'] as num?)?.toDouble() ?? 0;
    final totalBulletins =
        (_syncStatus['total_bulletins'] as num?)?.toDouble() ?? 0;
    final processed =
        (_syncStatus['processed_bulletins'] as num?)?.toDouble() ?? 0;
    final monthFraction =
        totalBulletins > 0 ? (processed / totalBulletins).clamp(0, 1) : 0;
    return ((completed + monthFraction) / totalMonths).clamp(0, 1);
  }

  String get _syncLabel {
    final month = '${_syncStatus['current_month'] ?? ''}';
    final bulletin = '${_syncStatus['current_bulletin'] ?? ''}';
    final completed = _syncStatus['completed_months'] ?? 0;
    final total = _syncStatus['total_months'] ?? 0;
    final processed = _syncStatus['processed_bulletins'] ?? 0;
    final bulletinTotal = _syncStatus['total_bulletins'] ?? 0;
    return 'CARGA HISTÓRICA: MÊS $month • $completed/$total MESES'
        '${bulletin.isEmpty ? '' : ' • BOLETIM $bulletin'}'
        '${bulletinTotal == 0 ? '' : ' • $processed/$bulletinTotal'}';
  }

  Future<void> _setPeriod(CapitalPeriod period) async {
    setState(() => _period = period);
    if (period == CapitalPeriod.custom && _custom == null) {
      await _selectDate();
    } else {
      await _load();
    }
  }

  Future<void> _selectDate() async {
    if (_period == CapitalPeriod.custom) {
      final value = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2010),
        lastDate: DateTime.now(),
        initialDateRange: _custom ??
            DateTimeRange(
              start: DateTime(DateTime.now().year),
              end: DateTime.now(),
            ),
        locale: const Locale('pt', 'BR'),
        initialEntryMode: DatePickerEntryMode.calendar,
        keyboardType: TextInputType.datetime,
        helpText: 'SELECIONE O INTERVALO',
        cancelText: 'CANCELAR',
        confirmText: 'APLICAR',
        saveText: 'APLICAR',
        fieldStartLabelText: 'DATA INICIAL',
        fieldEndLabelText: 'DATA FINAL',
        fieldStartHintText: 'dd/mm/aaaa',
        fieldEndHintText: 'dd/mm/aaaa',
        errorFormatText: 'Use o formato dd/mm/aaaa',
        errorInvalidRangeText: 'A data final deve ser posterior à inicial',
        switchToInputEntryModeIcon: const Icon(Icons.keyboard_alt_outlined),
        switchToCalendarEntryModeIcon:
            const Icon(Icons.calendar_month_outlined),
        builder: _calendarBuilder,
      );
      if (value != null) {
        _custom = value;
        await _load();
      }
      return;
    }
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      initialDate: _reference,
      locale: const Locale('pt', 'BR'),
      builder: _calendarBuilder,
    );
    if (value != null) {
      _reference = value;
      await _load();
    }
  }

  Widget _calendarBuilder(BuildContext context, Widget? child) {
    const calendarBlue = Color(0xFF145DA0);
    const calendarBlueDark = Color(0xFF0B3558);
    const calendarBlack = Color(0xFF111827);
    const calendarMuted = Color(0xFF4B5563);
    const calendarSelection = Color(0xFFD8EAFE);

    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        colorScheme: const ColorScheme.light(
          primary: calendarBlue,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: calendarBlack,
          outline: Color(0xFF94A3B8),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFB8CCE0)),
          ),
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          headerBackgroundColor: calendarBlue,
          headerForegroundColor: Colors.white,
          rangePickerBackgroundColor: Colors.white,
          rangePickerSurfaceTintColor: Colors.white,
          rangePickerHeaderBackgroundColor: calendarBlue,
          rangePickerHeaderForegroundColor: Colors.white,
          rangeSelectionBackgroundColor: calendarSelection,
          rangeSelectionOverlayColor:
              const WidgetStatePropertyAll(Color(0x33246FB3)),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? const Color(0xFF9CA3AF)
                : calendarBlack,
          ),
          dayOverlayColor: const WidgetStatePropertyAll(Color(0x1F145DA0)),
          todayForegroundColor: const WidgetStatePropertyAll(calendarBlueDark),
          todayBackgroundColor: const WidgetStatePropertyAll(Color(0xFFEAF4FF)),
          todayBorder: const BorderSide(color: calendarBlue, width: 2),
          yearForegroundColor: const WidgetStatePropertyAll(calendarBlack),
          yearOverlayColor: const WidgetStatePropertyAll(Color(0x1F145DA0)),
          weekdayStyle: const TextStyle(
            color: calendarBlueDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          dayStyle: const TextStyle(
            color: calendarBlack,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          yearStyle: const TextStyle(
            color: calendarBlack,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          headerHeadlineStyle: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ),
          headerHelpStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          rangePickerHeaderHeadlineStyle: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          rangePickerHeaderHelpStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Color(0xFFF8FAFC),
            labelStyle: TextStyle(
              color: calendarBlueDark,
              fontWeight: FontWeight.w700,
            ),
            hintStyle: TextStyle(color: calendarMuted),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF94A3B8)),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: calendarBlue, width: 2),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFB8CCE0)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: calendarBlueDark,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        iconTheme: const IconThemeData(color: calendarBlueDark),
        textTheme: baseTheme.textTheme.apply(
          bodyColor: calendarBlack,
          displayColor: calendarBlack,
        ),
      ),
      child: child!,
    );
  }

  Future<void> _move(int direction) async {
    final current = _reference;
    _reference = switch (_period) {
      CapitalPeriod.day => current.add(Duration(days: direction)),
      CapitalPeriod.week => current.add(Duration(days: direction * 7)),
      CapitalPeriod.month =>
        DateTime(current.year, current.month + direction, 1),
      CapitalPeriod.year => DateTime(current.year + direction, 1, 1),
      CapitalPeriod.custom => current,
    };
    if (_reference.isAfter(DateTime.now())) _reference = DateTime.now();
    await _load();
  }

  Future<void> _shareImage() async {
    try {
      final boundary = _sheetKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Planilha indisponível.');
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Não foi possível gerar a imagem.');
      final shared = await shareCapitalFlowImage(
        data.buffer.asUint8List(),
        'fluxo-capital-${_iso(_range.start)}-${_iso(_range.end)}.png',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(shared
            ? 'Imagem pronta. Selecione o WhatsApp para compartilhar.'
            : 'O compartilhamento de imagem não é compatível com este navegador.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível gerar a imagem da planilha.')));
    }
  }

  Future<void> _sharePdf() async {
    try {
      final document = pw.Document();
      document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
              _showInstitutional
                  ? 'FLUXO DE CAPITAL INSTITUCIONAL — BRASIL'
                  : 'FLUXO DE CAPITAL ESTRANGEIRO — B3',
              style: const pw.TextStyle(
                  fontSize: 17, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Período: ${_rangeLabel(_range)}'),
          pw.SizedBox(height: 12),
          _pdfFlowTable(),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Text(
              'FONTE OFICIAL: B3 — Boletim Diário do Mercado (BDI), tabela Participação dos Investidores.',
              style: const pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(
              'Dados obtidos da divulgação oficial da B3, sujeitos a atualização ou republicação e à defasagem D-2. Saldo = compras - vendas.',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 5),
          pw.Text('EKT Desenvolvimento',
              style: const pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ));
      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'fluxo-capital-${_iso(_range.start)}-${_iso(_range.end)}.pdf',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível gerar o PDF da planilha.')));
    }
  }

  pw.Widget _pdfFlowTable() {
    const headers = [
      'DATA',
      'DIA DA SEMANA',
      'ENTRADA / COMPRAS',
      'SAÍDA / VENDAS',
      'SALDO DO DIA',
    ];

    return pw.Table(
      border: pw.TableBorder.all(
        color: const PdfColor.fromInt(0xFFB9C5CD),
        width: 0.5,
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.55),
        3: pw.FlexColumnWidth(1.55),
        4: pw.FlexColumnWidth(1.55),
      },
      children: [
        pw.TableRow(
          decoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFF10476B)),
          children: headers
              .map((value) => _pdfCell(value, header: true, bold: true))
              .toList(),
        ),
        ..._rows.map(
          (row) => pw.TableRow(
            children: [
              _pdfCell(_date(row.date)),
              _pdfCell(_weekday(row.date)),
              _pdfCell(_money(row.inflow), numeric: true),
              _pdfCell(_money(row.outflow), numeric: true),
              _pdfCell(
                _signedMoney(row.balance),
                numeric: true,
                balance: row.balance,
              ),
            ],
          ),
        ),
        pw.TableRow(
          decoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EEF2)),
          children: [
            _pdfCell('TOTAL', bold: true),
            _pdfCell('${_rows.length} pregões', bold: true),
            _pdfCell(_money(_totalIn), numeric: true, bold: true),
            _pdfCell(_money(_totalOut), numeric: true, bold: true),
            _pdfCell(
              _signedMoney(_finalBalance),
              numeric: true,
              bold: true,
              balance: _finalBalance,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _pdfCell(
    String value, {
    bool header = false,
    bool numeric = false,
    bool bold = false,
    double? balance,
  }) {
    final text = pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 9,
        color: header ? PdfColors.white : PdfColors.black,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: numeric ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: balance == null || balance == 0
          ? text
          : pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 7,
                  height: 7,
                  decoration: pw.BoxDecoration(
                    color: balance > 0 ? PdfColors.green : PdfColors.red,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 5),
                text,
              ],
            ),
    );
  }

  KeyEventResult _navigate(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _rows.isEmpty) {
      return KeyEventResult.ignored;
    }
    var row = _selectedRow;
    var column = _selectedColumn;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      row = (row + 1).clamp(0, _rows.length);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      row = (row - 1).clamp(0, _rows.length);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      column = (column + 1).clamp(0, 4);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      column = (column - 1).clamp(0, 4);
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      column = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      column = 4;
    } else {
      return KeyEventResult.ignored;
    }
    setState(() {
      _selectedRow = row;
      _selectedColumn = column;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _dosNavy,
        appBar: AppBar(
          backgroundColor: _dosNavy,
          foregroundColor: Colors.white,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FLUXO DE CAPITAL',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              Text('MONITOR B3 • SOMENTE LEITURA',
                  style: TextStyle(
                      fontFamily: 'monospace', color: _dosCyan, fontSize: 10)),
            ],
          ),
          actions: [
            IconButton(
                tooltip: 'Consultar novamente a B3',
                onPressed: _loading || _activeCapitalView == null
                    ? null
                    : () => _load(force: true),
                icon: const Icon(Icons.sync)),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
              children: [
                _capitalViewButton(),
                if (_activeCapitalView != null) ...[
                  const SizedBox(height: 10),
                  _statusBar(),
                  const SizedBox(height: 8),
                  _marketScopeNotice(),
                  const SizedBox(height: 10),
                  _filters(),
                  const SizedBox(height: 10),
                  if (_loading)
                    const LinearProgressIndicator(
                        color: _dosCyan, backgroundColor: _dosPanel)
                  else if (_error != null)
                    _message(_error!, error: true)
                  else if (_rows.isEmpty)
                    _message(_syncStatus['status'] == 'running'
                        ? 'CARGA HISTÓRICA EM SEGUNDO PLANO. A PLANILHA SERÁ ATUALIZADA AUTOMATICAMENTE.'
                        : 'NENHUM DADO OFICIAL DISPONÍVEL PARA ESTE PERÍODO.')
                  else ...[
                    _shareActions(),
                    const SizedBox(height: 8),
                    RepaintBoundary(key: _sheetKey, child: _spreadsheet()),
                  ],
                ],
              ],
            ),
          ),
        ),
      );

  Widget _capitalViewButton() => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFC0C0C0),
          border: Border(
            top: const BorderSide(color: Colors.white, width: 2),
            left: const BorderSide(color: Colors.white, width: 2),
            right: BorderSide(color: Colors.grey.shade800, width: 2),
            bottom: BorderSide(color: Colors.grey.shade800, width: 2),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -31,
              left: 0,
              child: Container(
                color: const Color(0xFFC0C0C0),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: const Text(
                  'Menu de comandos',
                  style: TextStyle(
                    color: Colors.black,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                if (_activeCapitalView != null) _returnCommandButton(),
                _classicCommandButton(
                  label: 'CAPITAL INSTITUCIONAL — BRASIL',
                  semanticsLabel: 'Abrir capital institucional Brasil',
                  icon: Icons.account_balance_outlined,
                  view: CapitalView.institutional,
                ),
                _classicCommandButton(
                  label: 'FLUXO DE CAPITAL ESTRANGEIRO',
                  semanticsLabel: 'Abrir fluxo de capital estrangeiro',
                  icon: Icons.public_outlined,
                  view: CapitalView.foreign,
                ),
              ],
            ),
          ],
        ),
      );

  Widget _returnCommandButton() => Semantics(
        button: true,
        label: 'Retornar à tela inicial do fluxo de capital',
        child: ElevatedButton.icon(
          onPressed: _returnToCapitalHome,
          icon: const Icon(Icons.home_outlined, size: 21),
          label: const Text('RETORNAR À TELA INICIAL'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _dosYellow,
            foregroundColor: const Color(0xFF7A1F1F),
            elevation: 5,
            shadowColor: const Color(0x88000000),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: Color(0xFFB45309), width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );

  Widget _classicCommandButton({
    required String label,
    required String semanticsLabel,
    required IconData icon,
    required CapitalView view,
  }) {
    final selected = _activeCapitalView == view;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: ElevatedButton.icon(
        onPressed: () => _openCapitalView(view),
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? const Color(0xFF0B5FA5) : Colors.white,
          foregroundColor: selected ? Colors.white : const Color(0xFF0B4F86),
          elevation: selected ? 1 : 4,
          shadowColor: const Color(0x66000000),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(
            color: selected ? const Color(0xFF073B63) : const Color(0xFF6D9FC5),
            width: selected ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _marketScopeNotice() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF103653),
          border: Border.all(color: _dosCyan),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: _dosYellow, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INFORMATIVO • ESCOPO DOS DADOS',
                    style: TextStyle(
                      color: _dosYellow,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _showInstitutional
                        ? 'Compras e vendas de investidores institucionais brasileiros nos mercados B3. O saldo representa compras menos vendas no mercado negociado e não equivale ao fluxo cambial do país.'
                        : 'Compras e vendas de investidores estrangeiros nos mercados B3: à vista/fracionário, ETFs, termo, opções, exercícios e blocos. O saldo é líquido de negociação (compras − vendas); não representa fluxo cambial nem aplicações em Tesouro, CDB, LCI/LCA ou fundos fora da bolsa.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _shareActions() => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: _shareImage,
            icon: const Icon(Icons.image_outlined),
            label: const Text('COMPARTILHAR IMAGEM'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _dosCyan,
              side: const BorderSide(color: _dosLine),
              shape: const RoundedRectangleBorder(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('COMPARTILHAR PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _dosYellow,
              side: const BorderSide(color: _dosLine),
              shape: const RoundedRectangleBorder(),
            ),
          ),
        ],
      );

  Widget _statusBar() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _dosPanel, border: Border.all(color: _dosLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.circle, size: 10, color: _dosGreen),
            const SizedBox(width: 7),
            const Expanded(
              child: Text('FONTE: B3 — BOLETIM DIÁRIO DO MERCADO',
                  style: TextStyle(
                      color: _dosCyan,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold)),
            ),
            Text('${_rows.length} PREGÕES',
                style: const TextStyle(
                    color: _dosYellow, fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 6),
          Text(
            'ATUALIZAÇÃO: ${_lastUpdated == null ? 'AGUARDANDO DADOS' : _dateTime(_lastUpdated!)} • DEFASAGEM: D-2',
            style: const TextStyle(
                color: _dosMuted, fontFamily: 'monospace', fontSize: 11),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 5),
            Text(_notice!,
                style: const TextStyle(
                    color: _dosMuted, fontFamily: 'monospace', fontSize: 10)),
          ],
          if (_syncStatus['status'] == 'running') ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _syncProgress,
              minHeight: 7,
              color: _dosYellow,
              backgroundColor: _dosNavy,
            ),
            const SizedBox(height: 6),
            Text(
              _syncLabel,
              style: const TextStyle(
                  color: _dosYellow,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            const Text(
              'VOCÊ PODE CONTINUAR NAVEGANDO. OS DADOS JÁ GRAVADOS PERMANECEM DISPONÍVEIS.',
              style: TextStyle(
                  color: _dosMuted, fontFamily: 'monospace', fontSize: 9),
            ),
          ] else if (_syncStatus['status'] == 'failed') ...[
            const SizedBox(height: 7),
            Text(
              'CARGA INTERROMPIDA: ${_syncStatus['error'] ?? 'falha temporária'}. USE ATUALIZAR PARA RETOMAR.',
              style: const TextStyle(
                  color: _dosRed, fontFamily: 'monospace', fontSize: 10),
            ),
          ],
        ]),
      );

  Widget _filters() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: _dosPanel, border: Border.all(color: _dosLine)),
        child: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: CapitalPeriod.values
                  .map((period) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(_periodName(period)),
                          selected: _period == period,
                          selectedColor: _dosCyan,
                          backgroundColor: _dosNavy,
                          side: const BorderSide(color: _dosLine),
                          labelStyle: TextStyle(
                              fontFamily: 'monospace',
                              color:
                                  _period == period ? _dosNavy : Colors.white),
                          shape: const RoundedRectangleBorder(),
                          onSelected: (_) => _setPeriod(period),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 9),
          Row(children: [
            IconButton(
                tooltip: 'Período anterior',
                onPressed:
                    _period == CapitalPeriod.custom ? null : () => _move(-1),
                color: _dosCyan,
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectDate,
                style: OutlinedButton.styleFrom(
                    foregroundColor: _dosYellow,
                    side: const BorderSide(color: _dosCyan),
                    shape: const RoundedRectangleBorder()),
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                    _period == CapitalPeriod.day
                        ? '${_date(_reference)} — ${_weekday(_reference)}'
                        : _rangeLabel(_range),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
            ),
            IconButton(
                tooltip: 'Próximo período',
                onPressed: _period == CapitalPeriod.custom ||
                        !_range.end.isBefore(DateTime.now())
                    ? null
                    : () => _move(1),
                color: _dosCyan,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ]),
      );

  Widget _spreadsheet() => Focus(
        focusNode: _gridFocus,
        autofocus: true,
        onKeyEvent: _navigate,
        child: Container(
          decoration: BoxDecoration(
              color: _dosPanel, border: Border.all(color: _dosCyan, width: 2)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: _dosCyan,
              child: Row(children: [
                Expanded(
                  child: Text(
                      _showInstitutional
                          ? 'CONSULTA DIÁRIA — CAPITAL INSTITUCIONAL BRASIL'
                          : 'CONSULTA DIÁRIA — CAPITAL ESTRANGEIRO',
                      style: const TextStyle(
                          color: _dosNavy,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold)),
                ),
                Text('${_date(_rows.first.date)} A ${_date(_rows.last.date)}',
                    style: const TextStyle(
                        color: _dosNavy,
                        fontFamily: 'monospace',
                        fontSize: 11)),
              ]),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 920,
                child: Column(children: [
                  _gridRow(
                    rowIndex: -1,
                    values: const [
                      'DATA',
                      'DIA DA SEMANA',
                      'ENTRADA / COMPRAS',
                      'SAÍDA / VENDAS',
                      'SALDO DO DIA'
                    ],
                    header: true,
                  ),
                  ..._rows.indexed.map((indexed) {
                    final index = indexed.$1;
                    final row = indexed.$2;
                    return _gridRow(rowIndex: index, values: [
                      _date(row.date),
                      _weekday(row.date).toUpperCase(),
                      _money(row.inflow),
                      _money(row.outflow),
                      _signedMoney(row.balance),
                    ]);
                  }),
                  _gridRow(
                    rowIndex: _rows.length,
                    values: [
                      'TOTAL',
                      '${_rows.length} PREGÕES',
                      _money(_totalIn),
                      _money(_totalOut),
                      _signedMoney(_finalBalance),
                    ],
                    total: true,
                  ),
                ]),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _dosLine))),
              child: const Text(
                'NAVEGAÇÃO: SETAS ← ↑ ↓ →  |  CLIQUE OU TOQUE EM UMA CÉLULA  |  DADOS SEM EDIÇÃO',
                style: TextStyle(
                    color: _dosMuted, fontFamily: 'monospace', fontSize: 10),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              color: _dosNavy,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FONTE OFICIAL: B3 — BOLETIM DIÁRIO DO MERCADO (BDI), TABELA PARTICIPAÇÃO DOS INVESTIDORES.',
                    style: TextStyle(
                        color: _dosCyan,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'DADOS OBTIDOS DA DIVULGAÇÃO OFICIAL DA B3, SUJEITOS A ATUALIZAÇÃO OU REPUBLICAÇÃO E À DEFASAGEM D-2. SALDO = COMPRAS - VENDAS.',
                    style: TextStyle(
                        color: _dosMuted, fontFamily: 'monospace', fontSize: 9),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'EKT DESENVOLVIMENTO',
                    style: TextStyle(
                        color: _dosYellow,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _gridRow({
    required int rowIndex,
    required List<String> values,
    bool header = false,
    bool total = false,
  }) {
    const widths = [130.0, 180.0, 200.0, 200.0, 210.0];
    return Row(
      children: List.generate(values.length, (columnIndex) {
        final selected =
            rowIndex == _selectedRow && columnIndex == _selectedColumn;
        final balanceColumn = columnIndex == 4 && !header;
        final negative = balanceColumn && values[columnIndex].startsWith('-');
        final inflowColumn = columnIndex == 2 && !header;
        final outflowColumn = columnIndex == 3 && !header;
        final totalBalanceColumn = balanceColumn && total;
        final cellColor = selected
            ? const Color(0xFF5E2A84)
            : header
                ? const Color(0xFF10476B)
                : totalBalanceColumn
                    ? const Color(0xFF23658F)
                    : balanceColumn
                        ? Colors.black
                        : inflowColumn
                            ? const Color(0xFF087A46)
                            : outflowColumn
                                ? const Color(0xFF9E1B32)
                                : total
                                    ? const Color(0xFF123B36)
                                    : rowIndex.isEven
                                        ? _dosNavy
                                        : _dosPanel;
        final textColor = selected
            ? Colors.white
            : header
                ? _dosCyan
                : balanceColumn
                    ? negative
                        ? _dosRed
                        : _dosGreen
                    : inflowColumn && total
                        ? _dosYellow
                        : inflowColumn || outflowColumn
                            ? Colors.white
                            : total
                                ? _dosYellow
                                : Colors.white;
        void selectCell() {
          _gridFocus.requestFocus();
          setState(() {
            _selectedRow = rowIndex;
            _selectedColumn = columnIndex;
          });
        }

        return MouseRegion(
          cursor: header ? MouseCursor.defer : SystemMouseCursors.basic,
          onEnter: header ? null : (_) => selectCell(),
          child: GestureDetector(
            onTap: header ? null : selectCell,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: widths[columnIndex],
              height: header
                  ? 42
                  : total
                      ? 46
                      : 38,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: columnIndex >= 2
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: cellColor,
                border: Border(
                  left: selected
                      ? const BorderSide(color: Colors.white, width: 2)
                      : BorderSide.none,
                  top: selected
                      ? const BorderSide(color: Colors.white, width: 2)
                      : BorderSide.none,
                  right: BorderSide(
                      color: selected ? Colors.white : _dosLine,
                      width: selected ? 2 : 1),
                  bottom: BorderSide(
                      color: selected ? Colors.white : _dosLine,
                      width: selected ? 2 : 1),
                ),
              ),
              child: Text(
                values[columnIndex],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: header || total || selected || balanceColumn
                      ? FontWeight.bold
                      : null,
                  decoration: balanceColumn
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: textColor,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _message(String text, {bool error = false}) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: _dosPanel,
            border: Border.all(color: error ? _dosRed : _dosLine)),
        child: Column(children: [
          Icon(error ? Icons.error_outline : Icons.inbox_outlined,
              color: error ? _dosRed : _dosCyan, size: 34),
          const SizedBox(height: 9),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: error ? _dosRed : _dosMuted, fontFamily: 'monospace')),
          if (error) ...[
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                    foregroundColor: _dosCyan,
                    side: const BorderSide(color: _dosCyan),
                    shape: const RoundedRectangleBorder()),
                child: const Text('TENTAR NOVAMENTE'))
          ],
        ]),
      );
}

class ForeignFlowRow {
  const ForeignFlowRow(
      {required this.date,
      required this.inflow,
      required this.outflow,
      required this.balance});
  final DateTime date;
  final double inflow;
  final double outflow;
  final double balance;

  factory ForeignFlowRow.fromJson(Map<String, dynamic> json) => ForeignFlowRow(
        date: DateTime.parse(json['reference_date'] as String),
        inflow: (json['inflow'] as num).toDouble(),
        outflow: (json['outflow'] as num).toDouble(),
        balance: (json['net'] as num).toDouble(),
      );
}

String _iso(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _weekday(DateTime value) => const [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo'
    ][value.weekday - 1];
String _dateTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return '${_date(parsed)} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}

String _rangeLabel(DateTimeRange range) =>
    '${_date(range.start)} ATÉ ${_date(range.end)}';
String _periodName(CapitalPeriod value) => switch (value) {
      CapitalPeriod.day => 'DIA',
      CapitalPeriod.week => 'SEMANA',
      CapitalPeriod.month => 'MÊS',
      CapitalPeriod.year => 'ANO',
      CapitalPeriod.custom => 'INTERVALO',
    };
String _money(double value) => 'R\$ ${_number(value)}';
String _signedMoney(double value) =>
    '${value > 0 ? '+' : value < 0 ? '-' : ''}R\$ ${_number(value.abs())}';
String _number(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final reversed = parts[0].split('').reversed.toList();
  final groups = <String>[];
  for (var index = 0; index < reversed.length; index += 3) {
    groups.add(reversed.skip(index).take(3).toList().reversed.join());
  }
  return '${groups.reversed.join('.')},${parts[1]}';
}
