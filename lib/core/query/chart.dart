/// A query shown as a chart (`show: chart`; the port's own, Matt 2026-10-30, "add all 12"): its records counted or
/// added up by one field, as bars, a line or a pie, drawn by the app (lib/editor/queries/query_chart.dart) and not by
/// Mermaid, whose ```mermaid charts stay as they are.
///
///     ```query
///     from: tickets #kiln
///     show: chart
///     chart: bar
///     x: status
///     y: sum(hours)
///     series: assignee
///     ```
///
/// - **x:** the field the bars (a line's points, a pie's slices) are of; `group:` where unsaid, else the status. Its
///   values are a group's (run.dart): in the order they sort, a list's record in a bar for each thing it holds, the
///   records with nothing in it last ("No status"). A day field's days are its bars, a month each where there are
///   more than [dayBars] of them.
/// - **y:** what each bar measures: `count` (where unsaid), or `sum`, `average`, `min`, `max` or `percent` of a field
///   (rollup.dart `aggregate`, which a rollup works out with too), rollups among the fields.
/// - **series:** a field each bar is split by, a colour each, stacked in a bar, a line each, in a pie left out.
///
/// Each bar keeps the keys of the rows in it, so a tap on it lists those rows under the chart, as a board's lane
/// does. Pure; the drawing only draws.
library;

import '../days.dart' show dateOfDay;
import 'read.dart';
import 'records.dart';
import 'rollup.dart';
import 'values.dart';

/// More days than this on a chart's x are counted by the month.
const int dayBars = 31;

/// One bar's place on x, or one series: its key (run.dart's group key), and what it is called.
class ChartBucket extends QueryData {
  const ChartBucket({required this.key, required this.label});
  final String key;
  final String label;
  @override
  Object? toJson() => {'key': key, 'label': label};
}

/// What one bar of one series measures: its value, as a cell says it, and the rows in it.
class ChartPoint extends QueryData {
  const ChartPoint({required this.value, required this.text, required this.keys});

  /// Null where there is nothing to measure (an average of no numbers).
  final double? value;
  final String text;
  final List<String> keys;
  @override
  Object? toJson() => {'value': value, 'text': text, 'keys': keys};
}

class ChartData extends QueryData {
  const ChartData({required this.kind, required this.x, required this.xLabel, required this.measure, required this.yLabel, required this.seriesField, required this.buckets, required this.series, required this.points});

  final ChartKind kind;
  final String x;
  final String xLabel;
  final Measure measure;

  /// What y says, `Count`, `Sum of hours`.
  final String yLabel;
  final String? seriesField;

  /// The bars, in order.
  final List<ChartBucket> buckets;

  /// The series, in order; one with an empty key and label where the chart is not split.
  final List<ChartBucket> series;

  /// `points[bar][series]`.
  final List<List<ChartPoint>> points;

  /// A bar's whole: its series added up (a stacked bar's height, a pie's slice).
  double whole(int bar) => points[bar].fold<double>(0, (sum, point) => sum + (point.value ?? 0));

  /// The tallest whole bar, or the greatest point of a line.
  double get most {
    var top = 0.0;
    for (var bar = 0; bar < buckets.length; bar += 1) {
      if (kind == ChartKind.line) {
        for (final point in points[bar]) {
          if ((point.value ?? 0) > top) top = point.value!;
        }
      } else {
        final all = whole(bar);
        if (all > top) top = all;
      }
    }
    return top;
  }

  /// The rows in a bar, or in one series of it.
  List<String> keysOf(int bar, [int? series]) => series == null ? <String>{for (final point in points[bar]) ...point.keys}.toList() : points[bar][series].keys;

  @override
  Object? toJson() => {
        'kind': kind.name,
        'x': x,
        'xLabel': xLabel,
        'measure': measure.toJson(),
        'yLabel': yLabel,
        'series': seriesField,
        'buckets': [for (final bucket in buckets) bucket.toJson()],
        'seriesBuckets': [for (final each in series) each.toJson()],
        'points': [
          for (final bar in points) [for (final point in bar) point.toJson()],
        ],
      };
}

