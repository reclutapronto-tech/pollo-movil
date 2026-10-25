package com.pollomovil.optimizer;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutionException;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import ai.timefold.solver.core.api.solver.SolverJob;
import ai.timefold.solver.core.api.solver.SolverManager;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/meal-plans")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class MealPlanOptimizationResource {
    @Inject
    @Named("mealPlan")
    SolverManager<MealPlanSolution> solverManager;

    @ConfigProperty(name = "pollo.timefold.api-token", defaultValue = "")
    String apiToken;

    @POST
    @Path("/solve")
    public Response solve(MealPlanSolution input, @HeaderParam("Authorization") String authorization) {
        if (!isAuthorized(authorization)) return Response.status(Response.Status.UNAUTHORIZED).build();
        if (input == null || input.getWorkers() == null || input.getWorkers().isEmpty()
                || input.getWorkers().size() > 200 || input.getMealStartRange() == null
                || input.getMealStartRange().isEmpty() || input.getMealStartRange().size() > 192) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(Map.of("error", "A meal plan requires bounded worker and time-slot data.")).build();
        }
        for (MealPlanWorker worker : input.getWorkers()) {
            if (worker == null || worker.getEmployeeId() == null || worker.getEmployeeId().isBlank()
                    || worker.getShiftStartMinute() < 0 || worker.getShiftEndMinute() > 2880
                    || worker.getShiftEndMinute() <= worker.getShiftStartMinute()
                    || worker.getMealDurationMinutes() < 1 || worker.getMealDurationMinutes() > 240
                    || worker.getPreferredMealStartMinute() < 0 || worker.getPreferredMealStartMinute() > 2879
                    || worker.getPreferredMealStartMinute() < worker.getShiftStartMinute()
                    || worker.getPreferredMealStartMinute() + worker.getMealDurationMinutes() > worker.getShiftEndMinute()
                    || worker.getBlockedStartMinutes() == null || worker.getBlockedStartMinutes().size() > 192) {
                return Response.status(Response.Status.BAD_REQUEST)
                        .entity(Map.of("error", "A worker shift or meal constraint is malformed.")).build();
            }
        }
        for (Integer minute : input.getMealStartRange()) {
            if (minute == null || minute < 0 || minute > 2879 || minute % 15 != 0) {
                return Response.status(Response.Status.BAD_REQUEST)
                        .entity(Map.of("error", "Meal start slots must be 15-minute boundaries.")).build();
            }
        }

        UUID problemId = UUID.randomUUID();
        SolverJob<MealPlanSolution> job = solverManager.solve(problemId, input);
        final MealPlanSolution best;
        try {
            best = job.getFinalBestSolution();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return Response.serverError().entity(Map.of("error", "Meal optimization was interrupted.")).build();
        } catch (ExecutionException exception) {
            return Response.serverError().entity(Map.of("error", "Meal optimization could not produce a solution.")).build();
        }
        if (best.getScore() == null || !best.getScore().isFeasible()) {
            return Response.status(422)
                    .entity(Map.of("error", "No meal schedule satisfies all shift, break and coverage-safe constraints.",
                            "score", best.getScore() == null ? "unknown" : best.getScore().toString())).build();
        }
        List<Map<String, Object>> assignments = new ArrayList<>();
        for (MealPlanWorker worker : best.getWorkers()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("employee_id", worker.getEmployeeId());
            row.put("start_minute", worker.getMealStartMinute());
            row.put("end_minute", worker.getMealStartMinute() + worker.getMealDurationMinutes());
            assignments.add(row);
        }
        return Response.ok(Map.of("planner", "timefold", "feasible", true,
                "score", best.getScore().toString(), "assignments", assignments)).build();
    }

    private boolean isAuthorized(String authorization) {
        if (apiToken == null || apiToken.isBlank() || authorization == null || !authorization.startsWith("Bearer ")) return false;
        return MessageDigest.isEqual(apiToken.getBytes(StandardCharsets.UTF_8),
                authorization.substring("Bearer ".length()).getBytes(StandardCharsets.UTF_8));
    }
}
