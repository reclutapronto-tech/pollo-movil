import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import {
  corsHeaders,
  errorResponse,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"

const ENDPOINT = "breadcrumbs"

serve((request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(request) })
  }

  const requestId = makeRequestId(request)
  logRequestStart(ENDPOINT, requestId, request)
  return errorResponse(
    requestId,
    410,
    "GPS_TRACKING_DISABLED",
    "Continuous GPS trail collection is disabled in Pollo Móvil. Location checks are limited to configured clock-in and clock-out events.",
  )
})