/// What y says as words.
String measureLabel(Measure measure) {
  final field = measure.field;
  return switch (measure.fn) {
    Aggregate.count => field == null ? 'Count' : 'Count of ${fieldLabel(field).toLowerCase()}',
    Aggregate.sum => 'Sum of ${fieldLabel(field ?? '').toLowerCase()}',
    Aggregate.average => 'Average ${fieldLabel(field ?? '').toLowerCase()}',
    Aggregate.min => 'Least ${fieldLabel(field ?? '').toLowerCase()}',
    Aggregate.max => 'Most ${fieldLabel(field ?? '').toLowerCase()}',
    Aggregate.percent => field == null ? 'Done' : 'Done, by ${fieldLabel(field).toLowerCase()}',
  };
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A month's short name, `Oct 2026`.
String _monthWords(String month) {
  final at = dateOfDay('$month-01');
  return at == null ? month : '${_months[at.month - 1]} ${at.year}';
}

class _Bucketed {
  _Bucketed(this.key, this.value, this.label);
  final String key;
  final Value value;
  final String label;
  final Set<int> records = {};
}

/// [records] in buckets by [field]: a group's way (run.dart), the bucket with nothing last; a day field by the month
/// where it has more than [dayBars] days.
List<_Bucketed> _bucketsOf(List<QueryRecord> records, String field, FieldLook look) {
  final values = [for (final record in records) look(record, field)];
  final days = <String>{
    for (final value in values)
      if (value is DayValue) value.day,
  };
  final byMonth = days.length > dayBars;
  final buckets = <String, _Bucketed>{};
  for (final (index, value) in values.indexed) {
    final each = isEmptyValue(value) ? [value] : groupValues(value);
    for (final one in each) {
      final Value placed;
      final String key;
      final String label;
      if (byMonth && one is DayValue) {
        final month = one.day.substring(0, 7);
        placed = DayValue('$month-01');
        key = 'month:$month';
        label = _monthWords(month);
      } else {
        placed = one;
        key = groupKey(one);
        label = isEmptyValue(one) ? 'No ${fieldLabel(field).toLowerCase()}' : (one is BoolValue ? (one.on ? 'Done' : 'Not done') : (one is ListValue && one.tags ? '#${one.items[0]}' : valueText(one)));
      }
      final bucket = buckets.putIfAbsent(key, () => _Bucketed(key, placed, label));
      bucket.records.add(index);
    }
  }
  final ordered = buckets.values.toList();
  // Stable: two that compare the same stay as they came.
  final at = {for (final (index, bucket) in ordered.indexed) bucket: index};
  ordered.sort((a, b) {
    final none = (a.key.isEmpty ? 1 : 0) - (b.key.isEmpty ? 1 : 0);
    if (none != 0) return none;
    final order = compareValues(a.value, b.value);
    if (order != 0) return order < 0 ? -1 : 1;
    return at[a]! - at[b]!;
  });
  return ordered;
}

/// The chart [query] asks for, over the [records] it shows (in its order), [keyOf] each one's row's key, and each
/// field read through [look]. [group] is the field the query groups by, x's where `x:` is unsaid.
ChartData chartOf(Query query, List<QueryRecord> records, String Function(QueryRecord record) keyOf, FieldLook look, {String? group}) {
  final x = query.x ?? group ?? 'status';
  final measure = query.y ?? const Measure(Aggregate.count);
  final seriesField = query.series;
  final kind = query.chart ?? ChartKind.bar;
  final bars = _bucketsOf(records, x, look);
  final split = seriesField != null && kind != ChartKind.pie ? _bucketsOf(records, seriesField, look) : null;
  final series = split == null ? const [ChartBucket(key: '', label: '')] : [for (final each in split) ChartBucket(key: each.key, label: each.label)];
  final points = <List<ChartPoint>>[];
  for (final bar in bars) {
    final row = <ChartPoint>[];
    for (var s = 0; s < series.length; s += 1) {
      final inside = split == null ? bar.records : [for (final index in bar.records) if (split[s].records.contains(index)) index];
      final over = [for (final index in inside) records[index]];
      final value = aggregate(measure, over, look);
      row.add(ChartPoint(value: numberOf(value), text: value is DayValue ? value.day : valueText(value), keys: [for (final record in over) keyOf(record)]));
    }
    points.add(row);
  }
  return ChartData(
    kind: kind,
    x: x,
    xLabel: fieldLabel(x),
    measure: measure,
    yLabel: measureLabel(measure),
    seriesField: split == null ? null : seriesField,
    buckets: [for (final bar in bars) ChartBucket(key: bar.key, label: bar.label)],
    series: series,
    points: points,
  );
}
