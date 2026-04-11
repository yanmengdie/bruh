export type PersonaPlatformAccountRecord = {
  platform: string
  handle: string
  profileUrl?: string | null
  isPrimary: boolean
  isActive: boolean
}

export type PersonaCatalogRecord = {
  id: string
  displayName: string
  avatarName: string
  handle: string
  stance: string
  domains: string[]
  leadInterestIds: string[]
  triggerKeywords: string[]
  entityKeywords: string[]
  subtitle: string
  inviteMessage: string
  themeColorHex: string
  locationLabel: string
  baseInviteOrder: number
  primaryLanguage: string
  friendGreeting: string
  aliases: string[]
  platformAccounts: PersonaPlatformAccountRecord[]
  defaultVoiceSpeakerId: string
  defaultVoiceLabel: string
  socialCircleIds: string[]
  relationshipHints: Record<string, string>
}

const allowedPrimaryLanguages = new Set(["en", "zh"])
const colorHexPattern = /^#[0-9a-f]{6}$/i

function schemaError(path: string, message: string): never {
  throw new Error(`SharedPersonas.json ${path}: ${message}`)
}

function requireRecord(value: unknown, path: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    schemaError(path, "must be an object")
  }
  return value as Record<string, unknown>
}

function requireNonEmptyString(value: unknown, path: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    schemaError(path, "must be a non-empty string")
  }
  return value.trim()
}

function requireBoolean(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") {
    schemaError(path, "must be a boolean")
  }
  return value
}

function requireStringArray(value: unknown, path: string): string[] {
  if (!Array.isArray(value)) {
    schemaError(path, "must be an array")
  }

  const strings = value.map((item, index) => requireNonEmptyString(item, `${path}[${index}]`))
  const deduped = new Set(strings)
  if (deduped.size !== strings.length) {
    schemaError(path, "must not contain duplicates")
  }

  return strings
}

function requireRelationshipHints(value: unknown, path: string) {
  const hints = requireRecord(value, path)
  const normalized: Record<string, string> = {}

  for (const [key, hint] of Object.entries(hints)) {
    normalized[requireNonEmptyString(key, `${path} key`)] = requireNonEmptyString(hint, `${path}.${key}`)
  }

  return normalized
}

function requirePlatformAccounts(value: unknown, path: string): PersonaPlatformAccountRecord[] {
  if (!Array.isArray(value)) {
    schemaError(path, "must be an array")
  }

  const seenPrimaryPlatforms = new Set<string>()
  return value.map((item, index) => {
    const record = requireRecord(item, `${path}[${index}]`)
    const platform = requireNonEmptyString(record.platform, `${path}[${index}].platform`).toLowerCase()
    const handle = requireNonEmptyString(record.handle, `${path}[${index}].handle`)
    const profileUrl = record.profileUrl == null
      ? null
      : requireNonEmptyString(record.profileUrl, `${path}[${index}].profileUrl`)
    const isPrimary = requireBoolean(record.isPrimary, `${path}[${index}].isPrimary`)
    const isActive = requireBoolean(record.isActive, `${path}[${index}].isActive`)

    if (isPrimary) {
      if (seenPrimaryPlatforms.has(platform)) {
        schemaError(`${path}[${index}].platform`, "must not define multiple primary accounts for the same platform")
      }
      seenPrimaryPlatforms.add(platform)
    }

    return {
      platform,
      handle,
      profileUrl,
      isPrimary,
      isActive,
    }
  })
}

export function assertValidPersonaCatalogData(value: unknown): asserts value is PersonaCatalogRecord[] {
  if (!Array.isArray(value) || value.length === 0) {
    schemaError("$", "must be a non-empty array")
  }

  const seenIds = new Set<string>()

  value.forEach((item, index) => {
    const path = `$[${index}]`
    const record = requireRecord(item, path)
    const id = requireNonEmptyString(record.id, `${path}.id`)

    if (seenIds.has(id)) {
      schemaError(`${path}.id`, `duplicate persona id "${id}"`)
    }
    seenIds.add(id)

    requireNonEmptyString(record.displayName, `${path}.displayName`)
    requireNonEmptyString(record.avatarName, `${path}.avatarName`)
    const handle = requireNonEmptyString(record.handle, `${path}.handle`)
    if (!handle.startsWith("@")) {
      schemaError(`${path}.handle`, "must start with @")
    }

    requireStringArray(record.domains, `${path}.domains`)
    requireStringArray(record.leadInterestIds, `${path}.leadInterestIds`)
    requireNonEmptyString(record.stance, `${path}.stance`)
    requireStringArray(record.triggerKeywords, `${path}.triggerKeywords`)
    requireStringArray(record.entityKeywords, `${path}.entityKeywords`)
    requireNonEmptyString(record.subtitle, `${path}.subtitle`)
    requireNonEmptyString(record.inviteMessage, `${path}.inviteMessage`)
    const themeColorHex = requireNonEmptyString(record.themeColorHex, `${path}.themeColorHex`)
    if (!colorHexPattern.test(themeColorHex)) {
      schemaError(`${path}.themeColorHex`, "must be a 6-digit hex color")
    }

    requireNonEmptyString(record.locationLabel, `${path}.locationLabel`)
    if (!Number.isInteger(record.baseInviteOrder) || Number(record.baseInviteOrder) < 0) {
      schemaError(`${path}.baseInviteOrder`, "must be a non-negative integer")
    }

    const primaryLanguage = requireNonEmptyString(record.primaryLanguage, `${path}.primaryLanguage`)
    if (!allowedPrimaryLanguages.has(primaryLanguage)) {
      schemaError(`${path}.primaryLanguage`, `must be one of ${[...allowedPrimaryLanguages].join(", ")}`)
    }

    requireNonEmptyString(record.friendGreeting, `${path}.friendGreeting`)
    requireStringArray(record.aliases, `${path}.aliases`)
    requirePlatformAccounts(record.platformAccounts, `${path}.platformAccounts`)
    requireNonEmptyString(record.defaultVoiceSpeakerId, `${path}.defaultVoiceSpeakerId`)
    requireNonEmptyString(record.defaultVoiceLabel, `${path}.defaultVoiceLabel`)
    const socialCircleIds = requireStringArray(record.socialCircleIds, `${path}.socialCircleIds`)
    const relationshipHints = requireRelationshipHints(record.relationshipHints, `${path}.relationshipHints`)

    for (const relatedId of Object.keys(relationshipHints)) {
      if (!socialCircleIds.includes(relatedId)) {
        schemaError(`${path}.relationshipHints.${relatedId}`, "must reference a persona declared in socialCircleIds")
      }
    }
  })
}
