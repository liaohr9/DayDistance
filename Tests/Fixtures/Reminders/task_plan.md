# Reminder module plan
- [x] Read public behavior and coordinate CountdownEvent fields.
- [x] Implement pure calendar notification plan and tests, including DST and yearly leap days.
- [x] Implement native notification service with explicit permission, owned-ID replacement, serial generation handling and event links.
- [x] Run isolated SwiftPM tests and SDK typecheck; record limitations.

Complete: 11 XCTest policy cases passed; mock service CLI probe passed, compiled with Xcode SDK. Verification details in notes.md and verification.log.

Scope: Shared/Core/ReminderPolicy.swift, App/Services/EventReminderService.swift, Tests/ReminderPolicyTests.swift, reminder fixtures only. No real notification scheduling or user data edits in tests.

Errors resolved: macOS UNAuthorizationStatus.ephemeral is unavailable, so native service handles authorized/provisional. Largest supported year can cause occurrence fallback; annual policy now stops when returned occurrence is before its cursor.
