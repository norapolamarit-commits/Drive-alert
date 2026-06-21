class RiskResult {
  const RiskResult({
    required this.riskClass,
    required this.alertLevel,
    required this.detectedSigns,
    required this.recommendation,
  });

  final String riskClass;
  final String alertLevel;
  final List<String> detectedSigns;
  final String recommendation;

  bool get shouldStoreAlert => alertLevel != 'Safe' || riskClass != 'Normal';

  int get levelValue => switch (alertLevel) {
        'Safe' => 0,
        'Watch' => 1,
        'Warning' => 2,
        'Emergency' => 3,
        _ => 0,
      };

  Map<String, dynamic> toJson() => {
        'riskClass': riskClass,
        'alertLevel': alertLevel,
        'detectedSigns': detectedSigns,
        'recommendation': recommendation,
      };

  factory RiskResult.fromJson(Map<String, dynamic> json) => RiskResult(
        riskClass: json['riskClass']?.toString() ?? 'Normal',
        alertLevel: json['alertLevel']?.toString() ?? 'Safe',
        detectedSigns: (json['detectedSigns'] as List<dynamic>?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
        recommendation: json['recommendation']?.toString() ?? '',
      );
}
