package com.pollomovil.optimizer;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutionException;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import ai.timefold.solver.core.api.solver.SolverJob;
import ai.timefold.solver.core.api.solver.SolverManager;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/assignments")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class AssignmentOptimizationResource {

    @Inject
    SolverManager<AssignmentProblem> solverManager;

    @ConfigProperty(name = "pollo.timefold.api-token", defaultValue = "")
    String apiToken;

    @GET
    @Path("/health")
    public Map<String, String> health() {
        return Map.of("service", "pollo-movil-timefold", "status", "ready");
    }

    @POST
    @Path("/solve")
    public Response solve(AssignmentProblem input, @HeaderParam("Authorization") String authorization) {
        if (!isAuthorized(authorization)) return Response.status(Response.Status.UNAUTHORIZED).build();
        if (!isValidInput(input)) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(Map.of("error", "The assignment request is malformed or exceeds service limits."))
                    .build();
        }
        if (input.getUnits().isEmpty()) {
            return Response.ok(Map.of("assignments", List.of(), "unassignedUnitIds", List.of(), "score", "0hard/0medium/0soft")).build();
        }
        if (input.getCandidates().isEmpty()) {
            return Response.ok(Map.of("assignments", List.of(),
                    "unassignedUnitIds", input.getUnits().stream().map(AssignmentUnit::getId).toList(),
                    "score", "0hard/0medium/0soft")).build();
        }

        AssignmentWeights weights = input.getWeights();
        for (AssignmentUnit unit : input.getUnits()) {
            unit.setLoadBalanceWeight(weights.getLoadBalanceWeight());
            unit.setHeavyRotationWeight(weights.getHeavyRotationWeight());
            unit.setPriorityWeight(weights.getPriorityWeight());
        }

        UUID problemId = UUID.randomUUID();
        SolverJob<AssignmentProblem> solverJob = solverManager.solve(problemId, input);
        final AssignmentProblem bestSolution;
        try {
            bestSolution = solverJob.getFinalBestSolution();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return Response.serverError().entity(Map.of("error", "Optimization was interrupted.")).build();
        } catch (ExecutionException exception) {
            return Response.serverError().entity(Map.of("error", "Optimization could not produce a solution.")).build();
        }

        List<Map<String, String>> assignments = new ArrayList<>();
        List<String> unassigned = new ArrayList<>();
        for (AssignmentUnit unit : bestSolution.getUnits()) {
            if (unit.getEmployee() == null) {
                unassigned.add(unit.getId());
            } else {
                assignments.add(Map.of("unitId", unit.getId(), "candidateId", unit.getEmployee().getId()));
            }
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("assignments", assignments);
        result.put("unassignedUnitIds", unassigned);
        result.put("score", bestSolution.getScore() == null ? null : bestSolution.getScore().toString());
        return Response.ok(result).build();
    }

    private boolean isAuthorized(String authorization) {
        // Never expose an unauthenticated optimization endpoint when local
        // configuration is incomplete. The caller has a safe local fallback.
        if (apiToken == null || apiToken.isBlank()) return false;
        if (authorization == null || !authorization.startsWith("Bearer ")) return false;
        byte[] expected = apiToken.getBytes(StandardCharsets.UTF_8);
        byte[] provided = authorization.substring("Bearer ".length()).getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, provided);
    }

    private boolean isValidInput(AssignmentProblem input) {
        if (input == null || input.getUnits() == null || input.getCandidates() == null
                || input.getUnits().size() > 500 || input.getCandidates().size() > 200) return false;
        AssignmentWeights weights = input.getWeights();
        if (weights == null || !validWeight(weights.getLoadBalanceWeight())
                || !validWeight(weights.getHeavyRotationWeight()) || !validWeight(weights.getPriorityWeight())) return false;

        Set<String> candidateIds = new HashSet<>();
        for (AssignmentCandidate candidate : input.getCandidates()) {
            if (candidate == null || candidate.getId() == null || candidate.getId().isBlank()
                    || !candidateIds.add(candidate.getId()) || candidate.getCapacityMinutes() < 0
                    || candidate.getAssignedWeightedMinutes() < 0 || candidate.getRecentHeavyTasks() < 0
                    || candidate.getRotationRank() < 0
                    || candidate.getPositionIds() == null || candidate.getPositionIds().size() > 100) return false;
        }

        Set<String> unitIds = new HashSet<>();
        for (AssignmentUnit unit : input.getUnits()) {
            if (unit == null || unit.getId() == null || unit.getId().isBlank() || !unitIds.add(unit.getId())
                    || unit.getGroupId() == null || unit.getGroupId().isBlank()
                    || unit.getEstimatedMinutes() < 1 || unit.getDifficulty() < 1 || unit.getDifficulty() > 5
                    || unit.getPriority() < 1 || unit.getPriority() > 5
                    || unit.getRequiredPositionIds() == null || unit.getRequiredPositionIds().size() > 100) return false;
        }
        return true;
    }

    private boolean validWeight(int weight) {
        return weight >= 0 && weight <= 1000;
    }
}
