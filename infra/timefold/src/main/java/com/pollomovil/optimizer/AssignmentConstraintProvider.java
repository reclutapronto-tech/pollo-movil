package com.pollomovil.optimizer;

import ai.timefold.solver.core.api.score.HardMediumSoftScore;
import ai.timefold.solver.core.api.score.stream.Constraint;
import ai.timefold.solver.core.api.score.stream.ConstraintCollectors;
import ai.timefold.solver.core.api.score.stream.ConstraintFactory;
import ai.timefold.solver.core.api.score.stream.ConstraintProvider;
import ai.timefold.solver.core.api.score.stream.Joiners;

public class AssignmentConstraintProvider implements ConstraintProvider {

    @Override
    public Constraint[] defineConstraints(ConstraintFactory factory) {
        return new Constraint[] {
                rejectIneligibleAssignments(factory),
                respectRemainingCapacity(factory),
                separateDividedTaskParts(factory),
                minimizeUnassignedUnits(factory),
                balanceWeightedWorkload(factory),
                balanceTaskPairs(factory),
                rotateHeavyTaskPairs(factory),
                rotateHeavyTasks(factory)
        };
    }

    private Constraint rejectIneligibleAssignments(ConstraintFactory factory) {
        return factory.forEach(AssignmentUnit.class)
                .filter(unit -> unit.getEmployee() != null && !unit.getEmployee().isEligibleFor(unit))
                .penalize(HardMediumSoftScore.ONE_HARD)
                .asConstraint("Only eligible on-shift employees receive tasks");
    }

    private Constraint respectRemainingCapacity(ConstraintFactory factory) {
        return factory.forEach(AssignmentUnit.class)
                .groupBy(AssignmentUnit::getEmployee,
                        ConstraintCollectors.sum(unit -> (long) unit.getEstimatedMinutes()))
                .filter((employee, assignedMinutes) -> assignedMinutes > employee.getCapacityMinutes())
                .penalize(HardMediumSoftScore.ONE_HARD,
                        (employee, assignedMinutes) -> (int) Math.min(Integer.MAX_VALUE,
                                assignedMinutes - employee.getCapacityMinutes()))
                .asConstraint("Do not exceed remaining shift capacity");
    }

    private Constraint separateDividedTaskParts(ConstraintFactory factory) {
        return factory.forEachUniquePair(AssignmentUnit.class,
                        Joiners.equal(AssignmentUnit::getEmployee),
                        Joiners.equal(AssignmentUnit::getGroupId))
                .filter((left, right) -> left.getEmployee() != null)
                .penalize(HardMediumSoftScore.ONE_HARD)
                .asConstraint("A divided task has at most one part per employee");
    }

    private Constraint minimizeUnassignedUnits(ConstraintFactory factory) {
        return factory.forEachIncludingUnassigned(AssignmentUnit.class)
                .filter(unit -> unit.getEmployee() == null)
                .penalize(HardMediumSoftScore.ONE_MEDIUM,
                        unit -> 100 + Math.max(1, unit.getPriority()) * unit.getPriorityWeight())
                .asConstraint("Assign as many eligible tasks as capacity allows");
    }

    private Constraint balanceWeightedWorkload(ConstraintFactory factory) {
        return factory.forEach(AssignmentUnit.class)
                .penalize(HardMediumSoftScore.ONE_SOFT, unit -> {
                    AssignmentCandidate employee = unit.getEmployee();
                    int capacity = Math.max(1, employee.getCapacityMinutes());
                    double projected = (double) employee.getAssignedWeightedMinutes()
                            + unit.getWeightedMinutes();
                    double workloadCost = projected * unit.getLoadBalanceWeight() * 10d / capacity;
                    return cappedSoftPenalty(workloadCost + Math.max(0, employee.getRotationRank()));
                })
                .asConstraint("Distribute weighted workload fairly");
    }

    private Constraint balanceTaskPairs(ConstraintFactory factory) {
        return factory.forEachUniquePair(AssignmentUnit.class,
                        Joiners.equal(AssignmentUnit::getEmployee))
                .filter((left, right) -> left.getEmployee() != null)
                .penalize(HardMediumSoftScore.ONE_SOFT, (left, right) -> {
                    int capacity = Math.max(1, left.getEmployee().getCapacityMinutes());
                    double combinedWeight = (double) left.getWeightedMinutes()
                            + right.getWeightedMinutes();
                    double cost = combinedWeight * left.getLoadBalanceWeight() * 10d / capacity;
                    return cappedSoftPenalty(cost);
                })
                .asConstraint("Avoid concentrating multiple activities on one employee");
    }

    private Constraint rotateHeavyTaskPairs(ConstraintFactory factory) {
        return factory.forEachUniquePair(AssignmentUnit.class,
                        Joiners.equal(AssignmentUnit::getEmployee))
                .filter((left, right) -> left.getEmployee() != null
                        && left.getDifficulty() >= 4 && right.getDifficulty() >= 4)
                .penalize(HardMediumSoftScore.ONE_SOFT, (left, right) -> {
                    int capacity = Math.max(1, left.getEmployee().getCapacityMinutes());
                    return (int) ((long) left.getHeavyRotationWeight() * 1_000L / capacity);
                })
                .asConstraint("Spread heavy activities within the daily plan");
    }

    private Constraint rotateHeavyTasks(ConstraintFactory factory) {
        return factory.forEach(AssignmentUnit.class)
                .filter(unit -> unit.getDifficulty() >= 4 && unit.getEmployee().getRecentHeavyTasks() > 0)
                .penalize(HardMediumSoftScore.ONE_SOFT,
                        unit -> cappedSoftPenalty(
                                (double) unit.getHeavyRotationWeight()
                                        * unit.getEmployee().getRecentHeavyTasks()
                                        * 1_000d
                                        / Math.max(1, unit.getEmployee().getCapacityMinutes())))
                .asConstraint("Rotate heavy work away from recent recipients");
    }

    private int cappedSoftPenalty(double value) {
        if (!Double.isFinite(value) || value >= 100_000d) return 100_000;
        if (value <= 0d) return 0;
        return (int) Math.round(value);
    }

}
