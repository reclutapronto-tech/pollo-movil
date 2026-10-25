package com.pollomovil.optimizer;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import ai.timefold.solver.core.api.domain.common.PlanningId;

public class AssignmentCandidate {

    @PlanningId
    private String id;
    private List<String> positionIds = new ArrayList<>();
    private boolean onShift;
    private boolean onBreak;
    private boolean absent;
    private boolean servingCustomers;
    private int capacityMinutes;
    private long assignedWeightedMinutes;
    private int recentHeavyTasks;
    private int rotationRank;

    public AssignmentCandidate() {
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public List<String> getPositionIds() { return positionIds; }
    public void setPositionIds(List<String> positionIds) { this.positionIds = positionIds == null ? new ArrayList<>() : positionIds; }
    public boolean isOnShift() { return onShift; }
    public void setOnShift(boolean onShift) { this.onShift = onShift; }
    public boolean isOnBreak() { return onBreak; }
    public void setOnBreak(boolean onBreak) { this.onBreak = onBreak; }
    public boolean isAbsent() { return absent; }
    public void setAbsent(boolean absent) { this.absent = absent; }
    public boolean isServingCustomers() { return servingCustomers; }
    public void setServingCustomers(boolean servingCustomers) { this.servingCustomers = servingCustomers; }
    public int getCapacityMinutes() { return capacityMinutes; }
    public void setCapacityMinutes(int capacityMinutes) { this.capacityMinutes = capacityMinutes; }
    public long getAssignedWeightedMinutes() { return assignedWeightedMinutes; }
    public void setAssignedWeightedMinutes(long assignedWeightedMinutes) { this.assignedWeightedMinutes = assignedWeightedMinutes; }
    public int getRecentHeavyTasks() { return recentHeavyTasks; }
    public void setRecentHeavyTasks(int recentHeavyTasks) { this.recentHeavyTasks = recentHeavyTasks; }
    public int getRotationRank() { return rotationRank; }
    public void setRotationRank(int rotationRank) { this.rotationRank = rotationRank; }

    public boolean isEligibleFor(AssignmentUnit unit) {
        if (!onShift || onBreak || absent || capacityMinutes < unit.getEstimatedMinutes()) return false;
        if (unit.getRequiredPositionIds() == null || unit.getRequiredPositionIds().isEmpty()) return false;
        if (positionIds.stream().noneMatch(unit.getRequiredPositionIds()::contains)) return false;
        return !unit.isInterruptible() || !servingCustomers;
    }

    @Override
    public boolean equals(Object other) {
        return this == other || other instanceof AssignmentCandidate candidate && Objects.equals(id, candidate.id);
    }

    @Override
    public int hashCode() { return Objects.hashCode(id); }
}
