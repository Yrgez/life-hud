// lib/features/biometrics/data/health_service.dart
// Samsung Health -> Health Connect -> приложение.
// Пакет: health (проверено на API 11.x–12.x; после апгрейда сверьте сигнатуры).
import 'dart:io';
import 'package:health/health.dart';

enum HealthAccessStatus { granted, denied, notInstalled, unsupported, error }

class DailyBiometrics {
  const DailyBiometrics({required this.caloriesIn, required this.caloriesOut, required this.steps});
  final double caloriesIn;
  final double caloriesOut;
  final int steps;

  /// Наедено: XXXX ккал (Сожжено: YYYY ккал) | Шаги: ZZ ZZZ
  String format() =>
      'Наедено: ${_fmt(caloriesIn)} ккал (Сожжено: ${_fmt(caloriesOut)} ккал) | Шаги: ${_fmt(steps)}';

  static String _fmt(num n) => n
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u00A0');
}

class BiometricsResult {
  const BiometricsResult(this.status, {this.data, this.error});
  final HealthAccessStatus status;
  final DailyBiometrics? data;
  final String? error;
}

class HealthConnectService {
  HealthConnectService({Health? health}) : _health = health ?? Health();
  final Health _health;
  bool _configured = false;

  static const _types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.NUTRITION,
  ];
  static const _perms = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Проверка SDK + прав + чтение. Безопасно вызывать при каждом resume.
  Future<BiometricsResult> loadToday() async {
    if (!Platform.isAndroid) return const BiometricsResult(HealthAccessStatus.unsupported);
    try {
      await _ensureConfigured();
      final sdk = await _health.getHealthConnectSdkStatus();
      if (sdk != HealthConnectSdkStatus.sdkAvailable) {
        return const BiometricsResult(HealthAccessStatus.notInstalled);
      }
      final granted = await _health.hasPermissions(_types, permissions: _perms) ?? false;
      if (!granted) return const BiometricsResult(HealthAccessStatus.denied);
      return BiometricsResult(HealthAccessStatus.granted, data: await _readToday());
    } catch (e) {
      return BiometricsResult(HealthAccessStatus.error, error: e.toString());
    }
  }

  /// Вызывать по нажатию кнопки "Подключить" (нужен Activity).
  Future<bool> requestAccess() async {
    await _ensureConfigured();
    final sdk = await _health.getHealthConnectSdkStatus();
    if (sdk != HealthConnectSdkStatus.sdkAvailable) {
      await _health.installHealthConnect();
      return false;
    }
    return _health.requestAuthorization(_types, permissions: _perms);
  }

  Future<DailyBiometrics> _readToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    // Шаги: агрегат Health Connect — сам дедуплицирует источники.
    final steps = await _health.getTotalStepsInInterval(start, now) ?? 0;

    final raw = await _health.getHealthDataFromTypes(
      types: const [
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.TOTAL_CALORIES_BURNED,
        HealthDataType.NUTRITION,
      ],
      startTime: start,
      endTime: now,
    );
    final points = _health.removeDuplicates(raw);

    double active = 0, total = 0, eaten = 0;
    for (final p in points) {
      final v = p.value;
      switch (p.type) {
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          if (v is NumericHealthValue) active += v.numericValue.toDouble();
        case HealthDataType.TOTAL_CALORIES_BURNED:
          if (v is NumericHealthValue) total += v.numericValue.toDouble();
        case HealthDataType.NUTRITION:
          if (v is NutritionHealthValue) eaten += v.calories ?? 0;
        default:
          break;
      }
    }

    // "Сожжено" = полный расход (BMR + активность); если источник его не пишет — активные.
    final burned = total > active ? total : active;
    return DailyBiometrics(caloriesIn: eaten, caloriesOut: burned, steps: steps);
  }
}
