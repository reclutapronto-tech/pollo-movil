package com.pollomovil.optimizer;

import java.util.ArrayList;
import java.util.List;

import ai.timefold.solver.core.api.domain.solution.PlanningEntityCollectionProperty;
import ai.timefold.solver.core.api.domain.solution.PlanningScore;
import ai.timefold.solver.core.api.domain.solution.PlanningSolution;
import ai.timefold.solver.core.api.domain.solution.ProblemFactCollectionProperty;
import ai.timefold.solver.core.api.domain.valuerange.ValueRangeProvider;
import ai.timefold.solver.core.api.score.HardMediumSoftScore;

@PlanningSolution
public class AssignmentProblem {

    @ProblemFactCollectionProperty
    @ValueRangeProvider(id = "employeeRange")
    private List<AssignmentCandidate> candidates = new ArrayList<>();

    @PlanningEntityCollectionProperty
    private List<AssignmentUnit> units = new ArrayList<>();

    private AssignmentWeights weights = new AssignmentWeights();

    @PlanningScore
    private HardMediumSoftScore score;

    public AssignmentProblem() {
    }

    public AssignmentProblem(List<AssignmentCandidate> candidates, List<AssignmentUnit> units) {
        this.candidates = candidates == null ? new ArrayList<>() : candidates;
        this.units = units == null ? new ArrayList<>() : units;
    }

    public List<AssignmentCandidate> getCandidates() { return candidates; }
    public void setCandidates(List<AssignmentCandidate> candidates) { this.candidates = candidates; }
    public List<AssignmentUnit> getUnits() { return units; }
    public void setUnits(List<AssignmentUnit> units) { this.units = units; }
    public AssignmentWeights getWeights() { return weights; }
    public void setWeights(AssignmentWeights weights) { this.weights = weights == null ? new AssignmentWeights() : weights; }
    public HardMediumSoftScore getScore() { return score; }
    public void setScore(HardMediumSoftScore score) { this.score = score; }
}
