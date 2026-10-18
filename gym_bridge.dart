// lib/features/body/data/gym_bridge.dart
// Адаптер: тренировки (из GymMane-БД или CSV) -> MuscleStimulus.
// ExerciseCatalog — временная замена; подключите маппинг упражнение->мышцы из GymMane.
import 'package:csv/csv.dart';
import '../domain/recovery_model.dart';

class WorkoutSet {
  const WorkoutSet({required this.at, required this.exercise, required this.weightKg, required this.reps});
  final DateTime at;
  final String exercise;
  final double weightKg;
  final int reps;
}

/// Единый интерфейс: реализации — GymManeDbRepository (нативный модуль) и CsvWorkoutRepository.
abstract class WorkoutRepository {
  Future<List<WorkoutSet>> setsSince(DateTime since);
}

class MuscleLoad {
  const MuscleLoad({required this.primary, this.secondary = const []});
  final List<MuscleGroup> primary;
  final List<MuscleGroup> secondary;
}

class ExerciseCatalog {
  const ExerciseCatalog();

  static const _rules = <String, MuscleLoad>{
    'bench': MuscleLoad(primary: [MuscleGroup.chest], secondary: [MuscleGroup.triceps, MuscleGroup.shoulders]),
    'жим лёжа': MuscleLoad(primary: [MuscleGroup.chest], secondary: [MuscleGroup.triceps, MuscleGroup.shoulders]),
    'squat': MuscleLoad(primary: [MuscleGroup.quads, MuscleGroup.glutes], secondary: [MuscleGroup.hamstrings, MuscleGroup.lowerBack]),
    'присед': MuscleLoad(primary: [MuscleGroup.quads, MuscleGroup.glutes], secondary: [MuscleGroup.hamstrings, MuscleGroup.lowerBack]),
    'deadlift': MuscleLoad(primary: [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.lowerBack], secondary: [MuscleGroup.traps, MuscleGroup.forearms, MuscleGroup.lats]),
    'становая': MuscleLoad(primary: [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.lowerBack], secondary: [MuscleGroup.traps, MuscleGroup.forearms, MuscleGroup.lats]),
    'row': MuscleLoad(primary: [MuscleGroup.upperBack, MuscleGroup.lats], secondary: [MuscleGroup.biceps]),
    'тяга': MuscleLoad(primary: [MuscleGroup.upperBack, MuscleGroup.lats], secondary: [MuscleGroup.biceps]),
    'pull': MuscleLoad(primary: [MuscleGroup.lats], secondary: [MuscleGroup.biceps, MuscleGroup.upperBack]),
    'подтягив': MuscleLoad(primary: [MuscleGroup.lats], secondary: [MuscleGroup.biceps, MuscleGroup.upperBack]),
    'overhead': MuscleLoad(primary: [MuscleGroup.shoulders], secondary: [MuscleGroup.triceps]),
    'жим стоя': MuscleLoad(primary: [MuscleGroup.shoulders], secondary: [MuscleGroup.triceps]),
    'curl': MuscleLoad(primary: [MuscleGroup.biceps], secondary: [MuscleGroup.forearms]),
    'бицепс': MuscleLoad(primary: [MuscleGroup.biceps], secondary: [MuscleGroup.forearms]),
    'tricep': MuscleLoad(primary: [MuscleGroup.triceps]),
    'трицепс': MuscleLoad(primary: [MuscleGroup.triceps]),
    'calf': MuscleLoad(primary: [MuscleGroup.calves]),
    'икр': MuscleLoad(primary: [MuscleGroup.calves]),
    'crunch': MuscleLoad(primary: [MuscleGroup.abs], secondary: [MuscleGroup.obliques]),
    'пресс': MuscleLoad(primary: [MuscleGroup.abs], secondary: [MuscleGroup.obliques]),
  };

  MuscleLoad? lookup(String exercise) {
    final e = exercise.toLowerCase();
    for (final entry in _rules.entries) {
      if (e.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

class VolumeCalculator {
  VolumeCalculator({this.catalog = const ExerciseCatalog(), this.bodyweightKg = 80, this.secondaryFactor = 0.4});
  final ExerciseCatalog catalog;
  final double bodyweightKg;
  final double secondaryFactor;

  List<MuscleStimulus> toStimuli(List<WorkoutSet> sets) {
    // Агрегируем по (мышца, тренировочный день), чтобы одна сессия = один стимул.
    final acc = <String, ({MuscleGroup m, DateTime at, double v})>{};
    for (final s in sets) {
      final load = catalog.lookup(s.exercise);
      if (load == null || s.reps <= 0) continue;
      final w = s.weightKg > 0 ? s.weightKg : bodyweightKg * 0.65; // свой вес
      final vol = w * s.reps;
      void add(MuscleGroup m, double k) {
        final key = '${m.name}|${s.at.year}-${s.at.month}-${s.at.day}';
        final prev = acc[key];
        final at = (prev == null || s.at.isAfter(prev.at)) ? s.at : prev.at; // время последнего подхода
        acc[key] = (m: m, at: at, v: (prev?.v ?? 0) + vol * k);
      }
      for (final m in load.primary) { add(m, 1.0); }
      for (final m in load.secondary) { add(m, secondaryFactor); }
    }
    return [for (final e in acc.values) MuscleStimulus(e.m, e.at, e.v)];
  }
}

/// Резервный импорт CSV-экспорта GymMane. Заголовки ищутся по алиасам —
/// сверьте с реальным экспортом и поправьте.
class CsvWorkoutParser {
  static const _date = ['date', 'дата', 'timestamp', 'time'];
  static const _ex = ['exercise', 'упражнение', 'exercise name', 'name'];
  static const _w = ['weight', 'вес', 'kg', 'weight_kg'];
  static const _r = ['reps', 'повторения', 'repetitions'];

  List<WorkoutSet> parse(String csv) {
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(csv.replaceAll('\r\n', '\n'));
    if (rows.length < 2) return const [];
    final header = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    int idx(List<String> aliases) => header.indexWhere(aliases.contains);
    final iD = idx(_date), iE = idx(_ex), iW = idx(_w), iR = idx(_r);
    if ([iD, iE, iW, iR].contains(-1)) {
      throw FormatException('CSV: не найдены колонки. Заголовок: $header');
    }
    final out = <WorkoutSet>[];
    for (final row in rows.skip(1)) {
      if (row.length <= [iD, iE, iW, iR].reduce((a, b) => a > b ? a : b)) continue;
      final at = DateTime.tryParse(row[iD].toString());
      final w = double.tryParse(row[iW].toString().replaceAll(',', '.')) ?? 0;
      final r = int.tryParse(row[iR].toString()) ?? 0;
      if (at == null || r <= 0) continue;
      out.add(WorkoutSet(at: at, exercise: row[iE].toString(), weightKg: w, reps: r));
    }
    return out;
  }
}

class CsvWorkoutRepository implements WorkoutRepository {
  CsvWorkoutRepository(this._load);
  final Future<String> Function() _load; // file_picker / path_provider
  @override
  Future<List<WorkoutSet>> setsSince(DateTime since) async =>
      CsvWorkoutParser().parse(await _load()).where((s) => !s.at.isBefore(since)).toList();
}
