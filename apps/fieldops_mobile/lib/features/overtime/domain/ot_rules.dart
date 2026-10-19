// Jurisdiction-specific overtime calculation rules.
// Federal (default): weekly OT at 40h
// California: daily OT >8h, double-time >12h, weekly >40h, 7th day rules
// Custom: configurable thresholds per company

/// OT jurisdiction options.
enum OTJurisdiction { federal, california, custom }

class OTRules {
  const OTRules({
    this.jurisdiction = OTJurisdiction.federal,
    this.dailyOTThresholdHours = 8,
    this.dailyDoubleTimeThresholdHours,
    this.weeklyOTThresholdHours = 40,
    this.seventhDayRule = false,
  });

  /// Federal: weekly OT only at 40h
  static const federal = OTRules(
    jurisdiction: OTJurisdiction.federal,
    weeklyOTThresholdHours: 40,
  );

  /// California: daily OT >8h, double-time >12h, weekly >40h, 7th consecutive day
  static const california = OTRules(
    jurisdiction: OTJurisdiction.california,
    dailyOTThresholdHours: 8,
    dailyDoubleTimeThresholdHours: 12,
    weeklyOTThresholdHours: 40,
    seventhDayRule: true,
  );

  final OTJurisdiction jurisdiction;
  final double dailyOTThresholdHours;
  final double? dailyDoubleTimeThresholdHours;
  final double weeklyOTThresholdHours;
  final bool seventhDayRule;

  /// Calculate OT breakdown for a given number of daily hours.
  ({double regular, double overtime, double doubleTime}) calculateDaily(
      double hoursWorked) {
    if (jurisdiction == OTJurisdiction.federal) {
      // Federal: no daily OT, only weekly
      return (regular: hoursWorked, overtime: 0, doubleTime: 0);
    }

    final dtThreshold = dailyDoubleTimeThresholdHours;

    if (dtThreshold != null && hoursWorked > dtThreshold) {
      return (
        regular: dailyOTThresholdHours,
        overtime: dtThreshold - dailyOTThresholdHours,
        doubleTime: hoursWorked - dtThreshold,
      );
    }

    if (hoursWorked > dailyOTThresholdHours) {
      return (
        regular: dailyOTThresholdHours,
        overtime: hoursWorked - dailyOTThresholdHours,
        doubleTime: 0,
      );
    }

    return (regular: hoursWorked, overtime: 0, doubleTime: 0);
  }

  /// Calculate weekly OT from total weekly hours (after daily OT already counted).
  double calculateWeeklyOT(double totalWeeklyRegularHours) {
    if (totalWeeklyRegularHours > weeklyOTThresholdHours) {
      return totalWeeklyRegularHours - weeklyOTThresholdHours;
    }
    return 0;
  }
}
