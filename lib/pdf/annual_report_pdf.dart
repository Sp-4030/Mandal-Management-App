import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../database/database_helper.dart';

class AnnualReportPdf {
  static const String _fontFamily = 'HindviMarathiFont';
  static const String _fontPath =
      'assets/fonts/NotoSerifDevanagari-Regular.ttf';

  // Keep high-resolution rendering so Marathi text remains clear.
  static const double _renderScale = 3.0;

  // Saffron theme.
  static const PdfColor _brandColor = PdfColor(0.91, 0.46, 0.0);
  static const PdfColor _accentColor = PdfColor(0.73, 0.30, 0.0);
  static const PdfColor _sectionColor = PdfColor(1.0, 0.95, 0.88);
  static const PdfColor _borderColor = PdfColor(0.91, 0.72, 0.49);
  static const PdfColor _totalColor = PdfColor(1.0, 0.95, 0.88);
  static const PdfColor _white = PdfColor(1, 1, 1);

  static Future<void> generateAndPrint({
    required int year,
  }) {
    return _generate(year: year);
  }

  static Future<void> preview({
    required int year,
    required BuildContext context,
  }) {
    return _generate(
      year: year,
      previewContext: context,
    );
  }

  static Future<void> _generate({
    required int year,
    BuildContext? previewContext,
  }) async {
    final previewNavigator = previewContext == null
        ? null
        : Navigator.of(previewContext);

    final db = DatabaseHelper.instance;

    // ==========================================================
    // DATABASE DATA
    // ==========================================================

    final vargani = await db.getVargani(year);
    final previousBalance = await db.getPreviousBalance(year);
    final prasadDengani = await db.getPrasadDengani(year);
    final prasadSahitya = await db.getPrasadSahitya(year);
    final aartiVargani = await db.getAartiVargani(year);
    final kharch = await db.getKharch(year);
    final mahaprasadKharch = await db.getMahaprasadKharch(year);

    // ==========================================================
    // FONT
    // ==========================================================

    final fontData = await rootBundle.load(_fontPath);

    final fontLoader = FontLoader(_fontFamily);
    fontLoader.addFont(Future.value(fontData));
    await fontLoader.load();

    // ==========================================================
    // TEXT CACHE
    // ==========================================================

    final Map<String, _RenderedText> textCache = {};

    Future<_RenderedText> getTextImage(
        String text, {
          double fontSize = 12,
          bool bold = false,
          TextAlign textAlign = TextAlign.left,
          double maxWidth = 900,
          ui.Color color = const ui.Color(0xFF172B30),
        }) async {
      final key =
          '$text|$fontSize|$bold|${textAlign.index}|$maxWidth|${color.hashCode}';

      final cached = textCache[key];

      if (cached != null) {
        return cached;
      }

      final rendered = await _renderText(
        text,
        fontSize: fontSize,
        bold: bold,
        textAlign: textAlign,
        maxWidth: maxWidth,
        color: color,
      );

      textCache[key] = rendered;

      return rendered;
    }

    // ==========================================================
    // GENERIC TABLE ROW
    // ==========================================================

    Future<pw.TableRow> makeRow(
        List<String> values, {
          required List<TextAlign> textAlignments,
          required List<pw.Alignment> cellAlignments,
          required List<double> maxWidths,
          double fontSize = 10.8,
          List<double>? columnFontSizes,
          bool bold = false,
          bool header = false,
          PdfColor? backgroundColor,
        }) async {
      final cells = <pw.Widget>[];

      for (var index = 0; index < values.length; index++) {
        final cellFontSize =
        (columnFontSizes != null &&
            index < columnFontSizes.length)
            ? columnFontSizes[index]
            : fontSize;

        final image = await getTextImage(
          values[index],
          fontSize: cellFontSize,
          bold: bold || header,
          textAlign: textAlignments[index],
          maxWidth: maxWidths[index],
          color: header
              ? const ui.Color(0xFFFFFFFF)
              : const ui.Color(0xFF172B30),
        );

        cells.add(
          _imageCell(
            image,
            alignment: cellAlignments[index],

            // Only NAME column gets reduced padding.
            // index 1 = नाव
            padding: index == 1
                ? const pw.EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 1,
            )
                : null,
          ),
        );
      }

      return pw.TableRow(
        repeat: header,
        verticalAlignment:
        pw.TableCellVerticalAlignment.middle,
        decoration: pw.BoxDecoration(
          color: header
              ? _brandColor
              : (backgroundColor ?? _white),
        ),
        children: cells,
      );
    }

