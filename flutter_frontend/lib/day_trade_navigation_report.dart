import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<Uint8List> buildDayTradeNavigationReport({
  required String period,
  required String generatedAt,
  required List<NavigationReportMetric> metrics,
  required List<List<String>> rows,
}) async {
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  final document = pw.Document(
    title: 'Relatório de Navegação de Operações - EKT IA Systems',
    author: 'EKT IA Systems',
    subject: 'Operações Day Trade registradas no sistema',
    theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 24),
      header: (pw.Context context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey700, width: .8),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'EKT IA SYSTEMS',
              style: const pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: .5,
              ),
            ),
            pw.Text(
              'DAY TRADE | NAVEGAÇÃO DE OPERAÇÕES',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      footer: (pw.Context context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 7),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey500, width: .5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text(
              'Documento gerado a partir dos registros do sistema.',
              style:
                  const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.SizedBox(height: 14),
        pw.Text(
          'Relatório de operações Day Trade',
          style:
              const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Período dos registros: $period | Gerado em: $generatedAt',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: <pw.Widget>[
            for (var index = 0; index < metrics.length; index++) ...<pw.Widget>[
              if (index > 0) pw.SizedBox(width: 7),
              pw.Expanded(child: _metric(metrics[index])),
            ],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'REGISTROS DAS OPERAÇÕES',
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: .35,
          ),
        ),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500, width: .6),
            ),
            child: pw.Text(
              'Nenhuma operação cadastrada.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9),
            ),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Data',
              'Horario',
              'Ativo',
              'Mercado',
              'Tipo',
              'Qtd.',
              'Entrada',
              'Stop',
              'Alvo',
              'Saída',
              'R\$ líquido',
              'Pontos',
              'Status',
              'Estratégia',
            ],
            data: rows,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
            headerStyle: const pw.TextStyle(
              color: PdfColors.white,
              fontSize: 6.6,
              fontWeight: pw.FontWeight.bold,
            ),
            headerAlignment: pw.Alignment.center,
            cellStyle: const pw.TextStyle(fontSize: 6.3),
            cellAlignment: pw.Alignment.center,
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4.2),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey500, width: .45),
            columnWidths: <int, pw.TableColumnWidth>{
              0: const pw.FixedColumnWidth(46),
              1: const pw.FixedColumnWidth(55),
              2: const pw.FixedColumnWidth(38),
              3: const pw.FixedColumnWidth(57),
              4: const pw.FixedColumnWidth(38),
              5: const pw.FixedColumnWidth(27),
              6: const pw.FixedColumnWidth(48),
              7: const pw.FixedColumnWidth(48),
              8: const pw.FixedColumnWidth(48),
              9: const pw.FixedColumnWidth(48),
              10: const pw.FixedColumnWidth(56),
              11: const pw.FixedColumnWidth(40),
              12: const pw.FixedColumnWidth(50),
              13: const pw.FlexColumnWidth(),
            },
          ),
      ],
    ),
  );

  return Uint8List.fromList(await document.save());
}

pw.Widget _metric(NavigationReportMetric metric) => pw.Container(
      height: 46,
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey500, width: .55),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(
            metric.label.toUpperCase(),
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            metric.value,
            maxLines: 1,
            style: const pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

class NavigationReportMetric {
  const NavigationReportMetric(this.label, this.value);

  final String label;
  final String value;
}
