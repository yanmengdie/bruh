import personaCatalogData from "../../../bruh/SharedPersonas.json" with { type: "json" }
import { assertValidPersonaCatalogData } from "./persona_catalog_schema.ts"
import { defaultUsernames, resolvePersona, resolvePersonaById } from "./personas.ts"

Deno.test("SharedPersonas catalog passes schema validation", () => {
  assertValidPersonaCatalogData(personaCatalogData)
})

Deno.test("persona lookup remains stable for canonical ids and usernames", () => {
  const trump = resolvePersonaById("trump")
  if (!trump) {
    throw new Error("Expected trump persona to exist")
  }

  const byHandle = resolvePersona("@realdonaldtrump")
  if (!byHandle || byHandle.personaId != "trump") {
    throw new Error("Expected resolvePersona to find trump by handle")
  }

  if (!defaultUsernames.includes("realdonaldtrump")) {
    throw new Error("Expected default usernames to include realdonaldtrump")
  }
})
