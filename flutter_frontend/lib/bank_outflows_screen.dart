import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_client.dart';
import 'bank_expense_natures_dialog.dart';
import 'statement_lab_file.dart';
import 'shared_statement_service.dart';

String receiptRepositoryTitle(
  Map<String, dynamic> file,
  Iterable<Map<String, dynamic>> outflows,
) {
  final fileId = '${file['id'] ?? ''}';
  final recipients = <String>{};
  for (final outflow in outflows) {
    if ('${outflow['source_file_id'] ?? ''}' != fileId) continue;
    final recipient = '${outflow['destination'] ?? ''}'.trim();
    if (recipient.isNotEmpty && recipient.toLowerCase() != 'não identificado') {
      recipients.add(recipient);
    }
  }
  if (recipients.length == 1) return recipients.first;
  if (recipients.length > 1) return '${recipients.length} destinatários';
  return '${file['filename'] ?? 'Comprovante'}';
}

class BankOutflowsScreen extends StatefulWidget {
  const BankOutflowsScreen({super.key, required this.apiUriBuilder});
  final Uri Function(String path) apiUriBuilder;

  @override
  State<BankOutflowsScreen> createState() => _BankOutflowsScreenState();
}

class _FileInspectionDialog extends StatelessWidget {
  const _FileInspectionDialog({
    required this.item,
    required this.bytes,
    required this.inspection,
    required this.money,
  });

