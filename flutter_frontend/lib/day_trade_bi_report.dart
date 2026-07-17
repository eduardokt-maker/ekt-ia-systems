import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> printDayTradeBiReport({
  required String period,
  required Map<String, String> indicators,
  required List<List<String>> dailyRows,
}) async {
  final document = pw.Document(
    title: 'Relatório BI - INTRADAY - $period',
    author: 'EKT IA Systems',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border:
              pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey700)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text('EKT IA SYSTEMS',
                style: const pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text('BI - INTRADAY', style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (context) => <pw.Widget>[
        pw.SizedBox(height: 18),
        pw.Text('Relatório gerencial de operações Day Trade',
            style: const pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Text('Período: $period • Conta real • Documento somente leitura',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 20),
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: indicators.entries
              .map((entry) => pw.Container(
                    width: 160,
                    padding: const pw.EdgeInsets.all(10),
                    // Border helpers from the PDF package are not const.
                    // ignore: prefer_const_constructors
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Text(entry.key,
                            style: const pw.TextStyle(
                                fontSize: 8, color: PdfColors.grey700)),
                        pw.SizedBox(height: 4),
                        pw.Text(entry.value,
                            style: const pw.TextStyle(
                                fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ))
              .toList(),
        ),
        pw.SizedBox(height: 24),
        pw.Text('Resumo cronológico',
            style: const pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (dailyRows.isEmpty)
          pw.Text('Nenhuma operação encerrada no período informado.')
        else
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Data',
              'Operações',
              'Gains',
              'Losses',
              'Acerto',
              'Resultado'
            ],
            data: dailyRows,
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerStyle: const pw.TextStyle(
                color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Este relatório é informativo e consolida exclusivamente as operações registradas no sistema.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  await Printing.layoutPdf(
    name: 'BI-Day-Trade-$period.pdf',
    onLayout: (_) async => Uint8List.fromList(await document.save()),
  );
}
