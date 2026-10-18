// Карта тела на векторах GymMane (body_svg.dart) + наша модель восстановления.
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import 'body_svg.dart';
import 'recovery_model.dart';

final Map<String, Path> _pathCache = {};
Path svgPath(String d) => _pathCache.putIfAbsent(d, () => parseSvgPathData(d));

/// id мышцы в body_svg.dart -> наши группы.
const Map<String, List<MuscleGroup>> kGymIdToGroups = {
  'chest': [MuscleGroup.chest],
  'back': [MuscleGroup.upperBack, MuscleGroup.lats],
  'trapezius': [MuscleGroup.traps],
  'shoulders': [MuscleGroup.shoulders],
  'biceps': [MuscleGroup.biceps],
  'triceps': [MuscleGroup.triceps],
  'forearm': [MuscleGroup.forearms],
  'abdomen': [MuscleGroup.abs],
  'obliques': [MuscleGroup.obliques],
  'lowerback': [MuscleGroup.lowerBack],
  'glutes': [MuscleGroup.glutes],
  'quads': [MuscleGroup.quads, MuscleGroup.adductors],
  'hamstrings': [MuscleGroup.hamstrings],
  'calves': [MuscleGroup.calves],
};

/// Если на один контур приходится несколько групп — показываем самую уставшую.
MuscleState worstState(Map<MuscleGroup, MuscleState> s, List<MuscleGroup> gs) {
  var best = s[gs.first]!;
  for (final g in gs.skip(1)) {
    final c = s[g]!;
    if (best.phase == RecoveryPhase.untrained && c.phase != RecoveryPhase.untrained) {
      best = c;
    } else if (c.phase != RecoveryPhase.untrained && c.fatigue > best.fatigue) {
      best = c;
    }
  }
  return best;
}

Color muscleColor(MuscleState s) {
  switch (s.phase) {
    case RecoveryPhase.supercompensated:
      return Color.lerp(Colors.cyan.shade300, Colors.cyanAccent, s.supercompBoost)!;
    case RecoveryPhase.untrained:
    case RecoveryPhase.detrained:
      return const Color(0xFF4A5056);
    default:
      final r = s.recovery.clamp(0.0, 1.0);
      return r < .5
          ? Color.lerp(Colors.redAccent, Colors.amber, r / .5)!
          : Color.lerp(Colors.amber, Colors.greenAccent.shade400, (r - .5) / .5)!;
  }
}

String? muscleAt(Offset p) {
  for (final id in muscleFills.keys) {
    final hits = muscleHits[id];
    final probes = (hits != null && hits.isNotEmpty) ? hits : muscleFills[id]!;
    for (final d in probes) {
      if (svgPath(d).contains(p)) return id;
    }
  }
  return null;
}

class BodyView extends StatelessWidget {
  const BodyView({super.key, required this.states, required this.onTap});
  final Map<MuscleGroup, MuscleState> states;
  final void Function(MuscleState) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = {
      for (final e in kGymIdToGroups.entries) e.key: muscleColor(worstState(states, e.value)),
    };
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final scale = w / bodyViewW;
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final id = muscleAt(Offset(d.localPosition.dx / scale, d.localPosition.dy / scale));
            final groups = id == null ? null : kGymIdToGroups[id];
            if (groups != null) onTap(worstState(states, groups));
          },
          child: CustomPaint(
            size: Size(w, w * bodyViewH / bodyViewW),
            painter: _BodyPainter(colors),
          ),
        ),
      );
    });
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter(this.colors);
  final Map<String, Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / bodyViewW);
    void fill(String d, Color c) => canvas.drawPath(
        svgPath(d), Paint()..color = c..style = PaintingStyle.fill..isAntiAlias = true);
    for (final d in bodyBaseMain) { fill(d, const Color(0xFF23282C)); }
    for (final d in bodyBaseLite) { fill(d, const Color(0xFF2C3237)); }
    for (final e in muscleFills.entries) {
      final c = colors[e.key] ?? const Color(0xFF4A5056);
      for (final d in e.value) { fill(d, c); }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => true;
}