  final Map<String, dynamic> item;
  final Uint8List bytes;
  final Map<String, dynamic> inspection;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final analysis = Map<String, dynamic>.from(
        inspection['analysis'] as Map? ?? const <String, dynamic>{});
    final file = Map<String, dynamic>.from(
        inspection['file'] as Map? ?? const <String, dynamic>{});
    final count = analysis['count'] ?? 0;
    final total = analysis['total'] ?? 0;
    final firstDate = '${analysis['first_transaction_date'] ?? ''}';
    final lastDate = '${analysis['last_transaction_date'] ?? ''}';
    final period = firstDate.isEmpty
        ? 'Nenhuma despesa reconhecida'
        : firstDate == lastDate
            ? firstDate
            : '$firstDate a $lastDate';
    final extractedText = '${file['extracted_text'] ?? ''}'.trim();
    final mimeType = '${item['mime_type']}';
    final screen = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: SizedBox(
        width: screen.width.clamp(320, 1050).toDouble(),
        height: screen.height.clamp(440, 780).toDouble(),
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
            child: Row(children: <Widget>[
              const Icon(Icons.find_in_page_outlined, color: Color(0xFF1F6DA8)),
              const SizedBox(width: 9),
              Expanded(
                  child: Text('${item['repository_title'] ?? item['filename']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900))),
              IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            color: const Color(0xFFF2F7FB),
            child: Wrap(spacing: 20, runSpacing: 5, children: <Widget>[
              Text('Leitura persistida: $count despesa(s)',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('Total reconhecido: ${money.format(total)}'),
              Text('Período: $period'),
            ]),
          ),
          if (extractedText.isNotEmpty)
            ExpansionTile(
              dense: true,
              title: const Text('Texto reconhecido pelo sistema',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 110),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: SelectableText(extractedText,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Expanded(child: _preview(mimeType)),
        ]),
      ),
    );
  }

  Widget _preview(String mimeType) {
    if (mimeType == 'application/pdf' ||
        '${item['filename']}'.toLowerCase().endsWith('.pdf')) {
      return PdfPreview(
        build: (_) async => bytes,
        pdfFileName: '${item['filename']}',
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      );
    }
    if (mimeType.startsWith('image/')) {
      return Container(
        color: const Color(0xFFF4F4F4),
        alignment: Alignment.center,
        child: InteractiveViewer(
          minScale: .7,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    }
    return const Center(
      child: Text('A visualização deste formato não está disponível.'),
    );
  }
}

class _BankOutflowsScreenState extends State<BankOutflowsScreen> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _search = TextEditingController();
  final _bank = TextEditingController();
  final _account = TextEditingController();
  final _filesScrollController = ScrollController();
  bool _loading = true;
  bool _uploading = false;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _files = const [];
  List<Map<String, dynamic>> _banks = const [];
  List<Map<String, dynamic>> _natures = const [];
  Map<String, dynamic>? _selectedBank;
  Map<String, dynamic> _summary = const {};
  int _selectedIndex = 0;
  SharedStatementFile? _sharedFile;
  bool _autoUploadScheduled = false;

  @override
  void initState() {
    super.initState();
    _sharedFile = sharedStatementService.pending;
    sharedStatementService.addListener(_sharedFileChanged);
    _load();
  }

  void _sharedFileChanged() {
    if (!mounted) return;
    setState(() => _sharedFile = sharedStatementService.pending);
    if (_sharedFile != null) _scheduleSharedUpload();
  }

  @override
  void dispose() {
    _search.dispose();
    _bank.dispose();
    _account.dispose();
    _filesScrollController.dispose();
    sharedStatementService.removeListener(_sharedFileChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = widget.apiUriBuilder('/api/banking-lab/outflows').replace(
          queryParameters: _search.text.trim().isEmpty
              ? null
              : <String, String>{'q': _search.text.trim()});
      final responses = await Future.wait(<Future<dynamic>>[
        apiClient.get(uri, timeout: const Duration(seconds: 90)),
        apiClient.get(widget.apiUriBuilder('/api/banking-lab')),
        apiClient.get(widget.apiUriBuilder('/api/banking-lab/banks')),
        apiClient.get(widget.apiUriBuilder('/api/banking-lab/natures')),
      ]);
      final response = responses[0];
      if (response.body.trim().isEmpty) {
        throw const ApiFailure('O servidor não concluiu a consulta.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final filesBody = jsonDecode(responses[1].body) as Map<String, dynamic>;
      final banksBody = jsonDecode(responses[2].body) as Map<String, dynamic>;
      final naturesBody = jsonDecode(responses[3].body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        throw ApiFailure(body['message'] as String? ??
            'Não foi possível carregar os lançamentos.');
      }
      if (!mounted) return;
      setState(() {
        final selectedId = _items.isNotEmpty && _selectedIndex < _items.length
            ? _items[_selectedIndex]['id']
            : null;
        _items = (body['outflows'] as List<dynamic>)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _files =
            (filesBody['files'] as List<dynamic>? ?? const []).map((value) {
          final file = Map<String, dynamic>.from(value as Map);
          file['repository_title'] = receiptRepositoryTitle(file, _items);
          return file;
        }).toList()
              ..sort((a, b) => _fileDate(b).compareTo(_fileDate(a)));
        _banks = (banksBody['banks'] as List<dynamic>? ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _natures = (naturesBody['natures'] as List<dynamic>? ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
        final found = _items.indexWhere((value) => value['id'] == selectedId);
        _selectedIndex = found >= 0
            ? found
            : (_items.isEmpty ? 0 : _selectedIndex.clamp(0, _items.length - 1));
        if (_selectedBank == null && _files.isNotEmpty) {
          final file = _files.first;
          _selectedBank = _banks.cast<Map<String, dynamic>?>().firstWhere(
              (value) => value?['ispb'] == file['bank_ispb'],
              orElse: () => null);
          _bank.text = _selectedBank == null
              ? '${file['bank_name']}'
              : _bankLabel(_selectedBank!);
          _account.text = '${file['account_label']}';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scheduleSharedUpload();
      }
    }
  }

  void _scheduleSharedUpload() {
    if (_autoUploadScheduled ||
        _uploading ||
        _sharedFile == null ||
        _selectedBank == null ||
        _account.text.trim().isEmpty) {
      return;
    }
    _autoUploadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _upload(automatic: true);
      } finally {
        _autoUploadScheduled = false;
      }
    });
  }

  Future<void> _upload({bool automatic = false}) async {
    if (_selectedBank == null || _account.text.trim().isEmpty) {
      _message('Selecione o banco e informe a conta.', error: true);
      return;
    }
    final sharedFile = _sharedFile;
    final file = sharedFile == null
        ? await pickStatementFile()
        : StatementPickedFile(sharedFile.name, sharedFile.bytes);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final response = await apiClient.post(
        widget.apiUriBuilder('/api/banking-lab/upload'),
        body: <String, dynamic>{
          'bank_ispb': _selectedBank!['ispb'],
          'account_label': _account.text.trim(),
          'filename': file.name,
          'content_base64': base64Encode(file.bytes),
          if (sharedFile != null && sharedFile.extractedText.trim().isNotEmpty)
            'extracted_text': sharedFile.extractedText.trim(),
        },
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 201 || body['ok'] != true) {
        final message =
            body['message'] as String? ?? 'Não foi possível enviar o arquivo.';
        if (sharedFile != null &&
            response.statusCode == 400 &&
            message.toLowerCase().contains('já foi enviado')) {
          sharedStatementService.clear();
          await _load();
          _message('Este comprovante já estava armazenado. Lista atualizada.');
          return;
        }
        throw ApiFailure(message);
      }
      if (sharedFile != null) sharedStatementService.clear();
      await _load();
      final duplicate = body['duplicate'] == true;
      _message(duplicate
          ? 'Comprovante já armazenado. A leitura foi atualizada e processada.'
          : automatic
              ? 'Comprovante lido e despesa atualizada automaticamente.'
              : 'Arquivo armazenado. As despesas foram atualizadas.');
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> item) async {
    try {
      final response = await apiClient.get(widget
          .apiUriBuilder('/api/banking-lab/files/${item['id']}/download'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível baixar o arquivo.');
      }
      downloadStatementFile(
          response.bodyBytes, '${item['filename']}', '${item['mime_type']}');
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<bool> _deleteFile(Map<String, dynamic> item) async {
    final title = '${item['repository_title'] ?? item['filename']}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFB42332), size: 34),
        title: const Text('Excluir comprovante?'),
        content: Text(
          'O arquivo “$title” será removido permanentemente do repositório. '
          'Os lançamentos já cadastrados não serão excluídos.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42332),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir arquivo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      final response = await apiClient.delete(
        widget.apiUriBuilder('/api/banking-lab/files/${item['id']}'),
      );
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir o comprovante.');
      }
      await _load();
      _message('Comprovante excluído do repositório.');
      return true;
    } catch (error) {
      _message('$error', error: true);
      return false;
    }
  }

  DateTime _fileDate(Map<String, dynamic> item) =>
      DateTime.tryParse('${item['uploaded_at']}') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  String _fileDateLabel(Map<String, dynamic> item) {
    final date = DateTime.tryParse('${item['uploaded_at']}')?.toLocal();
    return date == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  Future<void> _viewFile(Map<String, dynamic> item) async {
    try {
      final responses = await Future.wait([
        apiClient.get(widget
            .apiUriBuilder('/api/banking-lab/files/${item['id']}/download')),
        apiClient.get(widget
            .apiUriBuilder('/api/banking-lab/files/${item['id']}/analysis')),
      ]);
      if (responses[0].statusCode != 200) {
        throw const ApiFailure('Não foi possível abrir o arquivo.');
      }
      final analysisBody =
          jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (responses[1].statusCode != 200 || analysisBody['ok'] != true) {
        throw ApiFailure(analysisBody['message'] as String? ??
            'Não foi possível carregar a leitura do arquivo.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _FileInspectionDialog(
          item: item,
          bytes: responses[0].bodyBytes,
          inspection: Map<String, dynamic>.from(analysisBody),
          money: _money,
        ),
      );
    } catch (error) {
      _message('$error', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor:
              error ? const Color(0xFFB42332) : const Color(0xFF167A4B)));
  }

  Map<String, dynamic>? get _selectedItem =>
      _items.isEmpty || _selectedIndex >= _items.length
          ? null
          : _items[_selectedIndex];

  void _select(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() => _selectedIndex = index);
  }

  String _bankLabel(Map<String, dynamic> bank) =>
      '${bank['bank_code'] ?? 'S/C'} • ${bank['short_name']}';

  String _size(num bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';

  String _natureName(Map<String, dynamic> item) {
    final name = '${item['expense_nature_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Não categorizado' : name;
  }

  Future<void> _openNatures() async {
    await showDialog<void>(
        context: context,
        builder: (_) =>
            BankExpenseNaturesDialog(apiUriBuilder: widget.apiUriBuilder));
    if (mounted) await _load();
  }

  Future<void> _confirmEdit(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entrar no modo de edição?'),
        content: Text(
            'Deseja editar o lançamento nº ${item['sequence_number']}? Os totais serão recalculados após a gravação.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Confirmar edição')),
        ],
      ),
    );
    if (confirmed == true) await _openForm(item);
  }

  Future<void> _openRecord(Map<String, dynamic> item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: <Widget>[
          const Icon(Icons.receipt_long_rounded, color: Color(0xFF1769AA)),
          const SizedBox(width: 9),
          Expanded(child: Text('Despesa nº ${item['sequence_number']}')),
        ]),
        content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final width = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                  _readOnlyField('Data', '${item['transaction_date']}', width),
                  _readOnlyField(
                      'Forma do débito', '${item['payment_type']}', width),
                  _readOnlyField('Favorecido', '${item['destination']}', width),
                  _readOnlyField(
                      'Natureza da despesa', _natureName(item), width),
                  _readOnlyField('Valor', _money.format(item['amount']), width),
                  _readOnlyField('Descrição', '${item['description']}',
                      compact ? width : constraints.maxWidth),
                  _readOnlyField(
                      'Documento', '${item['document_number']}', width),
                  _readOnlyField('Observações', '${item['notes']}', width),
                  _readOnlyField(
                      'Arquivo / página',
                      '${item['source_filename']} • ${item['source_page'] ?? '—'}',
                      compact ? width : constraints.maxWidth),
                ]);
              }),
            )),
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: <Widget>[
          TextButton.icon(
              onPressed: () => _shareRecord(item),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Compartilhar')),
          TextButton.icon(
              onPressed: () => _printRecord(item),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimir')),
          TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _confirmEdit(item);
              },
              icon: const Icon(Icons.edit_rounded, color: Color(0xFFE18A18)),
              label: const Text('Editar')),
          TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _delete(item);
              },
              icon: const Icon(Icons.delete_forever_rounded,
                  color: Color(0xFFC43B4D)),
              label: const Text('Excluir')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<Uint8List> _recordPdf(Map<String, dynamic> item) async {
    final document = pw.Document();
    pw.Widget line(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.SizedBox(
                    width: 115,
                    child: pw.Text(label,
                        style: const pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800))),
                pw.Expanded(child: pw.Text(value)),
              ]),
        );
    document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text('Cadastro de despesas bancárias',
                      style: const pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800)),
                  pw.SizedBox(height: 5),
                  pw.Text('Registro nº ${item['sequence_number']}'),
                  pw.Divider(height: 28),
                  line('Data', '${item['transaction_date']}'),
                  line('Forma', '${item['payment_type']}'),
                  line('Favorecido', '${item['destination']}'),
                  line('Natureza', _natureName(item)),
                  line('Descrição', '${item['description']}'),
                  line('Documento', '${item['document_number']}'),
                  line('Valor', _money.format(item['amount'])),
                  line('Observações', '${item['notes']}'),
                  line('Origem',
                      '${item['source_filename']} • página ${item['source_page'] ?? '—'}'),
                ])));
    return document.save();
  }

  Future<void> _shareRecord(Map<String, dynamic> item) async {
    try {
      await Printing.sharePdf(
          bytes: await _recordPdf(item),
          filename: 'despesa-${item['sequence_number']}.pdf');
    } catch (_) {
      _message('Não foi possível compartilhar este registro.', error: true);
    }
  }

  Future<void> _printRecord(Map<String, dynamic> item) async {
    try {
      await Printing.layoutPdf(onLayout: (_) => _recordPdf(item));
    } catch (_) {
      _message('Não foi possível imprimir este registro.', error: true);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final editing = item != null;
    final date =
        TextEditingController(text: '${item?['transaction_date'] ?? ''}');
    final posting =
        TextEditingController(text: '${item?['posting_date'] ?? ''}');
    final type = TextEditingController(text: '${item?['payment_type'] ?? ''}');
    final destination =
        TextEditingController(text: '${item?['destination'] ?? ''}');
    final description =
        TextEditingController(text: '${item?['description'] ?? ''}');
    final document =
        TextEditingController(text: '${item?['document_number'] ?? ''}');
    final amount = TextEditingController(
        text: item == null ? '' : '${item['amount']}'.replaceAll('.', ','));
    final notes = TextEditingController(text: '${item?['notes'] ?? ''}');
    int? selectedNatureId = (item?['expense_nature_id'] as num?)?.toInt();
    String validation = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, updateDialog) {
        Widget field(TextEditingController controller, String label,
                {int lines = 1, TextInputType? keyboard}) =>
            TextField(
                controller: controller,
                maxLines: lines,
                keyboardType: keyboard,
                decoration: InputDecoration(
                    labelText: label, border: const OutlineInputBorder()));
        return AlertDialog(
          title: Text(editing
              ? 'Editar despesa nº ${item['sequence_number']}'
              : 'Nova despesa'),
          content: SizedBox(
              width: 660,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: field(date, 'Data da despesa (DD/MM)')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: field(posting, 'Data do lançamento (DD/MM)')),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: <Widget>[
                    Expanded(
                        child: field(
                            type, 'Forma do débito (Pix, Débito, TED...)')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: field(amount, 'Valor (R\$)',
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true))),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedNatureId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Natureza da despesa',
                        helperText:
                            'Selecione uma opção cadastrada; este campo não aceita digitação.',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder()),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Não categorizado')),
                      ..._natures.map((nature) => DropdownMenuItem<int?>(
                          value: (nature['id'] as num).toInt(),
                          child:
                              Text('${nature['code']} • ${nature['name']}'))),
                    ],
                    onChanged: (value) =>
                        updateDialog(() => selectedNatureId = value),
                  ),
                  const SizedBox(height: 12),
                  field(destination, 'Para quem foi / favorecido'),
                  const SizedBox(height: 12),
                  field(description, 'Descrição original'),
                  const SizedBox(height: 12),
                  field(document, 'Documento / referência'),
                  const SizedBox(height: 12),
                  field(notes, 'Observações', lines: 2),
                  if (editing) ...<Widget>[
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            'Origem: ${item['source_filename']} • página ${item['source_page'] ?? '—'}',
                            style: const TextStyle(
                                color: Color(0xFF66727E), fontSize: 12))),
                  ],
                  if (validation.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(validation,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ))),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (date.text.trim().isEmpty ||
                      type.text.trim().isEmpty ||
                      destination.text.trim().isEmpty ||
                      amount.text.trim().isEmpty) {
                    updateDialog(() => validation =
                        'Preencha data, forma, favorecido e valor.');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Salvar')),
          ],
        );
      }),
    );
    if (save != true || !mounted) return;
    final parsedAmount =
        double.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '.')) ??
            0;
    final payload = <String, dynamic>{
      'transaction_date': date.text.trim(),
      'posting_date':
          posting.text.trim().isEmpty ? date.text.trim() : posting.text.trim(),
      'payment_type': type.text.trim(),
      'destination': destination.text.trim(),
      'description': description.text.trim(),
      'document_number': document.text.trim(),
      'amount': parsedAmount,
      'notes': notes.text.trim(),
      'expense_nature_id': selectedNatureId,
    };
    try {
      final uri = widget.apiUriBuilder(editing
          ? '/api/banking-lab/outflows/${item['id']}'
          : '/api/banking-lab/outflows');
      final response = editing
          ? await apiClient.put(uri, body: jsonEncode(payload))
          : await apiClient.post(uri, body: jsonEncode(payload));
      final body = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if ((response.statusCode != 200 && response.statusCode != 201) ||
          body['ok'] != true) {
        throw ApiFailure(
            body['message'] as String? ?? 'Não foi possível salvar a despesa.');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir despesa?'),
        content: Text(
            'O lançamento nº ${item['sequence_number']} será retirado da lista, sem alterar o PDF original.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await apiClient.delete(
          widget.apiUriBuilder('/api/banking-lab/outflows/${item['id']}'));
      if (response.statusCode != 200) {
        throw const ApiFailure('Não foi possível excluir a despesa.');
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Extrato de despesas',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                Text('Cadastro dos débitos extraídos do arquivo',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
              ]),
          actions: <Widget>[
            IconButton(
                tooltip: 'Atualizar',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh))
          ],
        ),
        body: _loading
            ? const Center(
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Preparando os lançamentos do extrato...')
              ]))
            : _error.isNotEmpty
                ? _errorView()
                : _content(),
      );

  Widget _errorView() => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.receipt_long_outlined, size: 48),
          const SizedBox(height: 12),
          Text(_error, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente')),
        ]),
      ));

  Widget _content() => ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
        children: <Widget>[
          Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: _workspace(),
          ))
        ],
      );

  Widget _workspace() => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final controls = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _uploadCard(),
            const SizedBox(height: 10),
            _bankAccountCard(),
            const SizedBox(height: 10),
            _natureCard(),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              controls,
              const SizedBox(height: 12),
              _recordForm(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 6, child: _recordForm()),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: controls),
          ],
        );
      });

  Future<void> _openExpensesList() async {
    var routeSelectedIndex = _selectedIndex;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (routeContext) => StatefulBuilder(
        builder: (routeContext, updateRoute) => Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Listagem de despesas'),
                Text('Despesas bancárias cadastradas',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Atualizar listagem',
                onPressed: () async {
                  await _load();
                  if (routeContext.mounted) updateRoute(() {});
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(children: <Widget>[
                        const Expanded(
                          child: Text('Listagem das despesas',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900)),
                        ),
                        Text(
                          '${_summary['count'] ?? 0} registros • ${_money.format(_summary['total'] ?? 0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB42332)),
                        ),
                      ]),
                      const SizedBox(height: 7),
                      if (_items.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(26),
                            child: Text('Nenhuma despesa encontrada.'),
                          ),
                        )
                      else
                        _recordsTable(
                          selectedIndex: routeSelectedIndex,
                          onSelect: (index) {
                            _select(index);
                            updateRoute(() => routeSelectedIndex = index);
                          },
                          onEdit: (index, item) async {
                            _select(index);
                            await _confirmEdit(item);
                            if (routeContext.mounted) {
                              updateRoute(() {
                                routeSelectedIndex = _selectedIndex;
                              });
                            }
                          },
                          onDelete: (index, item) async {
                            _select(index);
                            await _delete(item);
                            if (routeContext.mounted) {
                              updateRoute(() {
                                routeSelectedIndex = _selectedIndex;
                              });
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _uploadCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFFEAF4FF), Color(0xFFF7FBFF)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB8D7F1)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x140B4F82), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF1769AA),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                        _sharedFile == null
                            ? 'Enviar comprovante'
                            : 'Comprovante recebido do celular',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF123A60))),
                    Text(
                      _sharedFile?.name ??
                          'PDF ou imagem para leitura e lançamento automático.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF526D84)),
                    ),
                  ],
                ),
              ),
              if (_sharedFile != null)
                IconButton(
                  tooltip: 'Descartar comprovante',
                  onPressed: sharedStatementService.clear,
                  icon: const Icon(Icons.close_rounded),
                ),
            ]),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final stack = constraints.maxWidth < 430;
              final upload = FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  backgroundColor: const Color(0xFF1769AA),
                  foregroundColor: Colors.white,
                ),
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file_rounded),
                label: Text(_sharedFile == null
                    ? 'Selecionar e enviar arquivo'
                    : 'Enviar comprovante'),
              );
              final repository = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  foregroundColor: const Color(0xFF123A60),
                  side: const BorderSide(color: Color(0xFF7FAED2)),
                  backgroundColor: Colors.white.withValues(alpha: .72),
                ),
                onPressed: _openReceiptsList,
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text('Repositório de comprovantes (${_files.length})'),
              );
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    upload,
                    const SizedBox(height: 8),
                    repository,
                  ],
                );
              }
              return Row(children: <Widget>[
                Expanded(child: upload),
                const SizedBox(width: 8),
                Expanded(child: repository),
              ]);
            }),
          ],
        ),
      );

  Widget _bankAccountCard() => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Row(children: <Widget>[
                Icon(Icons.account_balance_outlined, size: 19),
                SizedBox(width: 8),
                Text('Banco e conta',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(
                  flex: 3,
                  child: DropdownMenu<Map<String, dynamic>>(
                    controller: _bank,
                    expandedInsets: EdgeInsets.zero,
                    enableFilter: true,
                    enableSearch: true,
                    label: const Text('Banco'),
                    hintText: 'Banco ou código',
                    menuHeight: 320,
                    dropdownMenuEntries: _banks
                        .map((bank) => DropdownMenuEntry<Map<String, dynamic>>(
                            value: bank, label: _bankLabel(bank)))
                        .toList(),
                    onSelected: (value) =>
                        setState(() => _selectedBank = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _account,
                    decoration: const InputDecoration(
                      labelText: 'Conta',
                      prefixIcon: Icon(Icons.badge_outlined, size: 19),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      );

  Widget _natureCard() => Card(
        margin: EdgeInsets.zero,
        elevation: 1,
        color: const Color(0xFFF5EFE5),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFFD8C8AF))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: LayoutBuilder(builder: (context, constraints) {
            final button = FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9A6B2F),
                  foregroundColor: Colors.white),
              onPressed: _openNatures,
              icon: const Icon(Icons.add_circle_outline, size: 19),
              label: const Text('Criar despesa'),
            );
            if (constraints.maxWidth < 440) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _natureIntro(),
                  const SizedBox(height: 8),
                  button,
                ],
              );
            }
            return Row(children: <Widget>[
              Expanded(child: _natureIntro()),
              const SizedBox(width: 8),
              button,
            ]);
          }),
        ),
      );

  Future<void> _openReceiptsList() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (routeContext) => StatefulBuilder(
        builder: (routeContext, updateRoute) => Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Repositório de comprovantes'),
                Text('Todos os arquivos enviados e armazenados',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Atualizar comprovantes',
                onPressed: () async {
                  await _load();
                  if (routeContext.mounted) updateRoute(() {});
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        color: const Color(0xFFEAF2FA),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: <Widget>[
                          const Icon(Icons.folder_copy_outlined,
                              color: Color(0xFF1769AA)),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                                '${_files.length} arquivo(s) armazenado(s)',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w900)),
                          ),
                          const Text('Abrir  •  Baixar',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF526577))),
                        ]),
                      ),
                      Expanded(
                        child: _files.isEmpty
                            ? const Center(
                                child:
                                    Text('Nenhum comprovante foi armazenado.'))
                            : Scrollbar(
                                controller: _filesScrollController,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _filesScrollController,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  itemCount: _files.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, index) => _fileListRow(
                                    _files[index],
                                    onDeleted: () => updateRoute(() {}),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _fileListRow(
    Map<String, dynamic> file, {
    VoidCallback? onDeleted,
  }) =>
      SizedBox(
        height: 48,
        child: Row(children: <Widget>[
          Icon(
            '${file['mime_type']}'.startsWith('image/')
                ? Icons.image_outlined
                : Icons.picture_as_pdf_outlined,
            size: 20,
            color: const Color(0xFF344054),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${file['repository_title'] ?? file['filename']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12)),
                Text(
                    '${file['filename']}  •  ${_fileDateLabel(file)}  •  ${_size(file['size_bytes'] as num)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, color: Color(0xFF667085))),
              ],
            ),
          ),
          IconButton(
              tooltip: 'Ler e visualizar',
              visualDensity: VisualDensity.compact,
              onPressed: () => _viewFile(file),
              icon: const Icon(Icons.visibility_outlined,
                  size: 19, color: Color(0xFF1F6DA8))),
          IconButton(
              tooltip: 'Baixar original',
              visualDensity: VisualDensity.compact,
              onPressed: () => _downloadFile(file),
              icon: const Icon(Icons.download_outlined,
                  size: 19, color: Color(0xFF344054))),
          IconButton(
              tooltip: 'Excluir comprovante',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                if (await _deleteFile(file)) onDeleted?.call();
              },
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 19, color: Color(0xFFB42332))),
        ]),
      );

  Widget _natureIntro() => Row(children: <Widget>[
        Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: const Color(0xFFB58B55),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.category_outlined,
                color: Colors.white, size: 21)),
        const SizedBox(width: 10),
        const Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Cadastrar natureza de despesa',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: Color(0xFF74430F))),
            SizedBox(height: 2),
            Text('Organize os tipos de despesas bancárias.',
                style: TextStyle(fontSize: 11, color: Color(0xFF8A5C2A))),
          ],
        )),
      ]);

  Widget _recordForm() {
    final item = _selectedItem;
    return Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        color: const Color(0xFFF3F8FE),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFB8D7F1))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: const Color(0xFF1769AA),
                        borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Cadastro de despesas bancárias',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF123A60))),
                      Text(
                          item == null
                              ? 'Nenhum lançamento selecionado'
                              : 'Visualização do registro ${_selectedIndex + 1} de ${_items.length}',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF42627F))),
                    ],
                  )),
                  if (item != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Nº ${item['sequence_number']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1769AA))),
                    ),
                ]),
                const SizedBox(height: 8),
                if (item == null)
                  const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Não há registro para apresentar.'))
                else ...<Widget>[
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth < 510 ? 1 : 2;
                    final fieldWidth =
                        (constraints.maxWidth - ((columns - 1) * 8)) / columns;
                    return Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                      _readOnlyField(
                          'Data', '${item['transaction_date']}', fieldWidth),
                      _readOnlyField(
                          'Valor', _money.format(item['amount']), fieldWidth),
                      _readOnlyField('Favorecido', '${item['destination']}',
                          columns == 1 ? fieldWidth : fieldWidth * 2 + 8),
                      _readOnlyField(
                          'Natureza da despesa', _natureName(item), fieldWidth),
                      _readOnlyField('Forma do débito',
                          '${item['payment_type']}', fieldWidth),
                    ]);
                  }),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(14)),
                    child: Wrap(spacing: 7, runSpacing: 7, children: <Widget>[
                      _actionButton('Ver detalhes', Icons.open_in_new_rounded,
                          const Color(0xFF344054), () => _openRecord(item)),
                      _actionButton(
                          'Primeiro',
                          Icons.first_page,
                          const Color(0xFF2463A7),
                          _selectedIndex > 0 ? () => _select(0) : null),
                      _actionButton(
                          'Anterior',
                          Icons.arrow_back_ios_new_rounded,
                          const Color(0xFF3778B8),
                          _selectedIndex > 0
                              ? () => _select(_selectedIndex - 1)
                              : null),
                      _actionButton(
                          'Próximo',
                          Icons.arrow_forward_ios_rounded,
                          const Color(0xFF3778B8),
                          _selectedIndex < _items.length - 1
                              ? () => _select(_selectedIndex + 1)
                              : null),
                      _actionButton(
                          'Último',
                          Icons.last_page,
                          const Color(0xFF2463A7),
                          _selectedIndex < _items.length - 1
                              ? () => _select(_items.length - 1)
                              : null),
                      _actionButton('Nova despesa', Icons.add_circle_rounded,
                          const Color(0xFF16835A), () => _openForm(),
                          filled: true),
                      _actionButton(
                          'Listagem de despesas',
                          Icons.format_list_bulleted_rounded,
                          const Color(0xFF1769AA),
                          _openExpensesList,
                          filled: true),
                    ]),
                  ),
                ],
              ]),
        ));
  }

  Widget _actionButton(
          String label, IconData icon, Color color, VoidCallback? onPressed,
          {bool filled = false}) =>
      filled
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
              onPressed: onPressed,
              icon: Icon(icon, color: Colors.white),
              label: Text(label))
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.55)),
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 13)),
              onPressed: onPressed,
              icon: Icon(icon, color: onPressed == null ? null : color),
              label: Text(label));

  Widget _readOnlyField(String label, String value, double width) => SizedBox(
        width: width,
        child: TextFormField(
            key: ValueKey('$label-$value'),
            initialValue: value,
            readOnly: true,
            decoration: InputDecoration(
                labelText: label,
                filled: true,
                fillColor: Colors.white,
                labelStyle: const TextStyle(
                    color: Color(0xFF355777), fontWeight: FontWeight.w600),
                border: const OutlineInputBorder(),
                isDense: true)),
      );

  Widget _recordsTable({
    int? selectedIndex,
    void Function(int index)? onSelect,
    Future<void> Function(int index, Map<String, dynamic> item)? onEdit,
    Future<void> Function(int index, Map<String, dynamic> item)? onDelete,
  }) =>
      LayoutBuilder(builder: (context, constraints) {
        final activeIndex = selectedIndex ?? _selectedIndex;
        void selectRecord(int index) =>
            onSelect == null ? _select(index) : onSelect(index);
        if (constraints.maxWidth < 760) {
          return Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.2),
                borderRadius: BorderRadius.circular(16)),
            child: Column(
                children: _items.asMap().entries.map((entry) {
              return _mobileExpense(entry.key, entry.value,
                  selectedIndex: activeIndex,
                  onSelect: selectRecord,
                  onEdit: onEdit,
                  onDelete: onDelete);
            }).toList()),
          );
        }
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: Colors.black, width: 1.2)),
          child: Column(children: <Widget>[
            Container(
              color: const Color(0xFFEAF2FA),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: <Widget>[
                _tableCell('Nº', 5, header: true),
                _tableCell('Data', 7, header: true),
                _tableCell('Forma', 11, header: true),
                _tableCell('Favorecido', 18, header: true),
                _tableCell('Natureza', 14, header: true),
                _tableCell('Descrição', 20, header: true),
                _tableCell('Documento', 9, header: true),
                _tableCell('Valor', 11, header: true, alignEnd: true),
                const SizedBox(
                    width: 92,
                    child: Center(
                        child: Text('Ações',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF355777),
                                fontWeight: FontWeight.w800)))),
              ]),
            ),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final selected = index == activeIndex;
              return Material(
                color: selected ? const Color(0xFFDCEEFF) : Colors.white,
                child: FocusableActionDetector(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.numpadEnter):
                        ActivateIntent(),
                  },
                  actions: <Type, Action<Intent>>{
                    ActivateIntent:
                        CallbackAction<ActivateIntent>(onInvoke: (_) {
                      selectRecord(index);
                      _openRecord(item);
                      return null;
                    }),
                  },
                  child: InkWell(
                      onTap: () => selectRecord(index),
                      onDoubleTap: () => _openRecord(item),
                      child: Container(
                        decoration: const BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Color(0xFFE5EBF1)))),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(children: <Widget>[
                          _tableCell('${item['sequence_number']}', 5,
                              strong: true),
                          _tableCell('${item['transaction_date']}', 7),
                          _tableCell('${item['payment_type']}', 11),
                          _tableCell('${item['destination']}', 18,
                              strong: true),
                          _tableCell(_natureName(item), 14),
                          _tableCell('${item['description']}', 20),
                          _tableCell('${item['document_number']}', 9),
                          _tableCell(_money.format(item['amount']), 11,
                              strong: true, alignEnd: true, expense: true),
                          SizedBox(
                              width: 92,
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    _recordActionIcon(
                                        tooltip: 'Editar despesa',
                                        icon: Icons.edit_note_rounded,
                                        color: const Color(0xFFF39C2D),
                                        onPressed: () async {
                                          if (onEdit == null) {
                                            selectRecord(index);
                                            await _confirmEdit(item);
                                          } else {
                                            await onEdit(index, item);
                                          }
                                        }),
                                    const SizedBox(width: 6),
                                    _recordActionIcon(
                                        tooltip: 'Excluir despesa',
                                        icon: Icons.delete_sweep_rounded,
                                        color: const Color(0xFFE05265),
                                        onPressed: () async {
                                          if (onDelete == null) {
                                            selectRecord(index);
                                            await _delete(item);
                                          } else {
                                            await onDelete(index, item);
                                          }
                                        }),
                                  ])),
                        ]),
                      )),
                ),
              );
            }),
          ]),
        );
      });

  Widget _recordActionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: color.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 21, color: color),
            ),
          ),
        ),
      );

  Widget _tableCell(String text, int flex,
          {bool header = false,
          bool strong = false,
          bool alignEnd = false,
          bool expense = false}) =>
      Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(text,
              maxLines: header ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: TextStyle(
                  fontSize: header ? 12 : 13,
                  height: 1.2,
                  color: expense
                      ? const Color(0xFFB42332)
                      : header
                          ? const Color(0xFF355777)
                          : const Color(0xFF273746),
                  fontWeight:
                      header || strong ? FontWeight.w800 : FontWeight.w500)),
        ),
      );

  Widget _mobileExpense(
    int index,
    Map<String, dynamic> item, {
    int? selectedIndex,
    void Function(int index)? onSelect,
    Future<void> Function(int index, Map<String, dynamic> item)? onEdit,
    Future<void> Function(int index, Map<String, dynamic> item)? onDelete,
  }) {
    final selected = index == (selectedIndex ?? _selectedIndex);
    void selectRecord() => onSelect == null ? _select(index) : onSelect(index);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? const Color(0xFFE5F2FF) : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color:
                  selected ? const Color(0xFF4894D8) : const Color(0xFFD8E1E9),
              width: selected ? 1.5 : 1)),
      child: FocusableActionDetector(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
              selectRecord();
              _openRecord(item);
              return null;
            }),
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: selectRecord,
            onDoubleTap: () => _openRecord(item),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE6EEF6),
                              borderRadius: BorderRadius.circular(16)),
                          child: Text('Nº ${item['sequence_number']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 12))),
                      const SizedBox(width: 8),
                      Text('${item['transaction_date']}',
                          style: const TextStyle(
                              color: Color(0xFF526577),
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(_money.format(item['amount']),
                          style: const TextStyle(
                              color: Color(0xFFB42332),
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                      const SizedBox(width: 5),
                      _recordActionIcon(
                          tooltip: 'Editar despesa',
                          icon: Icons.edit_note_rounded,
                          color: const Color(0xFFF39C2D),
                          onPressed: () async {
                            if (onEdit == null) {
                              selectRecord();
                              await _confirmEdit(item);
                            } else {
                              await onEdit(index, item);
                            }
                          }),
                      const SizedBox(width: 4),
                      _recordActionIcon(
                          tooltip: 'Excluir despesa',
                          icon: Icons.delete_sweep_rounded,
                          color: const Color(0xFFE05265),
                          onPressed: () async {
                            if (onDelete == null) {
                              selectRecord();
                              await _delete(item);
                            } else {
                              await onDelete(index, item);
                            }
                          }),
                    ]),
                    const SizedBox(height: 9),
                    Text('${item['destination']}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Chip(
                              label: Text('${item['payment_type']}',
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero),
                          Chip(
                              avatar:
                                  const Icon(Icons.category_outlined, size: 15),
                              label: Text(_natureName(item),
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero),
                          if ('${item['document_number']}'.isNotEmpty)
                            Text('Doc. ${item['document_number']}',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF647483))),
                        ]),
                    Text('${item['description']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF5F6C78))),
                  ]),
            ),
          )),
    );
  }
}
