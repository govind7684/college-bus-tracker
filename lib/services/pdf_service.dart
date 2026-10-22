import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

/// Amount for the screens, e.g. "₹12,500".
String rupee(num v) => '₹${_inr.format(v)}';

/// Amount for PDFs. The built-in PDF font has no rupee sign, so "Rs." is used.
String rs(num v) => 'Rs. ${_inr.format(v)}';

/// PDF reports and receipts. The built-in PDF font covers English / Latin text only.
class PdfService {
  static const college = 'Carmel Polytechnic College, Punnapra';

  /// A titled table report (fees, accounts). [summary] rows are printed under the table as label / value pairs.
  static Future<void> shareTable({
    required String fileName,
    required String title,
    String subtitle = '',
    required List<String> headers,
    required List<List<String>> rows,
    List<List<String>> summary = const [],
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(college, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (subtitle.isNotEmpty) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 10),
        ]),
        footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Generated ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]),
        build: (c) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          ),
          if (summary.isNotEmpty) pw.SizedBox(height: 14),
          for (final s in summary)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(children: [
                pw.SizedBox(width: 160, child: pw.Text(s[0], style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                pw.Text(s[1], style: const pw.TextStyle(fontSize: 10)),
              ]),
            ),
        ],
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: fileName);
  }

  /// One fee payment receipt (A5).
  static Future<void> shareReceipt({
    required String receiptNo,
    required String date,
    required String student,
    required String admissionNo,
    required String className,
    required String bus,
    required String feeTitle,
    required int feeAmount,
    required int amount,
    required int paidToDate,
    required String mode,
    String note = '',
  }) async {
    pw.Widget line(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 11))),
          ]),
        );
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(30),
        build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(college, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('College Bus - Fee Receipt', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Divider(),
          line('Receipt no', receiptNo),
          line('Date', date),
          line('Student', student),
          if (admissionNo.isNotEmpty) line('Admission no', admissionNo),
          if (className.isNotEmpty) line('Class', className),
          line('Bus', bus),
          pw.Divider(),
          line('Fee', feeTitle),
          line('Fee amount', rs(feeAmount)),
          line('Received now', rs(amount)),
          line('Payment mode', mode),
          line('Total paid to date', rs(paidToDate)),
          line('Balance due', rs(feeAmount - paidToDate)),
          if (note.isNotEmpty) line('Note', note),
          pw.Spacer(),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Authorised signature', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
        ]),
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: '$receiptNo.pdf');
  }
}
