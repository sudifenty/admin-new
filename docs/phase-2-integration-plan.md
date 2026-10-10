# SmartPle Remote Control — Phase 2 Integration Plan

**Status:** Planning only. Phase 1 remains a UI-only dashboard using mock data and browser `localStorage`. Nothing in this plan connects to or changes the student app.

## 1. Goal

Replace the dashboard's local-only settings with a secure server-side source of truth, then make the student experience honor the effective daily question limit. Admin changes should be traceable and enforced by the backend—not only hidden or limited in the student UI.

## 2. Proposed limit rules

Use one deterministic rule for every student:

1. **Student-specific override**, if present.
2. Otherwise, **class limit**, if present.
3. Otherwise, **global default**.
4. If no global setting exists, use the initial default of **20 questions/day**.

A limit is a non-negative whole number. `0` means no new questions are available for that student that day. Clearing a student or class rule returns that scope to the next rule in the priority order. Updating the global value should not silently erase student or class rules.

The Phase 1 dashboard already presents this precedence. Confirm it with the product owner before treating it as final, especially the meaning of “Set for ALL Students.”

## 3. Suggested API contract

Use authenticated, versioned admin endpoints. Exact paths can be adapted to the existing backend conventions.

| Operation | Suggested endpoint | Purpose |
|---|---|---|
| Read settings | `GET /admin/v1/question-limits` | Return the global default, class rules, and configuration version. |
| Search students | `GET /admin/v1/students?q=&class=&cursor=` | Return paginated live student rows for the admin list. |
| Set global | `PUT /admin/v1/question-limits/global` | Save `{ "dailyLimit": 20, "expectedVersion": 12 }`. |
| Set class | `PUT /admin/v1/classes/{classId}/question-limit` | Save a class rule, including custom values. |
| Clear class | `DELETE /admin/v1/classes/{classId}/question-limit` | Remove the class rule and fall back to global. |
| Set student | `PUT /admin/v1/students/{studentId}/question-limit` | Save a personal override. |
| Clear student | `DELETE /admin/v1/students/{studentId}/question-limit` | Remove the personal override and fall back to class/global. |
| Resolve student limit | `GET /v1/me/question-limit` | Let the signed-in student app fetch its effective limit and reset time. |

Admin responses should include the saved value, `updatedAt`, `updatedBy`, and a monotonically increasing `version` (or an ETag). Student responses should include `effectiveLimit`, `source` (`student`, `class`, or `global`), the configuration version, and the next daily reset time.

## 4. Backend and data considerations

- Store global, class, and student settings as separate scoped rules; do not materialize a global change as hundreds of individual overrides.
- Validate limits server-side as whole numbers `>= 0`. Agree on a maximum before adding one; “custom” currently has no product-defined cap.
- Record an audit event for each admin change: admin ID, target scope/ID, old and new values, timestamp, and request/correlation ID.
- Use transactions or version checks so concurrent admins do not unknowingly overwrite newer settings. Return a conflict response for stale updates and let the dashboard reload the current value.
- Reuse the backend's existing student/class identifiers and tenant or school scoping. Avoid trusting class names or student IDs supplied by the browser without authorization checks.
- Decide the daily boundary using the school's configured IANA timezone (for example, `Africa/Kampala` if that is the school setting); do not rely on the device clock.

## 5. Student-app enforcement

The student app can display the effective limit, but the backend should enforce it whenever it serves or records a question. A UI-only limit can be bypassed by an outdated client or a modified request.

- For `0`, stop serving new questions immediately according to the agreed activation policy.
- For a reduced limit during an active day, define whether a student who has already used more than the new limit is simply blocked from further questions or handled another way.
- For an increased limit, define whether the extra questions are available immediately or from the next daily reset.
- Make question delivery/counting idempotent so retries do not accidentally consume multiple questions.
- Include the effective limit and remaining count in student-facing responses where useful, while keeping the server as the authority.

## 6. Admin UI integration changes

1. Add an API client/repository layer; keep components independent of endpoint details.
2. On page load, fetch settings and a page of students. Replace mock rows with server data.
3. Keep the current option controls, but add loading, empty, permission-denied, offline, and server-error states.
4. On Save, show a pending state and only mark a value active after the server confirms it. If saving fails, preserve the draft and explain how to retry; do not imply a local-only save is a server save.
5. Add conflict handling using the server version/ETag, then refresh the affected global/class/student data.
6. Use localStorage only as an optional short-lived cache/draft aid, never as the authoritative setting after integration.
7. Keep student search paginated/debounced if the real roster is substantially larger than the 10 Phase 1 samples.

## 7. Security and operational requirements

- Require an authenticated admin identity and an explicit admin permission for every write; do not rely on hiding controls in the UI.
- Scope reads and writes to the correct school/tenant.
- Ensure student credentials cannot call admin mutation endpoints.
- Apply the project's existing CSRF, rate limiting, logging, and secrets-management practices.
- Monitor failed writes, stale-version conflicts, limit-resolution failures, and student question-limit enforcement.

## 8. Acceptance tests

- The default is 20 when no setting exists.
- Each preset (`0`, `5`, `10`, `20`, `50`) and custom whole numbers persist and appear after a reload.
- Negative, fractional, malformed, and unsafe integer values are rejected by the server.
- A student override wins over class and global; clearing it restores the class/global value.
- A class rule wins over global for students without personal overrides; clearing it restores global.
- Changing global does not overwrite class or student overrides.
- The student app receives the same effective value the admin dashboard shows and the backend enforces it at the daily boundary.
- Unauthorized writes are rejected; concurrent/stale writes return a recoverable conflict.
- Search, pagination, empty results, loading, and save errors work with a real roster.

## 9. Decisions to confirm before implementation

1. Does “Set for ALL Students” mean a **global fallback** (current Phase 1 behavior), or must it override existing class and student settings?
2. When do changes take effect—immediately, on the next question request, or on the next daily reset?
3. What should happen if the daily limit is lowered below the number of questions a student has already used that day?
4. What timezone defines the daily reset for each school?
5. Should custom limits have a maximum, and if so, what is it?
6. Does limit `0` pause only question delivery, or also affect other student-app features?

## Suggested implementation sequence

**A. Confirm the six policy decisions above.** **B. Add server-side settings, audit, authorization, and resolution tests.** **C. Integrate the admin dashboard with the admin APIs.** **D. Integrate and enforce the effective limit in the student app.** **E. Roll out behind a feature flag, verify audit/enforcement metrics, then enable by school.**
