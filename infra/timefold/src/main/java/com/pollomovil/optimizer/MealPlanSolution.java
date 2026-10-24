package com.pollomovil.optimizer;

import java.util.ArrayList;
import java.util.List;

import ai.timefold.solver.core.api.domain.solution.PlanningEntityCollectionProperty;
import ai.timefold.solver.core.api.domain.solution.PlanningScore;
import ai.timefold.solver.core.api.domain.solution.PlanningSolution;
import ai.timefold.solver.core.api.domain.valuerange.ValueRangeProvider;
import ai.timefold.solver.core.api.score.HardMediumSoftScore;

@PlanningSolution
public class MealPlanSolution {
    @PlanningEntityCollectionProperty
    private List<MealPlanWorker> workers = new ArrayList<>();

    @ValueRangeProvider(id = "mealStartRange")
    private List<Integer> mealStartRange = new ArrayList<>();

    @PlanningScore
    private HardMediumSoftScore score;

    public MealPlanSolution() { }
    public List<MealPlanWorker> getWorkers() { return workers; }
    public void setWorkers(List<MealPlanWorker> workers) { this.workers = workers == null ? new ArrayList<>() : workers; }
    public List<Integer> getMealStartRange() { return mealStartRange; }
    public void setMealStartRange(List<Integer> mealStartRange) { this.mealStartRange = mealStartRange == null ? new ArrayList<>() : mealStartRange; }
    public HardMediumSoftScore getScore() { return score; }
    public void setScore(HardMediumSoftScore score) { this.score = score; }
}
