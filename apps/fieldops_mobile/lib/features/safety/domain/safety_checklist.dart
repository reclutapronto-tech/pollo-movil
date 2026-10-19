/// Pre-shift safety sign-off checklist.
/// Workers confirm safety items before starting work.
/// Creates audit trail for regulatory compliance.
class SafetyQuestion {
  const SafetyQuestion({
    required this.id,
    required this.question,
    this.required = true,
  });

  final String id;
  final String question;
  final bool required;
}

class SafetyChecklistResponse {
  const SafetyChecklistResponse({
    required this.questionId,
    required this.answer,
    required this.answeredAt,
  });

  final String questionId;
  final bool answer; // true = confirmed, false = flagged
  final DateTime answeredAt;
}

/// Default pre-shift safety questions.
const defaultSafetyQuestions = [
  SafetyQuestion(
    id: 'ppe_worn',
    question: 'Are you wearing all required PPE (hard hat, vest, gloves, boots)?',
  ),
  SafetyQuestion(
    id: 'site_hazards',
    question: 'Have you identified any new hazards at the job site?',
  ),
  SafetyQuestion(
    id: 'equipment_checked',
    question: 'Have you inspected your tools and equipment before use?',
  ),
  SafetyQuestion(
    id: 'fit_for_duty',
    question: 'Are you fit for duty (rested, not impaired, no injuries)?',
  ),
  SafetyQuestion(
    id: 'emergency_plan',
    question: 'Do you know the emergency plan and muster point for this site?',
  ),
];
