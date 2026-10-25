package com.pollomovil.optimizer;

import java.util.ArrayList;
import java.util.List;

import ai.timefold.solver.core.api.domain.common.PlanningId;
import ai.timefold.solver.core.api.domain.entity.PlanningEntity;
import ai.timefold.solver.core.api.domain.variable.PlanningVariable;

@PlanningEntity
public class MealPlanWorker {
    @PlanningId
    private String employeeId;
    private int shiftStartMinute;
    private int shiftEndMinute;
    private int mealDurationMinutes;
    private int preferredMealStartMinute;
    private List<Integer> blockedStartMinutes = new ArrayList<>();

    @PlanningVariable(valueRangeProviderRefs = "mealStartRange")
    private Integer mealStartMinute;

    public MealPlanWorker() { }
    public String getEmployeeId() { return employeeId; }
    public void setEmployeeId(String employeeId) { this.employeeId = employeeId; }
    public int getShiftStartMinute() { return shiftStartMinute; }
    public void setShiftStartMinute(int shiftStartMinute) { this.shiftStartMinute = shiftStartMinute; }
    public int getShiftEndMinute() { return shiftEndMinute; }
    public void setShiftEndMinute(int shiftEndMinute) { this.shiftEndMinute = shiftEndMinute; }
    public int getMealDurationMinutes() { return mealDurationMinutes; }
    public void setMealDurationMinutes(int mealDurationMinutes) { this.mealDurationMinutes = mealDurationMinutes; }
    public int getPreferredMealStartMinute() { return preferredMealStartMinute; }
    public void setPreferredMealStartMinute(int preferredMealStartMinute) { this.preferredMealStartMinute = preferredMealStartMinute; }
    public List<Integer> getBlockedStartMinutes() { return blockedStartMinutes; }
    public void setBlockedStartMinutes(List<Integer> blockedStartMinutes) {
        this.blockedStartMinutes = blockedStartMinutes == null ? new ArrayList<>() : blockedStartMinutes;
    }
    public Integer getMealStartMinute() { return mealStartMinute; }
    public void setMealStartMinute(Integer mealStartMinute) { this.mealStartMinute = mealStartMinute; }
    public boolean isStartValid() {
        return mealStartMinute != null && mealStartMinute >= shiftStartMinute
                && mealStartMinute + mealDurationMinutes <= shiftEndMinute
                && !blockedStartMinutes.contains(mealStartMinute);
    }
    public boolean overlaps(MealPlanWorker other) {
        return mealStartMinute != null && other.mealStartMinute != null
                && mealStartMinute < other.mealStartMinute + other.mealDurationMinutes
                && other.mealStartMinute < mealStartMinute + mealDurationMinutes;
    }
}
