// lib/features/hud/presentation/life_hud_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'grit_vault.dart';
import 'gym_bridge.dart';
import 'health_service.dart';
import 'recovery_model.dart';

// ───────────── Providers ─────────────
final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final gritRepoProvider = Provider((ref) => GritRepository(ref.watch(dbProvider)));
final healthServiceProvider = Provider((_) => HealthConnectService());

/// Подмените на GymManeDbRepository / CsvWorkoutRepository.
final workoutRepoProvider = Provider<WorkoutRepository>((_) => _DemoWorkoutRepository());

final biometricsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(healthServiceProvider).loadToday());

final activeGoalsProvider =
    StreamProvider.autoDispose((ref) => ref.watch(gritRepoProvider).watchActive());

final muscleStatesProvider = FutureProvider.autoDispose<Map<MuscleGroup, MuscleState>>((ref) async {
  final now = DateTime.now();
  final sets = await ref.watch(workoutRepoProvider).setsSince(now.subtract(const Duration(days: 21)));
  final stims = VolumeCalculator().toStimuli(sets);
  return const RecoveryEngine().evaluateAll(stims, now);
});

class _DemoWorkoutRepository implements WorkoutRepository {
  @override
  Future<List<WorkoutSet>> setsSince(DateTime since) async {
    final n = DateTime.now();
    return [
      for (var i = 0; i < 4; i++)
        WorkoutSet(at: n.subtract(const Duration(hours: 20)), exercise: 'Bench Press', weightKg: 80, reps: 8),
      for (var i = 0; i < 4; i++)
        WorkoutSet(at: n.subtract(const Duration(hours: 70)), exercise: 'Squat', weightKg: 100, reps: 6),
      for (var i = 0; i < 3; i++)
        WorkoutSet(at: n.subtract(const Duration(hours: 120)), exercise: 'Barbell Row', weightKg: 70, reps: 10),
    ];
  }
}

// ───────────── Screen ─────────────
class LifeHudScreen extends ConsumerStatefulWidget {
  const LifeHudScreen({super.key});
  @override
  ConsumerState<LifeHudScreen> createState() => _LifeHudScreenState();
}

class _LifeHudScreenState extends ConsumerState<LifeHudScreen> with WidgetsBindingObserver {
  bool _back = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      ref.invalidate(biometricsProvider);
      ref.invalidate(muscleStatesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muscles = ref.watch(muscleStatesProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const BiometricsBar(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Спереди')),
                ButtonSegment(value: true, label: Text('Сзади')),
              ],
              selected: {_back},
              onSelectionChanged: (s) => setState(() => _back = s.first),
            ),
          ),
          Expanded(
            child: muscles.when(
              data: (m) => BodyMap(states: m, back: _back, onTap: (s) => _showMuscle(context, s)),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
          const GoalsStrip(),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.anchor),
        label: const Text('Reality Check'),
        onPressed: () => _realityCheck(context),
      ),
    );
  }

  void _showMuscle(BuildContext ctx, MuscleState s) {
    final left = s.timeToReady(DateTime.now());
    showModalBottomSheet(
      context: ctx,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.muscle.name.toUpperCase(), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Восстановлено: ${(s.recovery * 100).round()}%'),
          Text('Фаза: ${s.phase.name}'),
          if (left != null) Text('Готова через: ${left.inHours} ч'),
          if (s.phase == RecoveryPhase.supercompensated)
            Text('Окно суперкомпенсации — пик ${(s.supercompBoost * 100).round()}%'),
        ]),
      ),
    );
  }

  Future<void> _realityCheck(BuildContext ctx, {int? exclude}) async {
    final v = await ref.read(gritRepoProvider).realityCheck(excludeId: exclude);
    if (!ctx.mounted) return;
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(v == null ? 'Пока пусто' : v.title),
        content: v == null
            ? const Text('Добавь первую победу в Grit Vault — она станет якорем.')
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _block('Было', v.startingState),
                  _block('Цена', v.cost),
                  _block('Броня', v.outcomeArmor),
                ]),
              ),
        actions: [
          if (v != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _realityCheck(ctx, exclude: v.id);
              },
              child: const Text('Ещё одну'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Я справлюсь')),
        ],
      ),
    );
  }

  Widget _block(String h, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
          Text(t),
        ]),
      );
}

// ───────────── Biometrics ─────────────
class BiometricsBar extends ConsumerWidget {
  const BiometricsBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(biometricsProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: res.when(
        loading: () => const Text('Samsung Health…'),
        error: (e, _) => Text('Ошибка: $e'),
        data: (r) {
          switch (r.status) {
            case HealthAccessStatus.granted:
              return Text(r.data!.format(), style: const TextStyle(fontWeight: FontWeight.w600));
            case HealthAccessStatus.unsupported:
              return const Text('Health Connect доступен только на Android');
            case HealthAccessStatus.error:
              return Text('Health: ${r.error}');
            default:
              return Row(children: [
                const Expanded(child: Text('Нет доступа к Health Connect')),
                TextButton(
                  onPressed: () async {
                    await ref.read(healthServiceProvider).requestAccess();
                    ref.invalidate(biometricsProvider);
                  },
                  child: const Text('Подключить'),
                ),
              ]);
          }
        },
      ),
    );
  }
}

