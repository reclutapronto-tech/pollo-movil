package com.pollomovil.optimizer;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.Response;

import static io.restassured.RestAssured.given;

@QuarkusTest
class AssignmentOptimizationResourceTest {

    @Test
    void rejectsRequestsWithoutTheServiceToken() {
        given()
                .contentType(ContentType.JSON)
                .body("{\"candidates\":[],\"units\":[]}")
                .when()
                .post("/api/assignments/solve")
                .then()
                .statusCode(401);
    }

    @Test
    void solvesWithPositionCapacityAvailabilityAndSplitTaskConstraints() {
        String problem = """
                {
                  "candidates": [
                    {"id":"cook-a","positionIds":["cook"],"onShift":true,"onBreak":false,"absent":false,"servingCustomers":false,"capacityMinutes":20,"assignedWeightedMinutes":0,"recentHeavyTasks":0,"rotationRank":0},
                    {"id":"cook-b","positionIds":["cook"],"onShift":true,"onBreak":false,"absent":false,"servingCustomers":false,"capacityMinutes":20,"assignedWeightedMinutes":0,"recentHeavyTasks":0,"rotationRank":1},
                    {"id":"wrong-position","positionIds":["service"],"onShift":true,"onBreak":false,"absent":false,"servingCustomers":false,"capacityMinutes":60,"assignedWeightedMinutes":0,"recentHeavyTasks":0,"rotationRank":0},
                    {"id":"absent-cook","positionIds":["cook"],"onShift":true,"onBreak":false,"absent":true,"servingCustomers":false,"capacityMinutes":60,"assignedWeightedMinutes":0,"recentHeavyTasks":0,"rotationRank":0}
                  ],
                  "units": [
                    {"id":"part-a","groupId":"divided-task","requiredPositionIds":["cook"],"estimatedMinutes":10,"difficulty":2,"priority":3,"interruptible":true},
                    {"id":"part-b","groupId":"divided-task","requiredPositionIds":["cook"],"estimatedMinutes":10,"difficulty":2,"priority":3,"interruptible":true},
                    {"id":"task-c","groupId":"task-c","requiredPositionIds":["cook"],"estimatedMinutes":10,"difficulty":2,"priority":3,"interruptible":true},
                    {"id":"task-d","groupId":"task-d","requiredPositionIds":["cook"],"estimatedMinutes":10,"difficulty":2,"priority":3,"interruptible":true}
                  ],
                  "weights":{"loadBalanceWeight":100,"heavyRotationWeight":60,"priorityWeight":100}
                }
                """;

        Response response = given()
                .header("Authorization", "Bearer ci-timefold-test-token")
                .contentType(ContentType.JSON)
                .body(problem)
                .when()
                .post("/api/assignments/solve");

        assertEquals(200, response.statusCode(), response.asString());
        List<Map<String, String>> assignments = response.jsonPath().getList("assignments");
        assertEquals(4, assignments.size());
        assertEquals(List.of(), response.jsonPath().getList("unassignedUnitIds"));

        Set<String> candidateIds = assignments.stream()
                .map(assignment -> assignment.get("candidateId"))
                .collect(Collectors.toSet());
        assertEquals(Set.of("cook-a", "cook-b"), candidateIds);
        assertFalse(assignments.stream().anyMatch(assignment ->
                "wrong-position".equals(assignment.get("candidateId"))
                        || "absent-cook".equals(assignment.get("candidateId"))));

        assertEquals(2L, assignments.stream().filter(a -> "cook-a".equals(a.get("candidateId"))).count());
        assertEquals(2L, assignments.stream().filter(a -> "cook-b".equals(a.get("candidateId"))).count());

        String partACandidate = assignments.stream()
                .filter(assignment -> "part-a".equals(assignment.get("unitId")))
                .findFirst().orElseThrow().get("candidateId");
        String partBCandidate = assignments.stream()
                .filter(assignment -> "part-b".equals(assignment.get("unitId")))
                .findFirst().orElseThrow().get("candidateId");
        assertFalse(partACandidate.equals(partBCandidate), "split task parts must go to different employees");
        assertTrue(response.jsonPath().getString("score").startsWith("0hard/0medium/"));
    }
}
