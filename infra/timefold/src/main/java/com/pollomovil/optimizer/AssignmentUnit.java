package com.pollomovil.optimizer;

import java.util.ArrayList;
import java.util.List;

import ai.timefold.solver.core.api.domain.common.PlanningId;
import ai.timefold.solver.core.api.domain.entity.PlanningEntity;
import ai.timefold.solver.core.api.domain.variable.PlanningVariable;

@PlanningEntity
public class AssignmentUnit {

    @PlanningId
    private String id;
    private String groupId;
    private List<String> requiredPositionIds = new ArrayList<>();
    private int estimatedMinutes;
    private int difficulty;
    private int priority;
    private boolean interruptible;
    private int loadBalanceWeight = 100;
    private int heavyRotationWeight = 60;
    private int priorityWeight = 100;

    @PlanningVariable(valueRangeProviderRefs = "employeeRange", allowsUnassigned = true)
    private AssignmentCandidate employee;

    public AssignmentUnit() {
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getGroupId() { return groupId; }
    public void setGroupId(String groupId) { this.groupId = groupId; }
    public List<String> getRequiredPositionIds() { return requiredPositionIds; }
    public void setRequiredPositionIds(List<String> requiredPositionIds) { this.requiredPositionIds = requiredPositionIds == null ? new ArrayList<>() : requiredPositionIds; }
    public int getEstimatedMinutes() { return estimatedMinutes; }
    public void setEstimatedMinutes(int estimatedMinutes) { this.estimatedMinutes = estimatedMinutes; }
    public int getDifficulty() { return difficulty; }
    public void setDifficulty(int difficulty) { this.difficulty = difficulty; }
    public int getPriority() { return priority; }
    public void setPriority(int priority) { this.priority = priority; }
    public boolean isInterruptible() { return interruptible; }
    public void setInterruptible(boolean interruptible) { this.interruptible = interruptible; }
    public int getLoadBalanceWeight() { return loadBalanceWeight; }
    public void setLoadBalanceWeight(int loadBalanceWeight) { this.loadBalanceWeight = loadBalanceWeight; }
    public int getHeavyRotationWeight() { return heavyRotationWeight; }
    public void setHeavyRotationWeight(int heavyRotationWeight) { this.heavyRotationWeight = heavyRotationWeight; }
    public int getPriorityWeight() { return priorityWeight; }
    public void setPriorityWeight(int priorityWeight) { this.priorityWeight = priorityWeight; }
    public AssignmentCandidate getEmployee() { return employee; }
    public void setEmployee(AssignmentCandidate employee) { this.employee = employee; }

    public long getWeightedMinutes() {
        return (long) estimatedMinutes * Math.max(1, difficulty);
    }
}
