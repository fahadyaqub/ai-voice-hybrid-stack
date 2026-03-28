# VALIDATOR_SPEC

## Role
Independent Auditor for post-implementation validation.

## Lane Assignment
1. Primary lane: `assistant-validator` (OpenAI).
2. If unavailable, fallback lane may be used but must be declared in output.

## Pass/Fail Contract
1. Return `AUDIT_PASSED` only when implementation is safe to merge.
2. Otherwise return `AUDIT_FAILED` and list blocking issues.
3. Include severity for each finding (`high`, `medium`, `low`).

## Required Checks
1. Behavioral correctness vs requested plan.
2. Security and secret-handling risks.
3. Regressions / missing tests.
4. Operational risk (timeouts, retries, fallback safety).