// ───────────── Goals ─────────────
class GoalsStrip extends ConsumerWidget {
  const GoalsStrip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(activeGoalsProvider).valueOrNull ?? const <GoalProgress>[];
    return SizedBox(
      height: 96,
      child: goals.isEmpty
          ? const Center(child: Text('Нет активных целей'))
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: goals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final g = goals[i];
                return SizedBox(
                  width: 200,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        LinearProgressIndicator(value: g.ratio),
                        Text('${g.done}/${g.total} шагов', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ───────────── Body map ─────────────
/// Плейсхолдер на CustomPainter. Замените _front/_back на SVG-пути из GymMane
/// (flutter_svg / path_drawing: parseSvgPathData -> Path, fill по id мышцы).
const _front = <MuscleGroup, List<Rect>>{
  MuscleGroup.shoulders: [Rect.fromLTWH(.20, .17, .13, .07), Rect.fromLTWH(.67, .17, .13, .07)],
  MuscleGroup.chest: [Rect.fromLTWH(.34, .18, .32, .09)],
  MuscleGroup.biceps: [Rect.fromLTWH(.16, .26, .08, .12), Rect.fromLTWH(.76, .26, .08, .12)],
  MuscleGroup.forearms: [Rect.fromLTWH(.12, .39, .08, .13), Rect.fromLTWH(.80, .39, .08, .13)],
  MuscleGroup.abs: [Rect.fromLTWH(.40, .28, .20, .17)],
  MuscleGroup.obliques: [Rect.fromLTWH(.33, .30, .06, .14), Rect.fromLTWH(.61, .30, .06, .14)],
  MuscleGroup.quads: [Rect.fromLTWH(.30, .50, .17, .22), Rect.fromLTWH(.53, .50, .17, .22)],
  MuscleGroup.calves: [Rect.fromLTWH(.31, .76, .13, .18), Rect.fromLTWH(.56, .76, .13, .18)],
};
const _backR = <MuscleGroup, List<Rect>>{
  MuscleGroup.traps: [Rect.fromLTWH(.38, .15, .24, .08)],
  MuscleGroup.shoulders: [Rect.fromLTWH(.20, .17, .13, .07), Rect.fromLTWH(.67, .17, .13, .07)],
  MuscleGroup.upperBack: [Rect.fromLTWH(.36, .24, .28, .08)],
  MuscleGroup.lats: [Rect.fromLTWH(.30, .32, .14, .12), Rect.fromLTWH(.56, .32, .14, .12)],
  MuscleGroup.triceps: [Rect.fromLTWH(.16, .26, .08, .12), Rect.fromLTWH(.76, .26, .08, .12)],
  MuscleGroup.lowerBack: [Rect.fromLTWH(.40, .45, .20, .07)],
  MuscleGroup.glutes: [Rect.fromLTWH(.32, .52, .36, .09)],
  MuscleGroup.hamstrings: [Rect.fromLTWH(.30, .62, .17, .16), Rect.fromLTWH(.53, .62, .17, .16)],
  MuscleGroup.calves: [Rect.fromLTWH(.31, .80, .13, .15), Rect.fromLTWH(.56, .80, .13, .15)],
};

Color muscleColor(MuscleState s) {
  switch (s.phase) {
    case RecoveryPhase.supercompensated:
      return Color.lerp(Colors.cyan.shade300, Colors.cyanAccent, s.supercompBoost)!;
    case RecoveryPhase.untrained:
    case RecoveryPhase.detrained:
      return Colors.blueGrey.shade600;
    default:
      final r = s.recovery.clamp(0.0, 1.0);
      return r < .5
          ? Color.lerp(Colors.redAccent, Colors.amber, r / .5)!
          : Color.lerp(Colors.amber, Colors.greenAccent.shade400, (r - .5) / .5)!;
  }
}

class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.states, required this.back, required this.onTap});
  final Map<MuscleGroup, MuscleState> states;
  final bool back;
  final void Function(MuscleState) onTap;

  Map<MuscleGroup, List<Rect>> get _regions => back ? _backR : _front;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 0.5,
        child: LayoutBuilder(builder: (_, c) {
          return GestureDetector(
            onTapUp: (d) {
              final p = Offset(d.localPosition.dx / c.maxWidth, d.localPosition.dy / c.maxHeight);
              for (final e in _regions.entries) {
                if (e.value.any((r) => r.inflate(.01).contains(p))) {
                  onTap(states[e.key]!);
                  return;
                }
              }
            },
            child: CustomPaint(size: Size(c.maxWidth, c.maxHeight), painter: _BodyPainter(states, _regions)),
          );
        }),
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter(this.states, this.regions);
  final Map<MuscleGroup, MuscleState> states;
  final Map<MuscleGroup, List<Rect>> regions;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawCircle(Offset(size.width * .5, size.height * .08), size.width * .08, outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .2, size.height * .15, size.width * .6, size.height * .82),
        const Radius.circular(24),
      ),
      outline,
    );
    for (final e in regions.entries) {
      final fill = Paint()..color = muscleColor(states[e.key]!);
      for (final r in e.value) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width, r.height * size.height),
            const Radius.circular(10),
          ),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.states != states || old.regions != regions;
}
