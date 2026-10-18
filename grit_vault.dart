// lib/features/grit/data/grit_vault.dart
// Grit Vault: цели -> шаги -> победы с контекстом преодоления. Drift (SQLite).
// Генерация: dart run build_runner build
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'grit_vault.g.dart';

class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get why => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class GoalSteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goalId => integer().references(Goals, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();
}

/// Победа = контекст: Исходное состояние/страх -> Цена -> Итог и броня опыта.
class Victories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goalId => integer().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text()();
  TextColumn get startingState => text()(); // страх / исходное состояние
  TextColumn get cost => text()(); // через какую боль и трудности прошёл
  TextColumn get outcomeArmor => text()(); // итог и "броня опыта"
  IntColumn get difficulty => integer().withDefault(const Constant(3))(); // 1..5
  DateTimeColumn get achievedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Goals, GoalSteps, Victories])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'life_hud'));
  @override
  int get schemaVersion => 1;
}

class GoalProgress {
  const GoalProgress(this.id, this.title, this.total, this.done);
  final int id;
  final String title;
  final int total;
  final int done;
  double get ratio => total == 0 ? 0 : done / total;
}

class GritRepository {
  GritRepository(this.db);
  final AppDatabase db;
  final _rng = math.Random();

  Future<int> addGoal(String title, {String? why, List<String> steps = const []}) =>
      db.transaction(() async {
        final id = await db.into(db.goals).insert(
            GoalsCompanion.insert(title: title, why: Value(why)));
        for (var i = 0; i < steps.length; i++) {
          await db.into(db.goalSteps).insert(
              GoalStepsCompanion.insert(goalId: id, title: steps[i], position: Value(i)));
        }
        return id;
      });

  Future<void> setStepDone(int stepId, bool done) =>
      (db.update(db.goalSteps)..where((t) => t.id.equals(stepId))).write(
        GoalStepsCompanion(done: Value(done), doneAt: Value(done ? DateTime.now() : null)),
      );

  Future<int> recordVictory({
    int? goalId,
    required String title,
    required String startingState,
    required String cost,
    required String outcomeArmor,
    int difficulty = 3,
  }) =>
      db.into(db.victories).insert(VictoriesCompanion.insert(
            title: title,
            startingState: startingState,
            cost: cost,
            outcomeArmor: outcomeArmor,
            goalId: Value(goalId),
            difficulty: Value(difficulty.clamp(1, 5)),
          ));

  Stream<List<GoalProgress>> watchActive() {
    final q = db.customSelect(
      'SELECT g.id AS id, g.title AS title, COUNT(s.id) AS total, '
      'COALESCE(SUM(s.done), 0) AS done '
      'FROM goals g LEFT JOIN goal_steps s ON s.goal_id = g.id '
      'WHERE g.completed_at IS NULL GROUP BY g.id ORDER BY g.created_at DESC',
      readsFrom: {db.goals, db.goalSteps},
    );
    return q.watch().map((rows) => [
          for (final r in rows)
            GoalProgress(r.read<int>('id'), r.read<String>('title'),
                r.read<int>('total'), r.read<int>('done')),
        ]);
  }

  /// Reality Check: случайная победа, вес ~ difficulty² (тяжёлые выпадают чаще),
  /// без повтора предыдущей.
  Future<Victory?> realityCheck({int? excludeId}) async {
    var all = await db.select(db.victories).get();
    if (excludeId != null && all.length > 1) {
      all = all.where((v) => v.id != excludeId).toList();
    }
    if (all.isEmpty) return null;
    final weights = [for (final v in all) (v.difficulty * v.difficulty).toDouble()];
    var roll = _rng.nextDouble() * weights.reduce((a, b) => a + b);
    for (var i = 0; i < all.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return all[i];
    }
    return all.last;
  }
}