    // ==========================================================
    // FIRST PAGE MAIN HEADING
    // ==========================================================

    final reportTitle = await getTextImage(
      'हिंदवी स्वराज्य',
      fontSize: 22,
      bold: true,
      textAlign: TextAlign.center,
      maxWidth: 700,
      color: const ui.Color(0xFFB94D00),
    );

    final reportSubtitle = await getTextImage(
      'मंडळ आर्थिक अहवाल',
      fontSize: 17,
      bold: true,
      textAlign: TextAlign.center,
      maxWidth: 700,
      color: const ui.Color(0xFF172B30),
    );

    // IMPORTANT:
    // Year is rendered directly into the PDF.
    final reportYear = await getTextImage(
      'वर्ष : $year',
      fontSize: 15,
      bold: true,
      textAlign: TextAlign.center,
      maxWidth: 400,
      color: const ui.Color(0xFFB94D00),
    );

    final pdf = pw.Document();

    // ==========================================================
    // SECTION BUILDER
    // ==========================================================

    Future<void> addSection({
      required String title,
      required List<pw.TableRow> rows,
      required Map<int, pw.TableColumnWidth> columnWidths,
      double? tableWidth,
    }) async {
      final sectionTitle = await getTextImage(
        title,
        fontSize: 16,
        bold: true,
        textAlign: TextAlign.center,
        maxWidth: 850,
        color: const ui.Color(0xFFB94D00),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,

          // A4 margins.
          margin: const pw.EdgeInsets.fromLTRB(
            30,
            20,
            30,
            24,
          ),

          maxPages: 10000,

          // ====================================================
          // HEADER
          // ====================================================

          header: (context) {
            final showReportTitle =
                context.pageNumber == 1;

            return pw.Column(
              crossAxisAlignment:
              pw.CrossAxisAlignment.stretch,
              children: [
                // ==================================================
                // MAIN REPORT HEADER - FIRST PDF PAGE ONLY
                // ==================================================

                if (showReportTitle) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: _sectionColor,
                      border: pw.Border(
                        top: pw.BorderSide(
                          color: _accentColor,
                          width: 1.0,
                        ),
                        bottom: pw.BorderSide(
                          color: _accentColor,
                          width: 1.0,
                        ),
                      ),
                    ),
                    child: pw.Column(
                      mainAxisSize:
                      pw.MainAxisSize.min,
                      children: [
                        // हिंदवी स्वराज्य
                        _image(
                          reportTitle,
                          width: 220,
                        ),

                        pw.SizedBox(height: 2),

                        // मंडळ आर्थिक अहवाल
                        _image(
                          reportSubtitle,
                          width: 250,
                        ),

                        pw.SizedBox(height: 3),

                        // वर्ष : 2026
                        pw.Container(
                          padding:
                          const pw.EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          decoration:
                          const pw.BoxDecoration(
                            color: _white,
                          ),
                          child: _image(
                            reportYear,
                            width: 160,
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 8),
                ],

                // ==================================================
                // SECTION HEADING
                // ==================================================

                pw.Container(
                  width: double.infinity,
                  padding:
                  const pw.EdgeInsets.symmetric(
                    vertical: 5,
                  ),
                  decoration:
                  const pw.BoxDecoration(
                    color: _sectionColor,
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: _brandColor,
                        width: 1,
                      ),
                    ),
                  ),
                  child: _image(
                    sectionTitle,
                    width: 300,
                  ),
                ),

                pw.SizedBox(height: 6),
              ],
            );
          },

          // ====================================================
          // TABLE
          // ====================================================

          build: (context) => [
            pw.Center(
              child: pw.Container(
                width: tableWidth,
                child: pw.Table(
                  tableWidth:
                  pw.TableWidth.max,
                  defaultVerticalAlignment:
                  pw.TableCellVerticalAlignment
                      .middle,
                  border: pw.TableBorder.all(
                    color: _borderColor,
                    width: 0.55,
                  ),
                  columnWidths: columnWidths,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ==========================================================
    // COMMON MONEY TABLE SETTINGS
    // ==========================================================

    const moneyTextAlignments = [
      TextAlign.center,
      TextAlign.center,
      TextAlign.center,
    ];

    const moneyCellAlignments = [
      pw.Alignment.center,
      pw.Alignment.center,
      pw.Alignment.center,
    ];

    const moneyMaxWidths = [
      26.0,
      260.0,
      100.0,
    ];

    const moneyColumnFontSizes = [
      10.8,
      13.0,
      10.8,
    ];

    const moneyColumnWidths =
    <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(42),
      1: pw.FlexColumnWidth(1),
      2: pw.FixedColumnWidth(100),
    };

    // ==========================================================
    // वर्गणी
    // ==========================================================

    final varganiRows = <pw.TableRow>[
      await makeRow(
        const [
          'आ न',
          'नाव',
          'रक्कम',
        ],
        textAlignments:
        moneyTextAlignments,
        cellAlignments:
        moneyCellAlignments,
        maxWidths:
        moneyMaxWidths,
        columnFontSizes:
        moneyColumnFontSizes,
        header: true,
      ),
    ];

    var varganiTotal = 0.0;

    for (
    var index = 0;
    index < vargani.length;
    index++
    ) {
      final item = vargani[index];

      final amount =
      _number(item['amount']);

      varganiTotal += amount;

      varganiRows.add(
        await makeRow(
          [
            '${index + 1}',
            item['name']?.toString() ?? '',
            _money(amount),
          ],
          textAlignments:
          moneyTextAlignments,
          cellAlignments:
          moneyCellAlignments,
          maxWidths:
          moneyMaxWidths,
          columnFontSizes:
          moneyColumnFontSizes,
        ),
      );
    }

    // Previous year balance.
    varganiRows.add(
      await makeRow(
        [
          '',
          'मागील वर्ष शिल्लक',
          _money(previousBalance),
        ],
        textAlignments:
        moneyTextAlignments,
        cellAlignments:
        moneyCellAlignments,
        maxWidths:
        moneyMaxWidths,
        columnFontSizes: const [
          10.8,
          11.2,
          10.8,
        ],
        bold: true,
        backgroundColor:
        _totalColor,
      ),
    );

    // Existing total behavior preserved.
    varganiRows.add(
      await _makeTotalRow(
        getTextImage,
        total: varganiTotal,
        maxWidths:
        moneyMaxWidths,
      ),
    );

    // ==========================================================
    // प्रसाद देणगी
    // ==========================================================

    final prasadDenganiRows =
    <pw.TableRow>[
      await makeRow(
        const [
          'आ न',
          'नाव',
          'रक्कम',
        ],
        textAlignments:
        moneyTextAlignments,
        cellAlignments:
        moneyCellAlignments,
        maxWidths:
        moneyMaxWidths,
        columnFontSizes:
        moneyColumnFontSizes,
        header: true,
      ),
    ];

    var prasadDenganiTotal = 0.0;

    for (
    var index = 0;
    index < prasadDengani.length;
    index++
    ) {
      final item =
      prasadDengani[index];

      final name =
          item['name']?.toString() ?? '';

      final amount =
      _number(item['amount']);

      prasadDenganiTotal += amount;

      prasadDenganiRows.add(
        await makeRow(
          [
            '${index + 1}',
            name,
            _money(amount),
          ],
          textAlignments:
          moneyTextAlignments,
          cellAlignments:
          moneyCellAlignments,
          maxWidths:
          moneyMaxWidths,
          columnFontSizes:
          moneyColumnFontSizes,
        ),
      );
    }

    prasadDenganiRows.add(
      await _makeTotalRow(
        getTextImage,
        total:
        prasadDenganiTotal,
        maxWidths:
        moneyMaxWidths,
      ),
    );

    // ==========================================================
    // प्रसाद साहित्य
    // ==========================================================

    final prasadSahityaRows =
    <pw.TableRow>[
      await makeRow(
        const [
          'आ न',
          'नाव',
          'देणारे साहित्य',
        ],
        textAlignments: const [
          TextAlign.center,
          TextAlign.center,
          TextAlign.center,
        ],
        cellAlignments: const [
          pw.Alignment.center,
          pw.Alignment.center,
          pw.Alignment.center,
        ],
        maxWidths: const [
          22,
          150,
          290,
        ],
        columnFontSizes: const [
          10.8,
          11.5,
          10.8,
        ],
        header: true,
      ),
    ];

    for (
    var index = 0;
    index < prasadSahitya.length;
    index++
    ) {
      final item =
      prasadSahitya[index];

      prasadSahityaRows.add(
        await makeRow(
          [
            '${index + 1}',
            item['name']?.toString() ?? '',
            item['item']?.toString() ?? '',
          ],
          textAlignments: const [
            TextAlign.center,
            TextAlign.center,
            TextAlign.center,
          ],
          cellAlignments: const [
            pw.Alignment.center,
            pw.Alignment.center,
            pw.Alignment.center,
          ],
          maxWidths: const [
            22,
            150,
            290,
          ],
          columnFontSizes: const [
            10.8,
            11.5,
            10.8,
          ],
        ),
      );
    }

    // ==========================================================
    // आरतीतील वर्गणी
    // ==========================================================

    final aartiRows =
    <pw.TableRow>[
      await makeRow(
        const [
          'आ न',
          'नाव',
          'रक्कम',
        ],
        textAlignments:
        moneyTextAlignments,
        cellAlignments:
        moneyCellAlignments,
        maxWidths:
        moneyMaxWidths,
        columnFontSizes:
        moneyColumnFontSizes,
        header: true,
      ),
    ];

    var aartiTotal = 0.0;

    for (
    var index = 0;
    index < aartiVargani.length;
    index++
    ) {
      final item =
      aartiVargani[index];

      final amount =
      _number(item['amount']);

      aartiTotal += amount;

      aartiRows.add(
        await makeRow(
          [
            '${index + 1}',
            item['name']?.toString() ?? '',
            _money(amount),
          ],
          textAlignments:
          moneyTextAlignments,
          cellAlignments:
          moneyCellAlignments,
          maxWidths:
          moneyMaxWidths,
          columnFontSizes:
          moneyColumnFontSizes,
        ),
      );
    }

    aartiRows.add(
      await _makeTotalRow(
        getTextImage,
        total: aartiTotal,
        maxWidths:
        moneyMaxWidths,
      ),
    );

    // ==========================================================
    // खर्च
    // ==========================================================

    final expenseWidths =
    <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(36),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(1.5),
      3: const pw.FixedColumnWidth(80),
    };

    const expenseAlignments = [
      TextAlign.center,
      TextAlign.center,
      TextAlign.center,
      TextAlign.center,
    ];

    const expenseCellAlignments = [
      pw.Alignment.center,
      pw.Alignment.center,
      pw.Alignment.center,
      pw.Alignment.center,
    ];

    const expenseMaxWidths = [
      22.0,
      155.0,
      200.0,
      65.0,
    ];

    final kharchRows =
    <pw.TableRow>[
      await makeRow(
        const [
          'आ न',
          'साहित्य / वस्तू',
          'ठरविणारा व आणाऱ्यांची नावे',
          'खर्च रक्कम',
        ],
        textAlignments:
        expenseAlignments,
        cellAlignments:
        expenseCellAlignments,
        maxWidths:
        expenseMaxWidths,
        fontSize: 11,
        header: true,
      ),
    ];

    var kharchTotal = 0.0;

    for (
    var index = 0;
    index < kharch.length;
    index++
    ) {
      final item = kharch[index];

      final amount =
      _number(item['amount']);

      kharchTotal += amount;

      kharchRows.add(
        await makeRow(
          [
            '${index + 1}',
            item['item']?.toString() ?? '',
            item['buyer_name']
                ?.toString() ??
                '',
            _money(amount),
          ],
          textAlignments:
          expenseAlignments,
          cellAlignments:
          expenseCellAlignments,
          maxWidths:
          expenseMaxWidths,
          fontSize: 11,
        ),
      );
    }

    kharchRows.add(
      await _makeExpenseTotalRow(
        getTextImage,
        total: kharchTotal,
        maxWidths:
        expenseMaxWidths,
      ),
    );

    // ==========================================================
    // महाप्रसाद बाजार
    // ==========================================================

    final mahaprasadRows =
    <pw.TableRow>[
      await makeRow(
        const [
          'आ न',
          'साहित्य',
          'वस्तू खरेदीदाराचे नावे',
          'खर्च',
        ],
        textAlignments:
        expenseAlignments,
        cellAlignments:
        expenseCellAlignments,
        maxWidths:
        expenseMaxWidths,
        fontSize: 11,
        header: true,
      ),
    ];

    var mahaprasadTotal = 0.0;

    for (
    var index = 0;
    index < mahaprasadKharch.length;
    index++
    ) {
      final item =
      mahaprasadKharch[index];

      final amount =
      _number(item['amount']);

      mahaprasadTotal += amount;

      mahaprasadRows.add(
        await makeRow(
          [
            '${index + 1}',
            item['item']?.toString() ?? '',
            item['buyer_name']
                ?.toString() ??
                '',
            _money(amount),
          ],
          textAlignments:
          expenseAlignments,
          cellAlignments:
          expenseCellAlignments,
          maxWidths:
          expenseMaxWidths,
          fontSize: 11,
        ),
      );
    }

    mahaprasadRows.add(
      await _makeExpenseTotalRow(
        getTextImage,
        total:
        mahaprasadTotal,
        maxWidths:
        expenseMaxWidths,
      ),
    );

    // ==========================================================
    // PDF SECTION ORDER
    // ==========================================================

    await addSection(
      title: 'वर्गणी',
      rows: varganiRows,
      columnWidths:
      moneyColumnWidths,
      tableWidth: 410,
    );

    await addSection(
      title: 'प्रसाद देणगी',
      rows: prasadDenganiRows,
      columnWidths:
      moneyColumnWidths,
      tableWidth: 410,
    );

    await addSection(
      title: 'प्रसाद साहित्य',
      rows: prasadSahityaRows,
      columnWidths: const {
        0: pw.FixedColumnWidth(42),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.7),
      },
    );

    await addSection(
      title: 'आरतीतील वर्गणी',
      rows: aartiRows,
      columnWidths:
      moneyColumnWidths,
      tableWidth: 410,
    );

    await addSection(
      title: 'खर्च',
      rows: kharchRows,
      columnWidths:
      expenseWidths,
    );

    await addSection(
      title: 'महाप्रसाद बाजार',
      rows: mahaprasadRows,
      columnWidths:
      expenseWidths,
    );

    // ==========================================================
    // PRINT / PREVIEW
    // ==========================================================

    if (previewNavigator == null) {
      await Printing.layoutPdf(
        onLayout:
            (PdfPageFormat format) async {
          return pdf.save();
        },
      );
    } else if (previewNavigator.mounted) {
      await previewNavigator.push<void>(
        MaterialPageRoute<void>(
          builder: (context) {
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  'वार्षिक अहवाल ($year)',
                ),
              ),
              body: PdfPreview(
                build: (format) =>
                    pdf.save(),
              ),
            );
          },
        ),
      );
    }
  }

  // ============================================================
  // MONEY TOTAL ROW
  // ============================================================

  static Future<pw.TableRow> _makeTotalRow(
      Future<_RenderedText> Function(
          String, {
          double fontSize,
          bool bold,
          TextAlign textAlign,
          double maxWidth,
          ui.Color color,
          }) getTextImage, {
        required double total,
        required List<double> maxWidths,
      }) async {
    final blank = await getTextImage(
      '',
      maxWidth: maxWidths[0],
    );

    final label = await getTextImage(
      'Total',
      fontSize: 11.8,
      bold: true,
      textAlign: TextAlign.center,
      maxWidth: maxWidths[1],
    );

    final amount = await getTextImage(
      _money(total),
      fontSize: 11.8,
      bold: true,
      textAlign: TextAlign.center,
      maxWidth: maxWidths[2],
    );

    return pw.TableRow(
      verticalAlignment:
      pw.TableCellVerticalAlignment
          .middle,
      decoration:
      const pw.BoxDecoration(
        color: _totalColor,
      ),
      children: [
        _imageCell(
          blank,
          alignment: pw.Alignment.center,
        ),
        _imageCell(
          label,
          alignment: pw.Alignment.center,
        ),
        _imageCell(
          amount,
          alignment: pw.Alignment.center,
        ),
      ],
    );
  }

  // ============================================================
  // EXPENSE TOTAL ROW
  // ============================================================

  static Future<pw.TableRow>
  _makeExpenseTotalRow(
      Future<_RenderedText> Function(
          String, {
          double fontSize,
          bool bold,
          TextAlign textAlign,
          double maxWidth,
          ui.Color color,
          }) getTextImage, {
        required double total,
        required List<double> maxWidths,
      }) async {
    final cells = <pw.Widget>[];

    for (var index = 0;
    index < 4;
    index++) {
      if (index == 2) {
        final label =
        await getTextImage(
          'Total',
          fontSize: 11.8,
          bold: true,
          textAlign: TextAlign.center,
          maxWidth:
          maxWidths[index],
        );

        cells.add(
          _imageCell(
            label,
            alignment:
            pw.Alignment.center,
          ),
        );
      } else if (index == 3) {
        final amount =
        await getTextImage(
          _money(total),
          fontSize: 11.8,
          bold: true,
          textAlign: TextAlign.center,
          maxWidth:
          maxWidths[index],
        );

        cells.add(
          _imageCell(
            amount,
            alignment:
            pw.Alignment.center,
          ),
        );
      } else {
        final blank =
        await getTextImage(
          '',
          maxWidth:
          maxWidths[index],
        );

        cells.add(
          _imageCell(
            blank,
            alignment:
            pw.Alignment.center,
          ),
        );
      }
    }

    return pw.TableRow(
      verticalAlignment:
      pw.TableCellVerticalAlignment
          .middle,
      decoration:
      const pw.BoxDecoration(
        color: _totalColor,
      ),
      children: cells,
    );
  }

  // ============================================================
  // HIGH-QUALITY MARATHI TEXT RENDERING
  // ============================================================

  static Future<_RenderedText>
  _renderText(
      String text, {
        double fontSize = 10.8,
        bool bold = false,
        TextAlign textAlign =
            TextAlign.left,
        double maxWidth = 900,
        ui.Color color =
        const ui.Color(0xFF172B30),
      }) async {
    final recorder =
    ui.PictureRecorder();

    final canvas = ui.Canvas(
      recorder,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: fontSize,
          fontWeight: bold
              ? FontWeight.bold
              : FontWeight.normal,
          height: 1.20,
          color: color,
        ),
      ),
      textAlign: textAlign,
      textDirection:
      TextDirection.ltr,
    );

    textPainter.layout(
      minWidth: 0,
      maxWidth: maxWidth,
    );

    final logicalWidth =
        textPainter.width.ceil() + 8;

    final logicalHeight =
        textPainter.height.ceil() + 8;

    final pixelWidth =
    (logicalWidth *
        _renderScale)
        .ceil();

    final pixelHeight =
    (logicalHeight *
        _renderScale)
        .ceil();

    // Render at 3x resolution.
    canvas.scale(
      _renderScale,
      _renderScale,
    );

    canvas.drawColor(
      const ui.Color(0x00000000),
      ui.BlendMode.srcOver,
    );

    textPainter.paint(
      canvas,
      const ui.Offset(4, 4),
    );

    final picture =
    recorder.endRecording();

    final image =
    await picture.toImage(
      pixelWidth,
      pixelHeight,
    );

    final byteData =
    await image.toByteData(
      format:
      ui.ImageByteFormat.png,
    );

    image.dispose();
    picture.dispose();

    if (byteData == null) {
      throw Exception(
        'Marathi text image could not be generated.',
      );
    }

    return _RenderedText(
      bytes:
      byteData.buffer
          .asUint8List(),
      logicalWidth:
      logicalWidth.toDouble(),
      logicalHeight:
      logicalHeight.toDouble(),
    );
  }

  // ============================================================
  // PDF IMAGE
  // ============================================================

  static pw.Widget _image(
      _RenderedText rendered, {
        double? width,
      }) {
    return pw.Center(
      child: pw.ConstrainedBox(
        constraints:
        pw.BoxConstraints(
          maxWidth:
          width ??
              rendered.logicalWidth,
        ),
        child: pw.Image(
          pw.MemoryImage(
            rendered.bytes,
          ),
          width:
          rendered.logicalWidth,
          height:
          rendered.logicalHeight,
          fit:
          pw.BoxFit.scaleDown,
        ),
      ),
    );
  }

  // ============================================================
  // TABLE CELL
  // ============================================================

  static pw.Widget _imageCell(
      _RenderedText rendered, {
        pw.Alignment alignment =
            pw.Alignment.center,
        pw.EdgeInsets? padding,
      }) {
    return pw.Container(
      width: double.infinity,
      alignment: alignment,

      // Name column uses smaller padding.
      padding: padding ??
          const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 3.8,
          ),

      child: pw.Image(
        pw.MemoryImage(
          rendered.bytes,
        ),
        width:
        rendered.logicalWidth,
        height:
        rendered.logicalHeight,
        fit:
        pw.BoxFit.contain,
      ),
    );
  }

  // ============================================================
  // NUMBER
  // ============================================================

  static double _number(
      dynamic value,
      ) {
    if (value == null) {
      return 0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        0;
  }

  // ============================================================
  // MONEY FORMAT
  // ============================================================

  static String _money(
      double value,
      ) {
    return '₹ ${_formatIndianNumber(value.round())}';
  }

  static String _formatIndianNumber(
      int number,
      ) {
    final value = number.abs();

    final text =
    value.toString();

    if (text.length <= 3) {
      return number < 0
          ? '-$text'
          : text;
    }

    final lastThree =
    text.substring(
      text.length - 3,
    );

    var remaining =
    text.substring(
      0,
      text.length - 3,
    );

    final parts =
    <String>[];

    while (remaining.length > 2) {
      parts.insert(
        0,
        remaining.substring(
          remaining.length - 2,
        ),
      );

      remaining =
          remaining.substring(
            0,
            remaining.length - 2,
          );
    }

    if (remaining.isNotEmpty) {
      parts.insert(
        0,
        remaining,
      );
    }

    final result =
        '${parts.join(',')},$lastThree';

    return number < 0
        ? '-$result'
        : result;
  }
}

// ============================================================
// RENDERED TEXT MODEL
// ============================================================

class _RenderedText {
  final Uint8List bytes;
  final double logicalWidth;
  final double logicalHeight;

  const _RenderedText({
    required this.bytes,
    required this.logicalWidth,
    required this.logicalHeight,
  });
}