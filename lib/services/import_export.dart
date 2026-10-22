/// Minimal CSV helpers (no extra package): quoted fields, embedded commas / quotes / line breaks.
class Csv {
  static String _cell(Object? v) {
    final s = v == null ? '' : v.toString();
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static String encode(List<String> header, List<List<Object?>> rows) =>
      [header, ...rows].map((r) => r.map(_cell).join(',')).join('\n');

  /// Parses CSV text into rows of cells (empty lines skipped).
  static List<List<String>> decode(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    final t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    void endCell() {
      row.add(cell.toString().trim());
      cell.clear();
    }

    void endRow() {
      endCell();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        endCell();
      } else if (ch == '\n') {
        endRow();
      } else {
        cell.write(ch);
      }
    }
    endRow();
    return rows;
  }
}
