# ADR-027: M2 Bootstrap implementation defaults

Status: Provisional

## Decisions for bootstrap
- Build tool: Maven.
- Database migration: Flyway.
- Local infrastructure: Docker Compose.
- Search implementation candidate: OpenSearch.
- CI example: GitHub Actions; replace if repository host differs.
- Java runtime baseline: Java 21.
- Spring Boot baseline for the starter package: 4.1.1.
- Flutter defaults remain Riverpod + go_router.

## Boundaries
These choices do not change M1 domain/API semantics. They may be replaced by a new ADR before dependent production implementation.

## Non-negotiable M1 constraints
- PostgreSQL is the source of truth.
- Redis is auxiliary only.
- RabbitMQ messages are published via Outbox.
- OpenAPI validation is a CI gate.
- inventory writes use Adjustment commands.
- Quote, PaymentAttempt channel, cancellation detail and append-only ledgers must not be bypassed.
