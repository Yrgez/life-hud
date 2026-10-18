// lib/features/body/domain/recovery_model.dart
// Модель усталости / восстановления / суперкомпенсации мышечных групп.
import 'dart:math' as math;

enum MuscleGroup {
  chest, upperBack, lats, traps, shoulders, biceps, triceps, forearms,
  abs, obliques, lowerBack, glutes, quads, hamstrings, calves, adductors,
}

class MuscleProfile {
  const MuscleProfile({
    required this.halfLifeHours,
    required this.referenceVolume,
    required this.supercompWindowHours,
  });

  /// T½ — время, за которое усталость от стимула падает вдвое.
  final double halfLifeHours;

  /// V_ref (кг·повторы): объём, дающий усталость ≈63% (1 - e^-1).
  final double referenceVolume;

  /// Длина окна суперкомпенсации после полного восстановления.
  final double supercompWindowHours;
}

const _large = MuscleProfile(halfLifeHours: 20, referenceVolume: 6000, supercompWindowHours: 48);
const _medium = MuscleProfile(halfLifeHours: 16, referenceVolume: 3500, supercompWindowHours: 48);
const _small = MuscleProfile(halfLifeHours: 12, referenceVolume: 2000, supercompWindowHours: 36);

const Map<MuscleGroup, MuscleProfile> kMuscleProfiles = {
  MuscleGroup.chest: _large,
  MuscleGroup.upperBack: _large,
  MuscleGroup.lats: _large,
  MuscleGroup.quads: _large,
  MuscleGroup.hamstrings: _large,
  MuscleGroup.glutes: _large,
  MuscleGroup.lowerBack: _large,
  MuscleGroup.shoulders: _medium,
  MuscleGroup.traps: _medium,
  MuscleGroup.triceps: _medium,
  MuscleGroup.adductors: _medium,
  MuscleGroup.biceps: _small,
  MuscleGroup.forearms: _small,
  MuscleGroup.abs: _small,
  MuscleGroup.obliques: _small,
  MuscleGroup.calves: _small,
};

/// Один "удар" по мышце: объём = Σ(вес · повторы · коэффициент роли).
class MuscleStimulus {
  const MuscleStimulus(this.muscle, this.at, this.volume);
  final MuscleGroup muscle;
  final DateTime at;
  final double volume;
}

enum RecoveryPhase { untrained, fatigued, recovering, ready, supercompensated, detrained }

class MuscleState {
  const MuscleState({
    required this.muscle,
    required this.fatigue,
    required this.phase,
    this.lastStimulus,
    this.readyAt,
    this.supercompBoost = 0,
  });

  final MuscleGroup muscle;
  final double fatigue; // 0..1
  final RecoveryPhase phase;
  final DateTime? lastStimulus;
  final DateTime? readyAt;
  final double supercompBoost; // 0..1, колокол внутри окна

  double get recovery => 1 - fatigue;

  Duration? timeToReady(DateTime now) =>
      readyAt != null && readyAt!.isAfter(now) ? readyAt!.difference(now) : null;
}

/// Математика:
///   F0_i   = 1 - exp(-V_i / V_ref)                 (насыщающаяся усталость)
///   T½_i   = T½_base · (1 + 0.5·F0_i)              (тяжёлая сессия восстанавливается дольше)
///   f_i(t) = F0_i · 2^(-Δt / T½_i)                 (экспоненциальный спад)
///   F(t)   = 1 - Π(1 - f_i(t))                     (суммарная усталость, всегда ≤ 1)
///   R(t)   = 1 - F(t)                              (восстановленность)
///   ready  : F ≤ 0.10;  t_ready находится сканом по часам
///   суперкомпенсация: окно W после t_ready, бонус = exp(-((s - W/2)/(W/2))²), s = t - t_ready
///   detrained: нет стимула > 10 суток
class RecoveryEngine {
  const RecoveryEngine({
    this.readyFatigue = 0.10,
    this.fatiguedAbove = 0.60,
    this.detrainAfter = const Duration(days: 10),
    this.horizon = const Duration(hours: 240),
  });

  final double readyFatigue;
  final double fatiguedAbove;
  final Duration detrainAfter;
  final Duration horizon;

  double fatigueAt(MuscleGroup m, List<MuscleStimulus> stims, DateTime t) {
    final p = kMuscleProfiles[m]!;
    var keep = 1.0;
    for (final s in stims) {
      if (s.muscle != m || s.at.isAfter(t) || s.volume <= 0) continue;
      final f0 = 1 - math.exp(-s.volume / p.referenceVolume);
      final hl = p.halfLifeHours * (1 + 0.5 * f0);
      final dtH = t.difference(s.at).inMinutes / 60.0;
      final f = f0 * math.pow(2, -dtH / hl).toDouble();
      keep *= (1 - f);
    }
    return 1 - keep;
  }

  MuscleState evaluate(MuscleGroup m, List<MuscleStimulus> all, DateTime now) {
    final mine = all.where((s) => s.muscle == m && !s.at.isAfter(now)).toList();
    if (mine.isEmpty) {
      return MuscleState(muscle: m, fatigue: 0, phase: RecoveryPhase.untrained);
    }
    final p = kMuscleProfiles[m]!;
    final last = mine.map((s) => s.at).reduce((a, b) => a.isAfter(b) ? a : b);
    final fatigue = fatigueAt(m, mine, now);

    DateTime? readyAt;
    final end = now.add(horizon);
    for (var t = last; !t.isAfter(end); t = t.add(const Duration(hours: 1))) {
      if (fatigueAt(m, mine, t) <= readyFatigue) {
        readyAt = t;
        break;
      }
    }

    var phase = RecoveryPhase.ready;
    var boost = 0.0;
    if (now.difference(last) > detrainAfter) {
      phase = RecoveryPhase.detrained;
    } else if (fatigue > fatiguedAbove) {
      phase = RecoveryPhase.fatigued;
    } else if (fatigue > readyFatigue) {
      phase = RecoveryPhase.recovering;
    } else {
      final sinceH = now.difference(readyAt ?? now).inMinutes / 60.0;
      final w = p.supercompWindowHours;
      if (sinceH <= w) {
        phase = RecoveryPhase.supercompensated;
        boost = math.exp(-math.pow((sinceH - w / 2) / (w / 2), 2)).toDouble();
      }
    }

    return MuscleState(
      muscle: m, fatigue: fatigue, phase: phase,
      lastStimulus: last, readyAt: readyAt, supercompBoost: boost,
    );
  }

  Map<MuscleGroup, MuscleState> evaluateAll(List<MuscleStimulus> stims, DateTime now) => {
        for (final m in MuscleGroup.values) m: evaluate(m, stims, now),
      };
}
