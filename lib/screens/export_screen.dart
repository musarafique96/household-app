import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/ui.dart';

class _ExportData {
  final List<Expense> expenses;
  final Map<int, String> catNames;
  final double total;

  const _ExportData(this.expenses, this.catNames, this.total);
}

/// Exports one month of expenses as a PDF, or copies it for Excel and Google Sheets.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _month = _currentMonth;
  late Future<_ExportData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExportData?> _load() async {
    final user = Session.current.value;
    if (user == null) return null;
    final cats = await Db.instance.categories(user.id);
    final exps = await Db.instance.expenses(user.id, _month);
    final sorted = [...exps]..sort((a, b) => a.date.compareTo(b.date));
    final total = sorted.fold<double>(0.0, (s, e) => s + e.amount);
    return _ExportData(sorted, {for (final c in cats) c.id: c.name}, total);
  }

  void _shift(int delta) {
    final next = DateTime(_month.year, _month.month + delta, 1);
    if (next.isAfter(_currentMonth)) return;
    setState(() {
      _month = next;
      _future = _load();
    });
  }

  List<List<String>> _rows(_ExportData d) => [
        for (final e in d.expenses)
          [
            ymd(e.date),
            d.catNames[e.categoryId] ?? '',
            e.note,
            e.amount.toStringAsFixed(2),
          ],
      ];

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copyForExcel(_ExportData d, AppUser user) async {
    final buffer = StringBuffer()..writeln('Date\tCategory\tNote\tAmount\tCurrency');
    for (final row in _rows(d)) {
      buffer.writeln('${row.join('\t')}\t${user.currency}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _snack('Copied. Paste into Excel or Google Sheets.');
  }

  Future<void> _sharePdf(_ExportData d, AppUser user) async {
    final cur = user.currency;
    final rows = _rows(d);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('Household expenses',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('${monthLabel(_month)}  •  Total ${money(d.total, cur)}'),
          pw.SizedBox(height: 16),
          if (rows.isEmpty)
            pw.Text('No expenses this month.')
          else
            pw.Table.fromTextArray(
              headers: ['Date', 'Category', 'Note', 'Amount ($cur)'],
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            ),
        ],
      ),
    );
    final bytes = await doc.save();
    final fileMonth = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    await Printing.sharePdf(bytes: bytes, filename: 'household-$fileMonth.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.current.value;

    return Scaffold(
      body: user == null
          ? const Center(child: Text('Choose an account in the Accounts tab first.'))
          : FutureBuilder<_ExportData?>(
              future: _future,
              builder: (context, snap) {
                final d = snap.data;
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    GradientHeader(
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          const Text('Export',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: !snap.hasData || d == null
                          ? const Center(child: CircularProgressIndicator())
                          : _body(d, user),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _body(_ExportData d, AppUser user) {
    final isCurrent = _month == _currentMonth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(monthLabel(_month),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: isCurrent ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          child: Row(
            children: [
              const IconBubble(icon: Icons.receipt_long_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${d.expenses.length} expenses • ${money(d.total, user.currency)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _sharePdf(d, user),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('Share as PDF'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
          ),
          onPressed: () => _copyForExcel(d, user),
          icon: const Icon(Icons.table_chart_rounded),
          label: const Text('Copy for Excel / Sheets'),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Preview'),
        const SizedBox(height: 8),
        if (d.expenses.isEmpty)
          const SoftCard(child: Text('No expenses this month.'))
        else
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            child: Column(
              children: [
                for (final e in d.expenses)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.note.isNotEmpty ? e.note : (d.catNames[e.categoryId] ?? ''),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${ymd(e.date)} • ${d.catNames[e.categoryId] ?? ''}',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(money(e.amount, user.currency),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 40),
      ],
    );
  }
}
