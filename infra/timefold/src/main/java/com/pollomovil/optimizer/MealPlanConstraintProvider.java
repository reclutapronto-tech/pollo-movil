package com.pollomovil.optimizer;

import ai.timefold.solver.core.api.score.HardMediumSoftScore;
import ai.timefold.solver.core.api.score.stream.Constraint;
import ai.timefold.solver.core.api.score.stream.ConstraintFactory;
import ai.timefold.solver.core.api.score.stream.ConstraintProvider;
import ai.timefold.solver.core.api.score.stream.Joiners;

public class MealPlanConstraintProvider implements ConstraintProvider {
    @Override
    public Constraint[] defineConstraints(ConstraintFactory factory) {
        return new Constraint[] {
            mealMustFitShiftAndBreaks(factory),
            mealsMustNotOverlap(factory),
            preferMealNearShiftMidpoint(factory)
        };
    }

    private Constraint mealMustFitShiftAndBreaks(ConstraintFactory factory) {
        return factory.forEach(MealPlanWorker.class)
                .filter(worker -> !worker.isStartValid())
                .penalize(HardMediumSoftScore.ONE_HARD)
                .asConstraint("Meals fit inside published shifts and avoid break windows");
    }

    private Constraint mealsMustNotOverlap(ConstraintFactory factory) {
        return factory.forEachUniquePair(MealPlanWorker.class,
                        Joiners.lessThan(MealPlanWorker::getEmployeeId))
                .filter(MealPlanWorker::overlaps)
                .penalize(HardMediumSoftScore.ONE_HARD)
                .asConstraint("Stagger meals so only one employee is unavailable at a time");
    }

    private Constraint preferMealNearShiftMidpoint(ConstraintFactory factory) {
        return factory.forEach(MealPlanWorker.class)
                .penalize(HardMediumSoftScore.ONE_MEDIUM,
                        worker -> Math.abs(worker.getMealStartMinute() - worker.getPreferredMealStartMinute()))
                .asConstraint("Prefer meal times near each worker's shift midpoint when feasible");
    }
}
