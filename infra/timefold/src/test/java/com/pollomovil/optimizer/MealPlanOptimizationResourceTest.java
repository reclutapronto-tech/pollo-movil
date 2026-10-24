package com.pollomovil.optimizer;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.IntStream;

import org.junit.jupiter.api.Test;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.Response;

@QuarkusTest
class MealPlanOptimizationResourceTest {

    @Test
    void requiresThePrivateTimefoldServiceToken() {
        given().contentType(ContentType.JSON)
                .body(Map.of("workers", List.of(), "mealStartRange", List.of()))
                .when().post("/api/meal-plans/solve")
                .then().statusCode(401);
    }

    @Test
    void usesTimefoldToStaggerMealsInsidePublishedShiftWindows() {
        List<Integer> slots = IntStream.rangeClosed(32, 60).map(value -> value * 15).boxed().toList();
        List<Map<String, Object>> workers = new ArrayList<>();
        workers.add(Map.of("employeeId", "employee-a", "shiftStartMinute", 480,
                "shiftEndMinute", 960, "mealDurationMinutes", 30, "preferredMealStartMinute", 720,
                "blockedStartMinutes", List.of()));
        workers.add(Map.of("employeeId", "employee-b", "shiftStartMinute", 480,
                "shiftEndMinute", 960, "mealDurationMinutes", 30, "preferredMealStartMinute", 720,
                "blockedStartMinutes", List.of()));
        Response response = given().header("Authorization", "Bearer ci-timefold-test-token")
                .contentType(ContentType.JSON).body(Map.of("workers", workers, "mealStartRange", slots))
                .when().post("/api/meal-plans/solve");

        assertEquals(200, response.statusCode(), response.asString());
        assertTrue(response.jsonPath().getBoolean("feasible"));
        assertEquals("timefold", response.jsonPath().getString("planner"));
        List<Map<String, Object>> assignments = response.jsonPath().getList("assignments");
        assertEquals(2, assignments.size());
        assertEquals(2, assignments.stream().map(row -> row.get("employee_id")).distinct().count());
        List<Integer> starts = assignments.stream().map(row -> ((Number) row.get("start_minute")).intValue()).sorted().toList();
        assertTrue(starts.get(1) >= starts.get(0) + 30, "meal periods must not overlap");
        assertTrue(assignments.stream().allMatch(row -> ((Number) row.get("start_minute")).intValue() >= 480
                && ((Number) row.get("end_minute")).intValue() <= 960));
    }
}
