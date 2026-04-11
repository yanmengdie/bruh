# SwiftData Migration Strategy

## Current Baseline

- app container creation is centralized in `BruhModelStore`
- current persisted schema is pinned as `BruhSchemaV1`
- migration entrypoint is `BruhSchemaMigrationPlan`
- destructive store reset is no longer the first recovery step
- if container boot fails, the app now copies the current store into `Application Support/store-backups/` before clearing the live files

## Rules For Future Model Changes

1. Any persisted model shape change must introduce a new `VersionedSchema`.
2. Additive changes should prefer lightweight migration first.
3. Renames, splits, or semantic rewrites must use an explicit migration stage instead of deleting the store.
4. Do not remove old schema versions from `BruhSchemaMigrationPlan` until the migration has shipped and stabilized.
5. Keep the last-resort in-memory fallback only as a bootability safeguard, not as the normal migration path.

## Suggested Workflow

1. Add `BruhSchemaV2` with the updated model list.
2. Register `BruhSchemaV2` in `BruhSchemaMigrationPlan.schemas`.
3. Add a `MigrationStage.lightweight` or `MigrationStage.custom` step from `V1` to `V2`.
4. Run local build and smoke-test with an existing on-disk store before shipping.
5. If a breaking migration is unavoidable, make sure the backup copy is inspectable and documented.

## Current Risk Notes

- The app still uses a recovery path that clears the active store after backup if the container cannot be reopened.
- Preview containers and in-memory preview data are intentionally outside the migration path.
- There is not yet an automated fixture-based migration test; build validation currently relies on compile + boot-time container creation.
