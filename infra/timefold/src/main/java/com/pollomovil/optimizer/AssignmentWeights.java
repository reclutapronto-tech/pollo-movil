package com.pollomovil.optimizer;

public class AssignmentWeights {

    private int loadBalanceWeight = 100;
    private int heavyRotationWeight = 60;
    private int priorityWeight = 100;

    public AssignmentWeights() {
    }

    public int getLoadBalanceWeight() { return loadBalanceWeight; }
    public void setLoadBalanceWeight(int loadBalanceWeight) { this.loadBalanceWeight = loadBalanceWeight; }
    public int getHeavyRotationWeight() { return heavyRotationWeight; }
    public void setHeavyRotationWeight(int heavyRotationWeight) { this.heavyRotationWeight = heavyRotationWeight; }
    public int getPriorityWeight() { return priorityWeight; }
    public void setPriorityWeight(int priorityWeight) { this.priorityWeight = priorityWeight; }
}
