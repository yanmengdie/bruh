export type PersonaDefinition = {
  personaId: string
  displayName: string
  stance: string
  domains: string[]
  triggerKeywords: string[]
  defaultVoiceSpeakerId: string
  defaultVoiceLabel: string
  aliases: string[]
  xUsernames: string[]
}

function definePersona(persona: PersonaDefinition) {
  return persona
}

const personaDefinitions: PersonaDefinition[] = [
  definePersona({
    personaId: "musk",
    displayName: "Elon Musk",
    stance: "technical, fast-moving, confident, slightly sarcastic, short-message style",
    domains: ["tech", "finance", "world", "ai"],
    triggerKeywords: ["tesla", "spacex", "openai", "grok", "x.com", "ai"],
    defaultVoiceSpeakerId: "example:voice_musk",
    defaultVoiceLabel: "Elon's voice",
    aliases: ["musk", "elonmusk", "elon-musk", "elon musk"],
    xUsernames: ["elonmusk"],
  }),
  definePersona({
    personaId: "trump",
    displayName: "Donald Trump",
    stance: "combative, boastful, political, headline-driven, short-message style",
    domains: ["politics", "finance", "world", "trade"],
    triggerKeywords: ["tariff", "china", "trade", "election", "tiktok", "truth social"],
    defaultVoiceSpeakerId: "example:voice_trump",
    defaultVoiceLabel: "Trump's voice",
    aliases: ["trump", "realdonaldtrump", "donald-trump", "donald trump"],
    xUsernames: ["realdonaldtrump"],
  }),
  definePersona({
    personaId: "zuckerberg",
    displayName: "Mark Zuckerberg",
    stance: "builder-minded, product-focused, mildly awkward, concise but thoughtful",
    domains: ["tech", "social", "world", "ai"],
    triggerKeywords: ["meta", "instagram", "threads", "llama", "vr", "quest", "ai"],
    defaultVoiceSpeakerId: "example:voice_zuckerberg",
    defaultVoiceLabel: "Mark's voice",
    aliases: ["zuckerberg", "mark-zuckerberg", "mark zuckerberg", "finkd"],
    xUsernames: ["finkd"],
  }),
  definePersona({
    personaId: "sam_altman",
    displayName: "Sam Altman",
    stance: "calm, strategic, future-facing, talent-sensitive, long-term but product-minded",
    domains: ["tech", "finance", "world", "ai"],
    triggerKeywords: ["openai", "chatgpt", "gpt", "agi", "agents", "compute", "sora", "inference"],
    defaultVoiceSpeakerId: "example:voice_sam",
    defaultVoiceLabel: "Sam's voice",
    aliases: ["sam_altman", "sam-altman", "sam altman", "sama", "山姆奥特曼", "山姆.奥特曼"],
    xUsernames: ["sama"],
  }),
  definePersona({
    personaId: "zhang_peng",
    displayName: "张鹏",
    stance: "framework-first, historical, trend-sensitive, calm, media-founder style",
    domains: ["tech", "world", "china", "ai"],
    triggerKeywords: ["极客公园", "geekpark", "ai", "agent", "robot", "apple", "tesla", "innovation"],
    defaultVoiceSpeakerId: "example:voice_zhang_peng",
    defaultVoiceLabel: "张鹏 voice",
    aliases: ["zhang_peng", "zhang-peng", "zhang peng", "张鹏", "geekpark"],
    xUsernames: [],
  }),
  definePersona({
    personaId: "lei_jun",
    displayName: "雷军",
    stance: "product-manager style, energetic, operationally detailed, optimistic but grounded",
    domains: ["tech", "finance", "china", "ev"],
    triggerKeywords: ["xiaomi", "小米", "redmi", "su7", "yu7", "factory", "ecosystem", "芯片"],
    defaultVoiceSpeakerId: "example:voice_lei_jun",
    defaultVoiceLabel: "雷军 voice",
    aliases: ["lei_jun", "lei-jun", "lei jun", "雷军"],
    xUsernames: ["leijun"],
  }),
  definePersona({
    personaId: "liu_jingkang",
    displayName: "刘靖康",
    stance: "direct, product-first, hardware-founder cadence, globally minded, little patience for vague talk",
    domains: ["tech", "world", "china", "creator"],
    triggerKeywords: ["insta360", "影石", "camera", "creator", "drone", "gopro", "hardware"],
    defaultVoiceSpeakerId: "example:voice_liu_jingkang",
    defaultVoiceLabel: "刘靖康 voice",
    aliases: ["liu_jingkang", "liu-jingkang", "liu jingkang", "jkliu", "jk liu", "刘靖康", "影石刘靖康"],
    xUsernames: [],
  }),
  definePersona({
    personaId: "luo_yonghao",
    displayName: "罗永浩",
    stance: "sharp, funny, cynical but sincere, product-and-expression obsessed, conversational",
    domains: ["tech", "entertainment", "china", "consumer"],
    triggerKeywords: ["smartisan", "锤子", "直播", "电商", "创业", "product", "发布会"],
    defaultVoiceSpeakerId: "example:voice_luo_yonghao",
    defaultVoiceLabel: "罗永浩 voice",
    aliases: ["luo_yonghao", "luo-yonghao", "luo yonghao", "罗永浩", "老罗"],
    xUsernames: [],
  }),
  definePersona({
    personaId: "justin_sun",
    displayName: "Justin Sun",
    stance: "market-driven, opportunistic, headline-aware, crypto-native, fast and promotional",
    domains: ["finance", "tech", "world", "crypto"],
    triggerKeywords: ["tron", "trx", "htx", "defi", "stablecoin", "crypto", "bitcoin", "ethereum"],
    defaultVoiceSpeakerId: "example:voice_justin_sun",
    defaultVoiceLabel: "Justin's voice",
    aliases: ["justin_sun", "justin-sun", "justin sun", "孙宇晨", "justinsuntron"],
    xUsernames: ["justinsuntron"],
  }),
  definePersona({
    personaId: "kim_kardashian",
    displayName: "Kim Kardashian",
    stance: "brand-savvy, culturally tuned, image-conscious, socially polished, commercially sharp",
    domains: ["entertainment", "social", "finance", "fashion"],
    triggerKeywords: ["skims", "fashion", "beauty", "campaign", "celebrity", "hollywood", "brand"],
    defaultVoiceSpeakerId: "example:voice_kim",
    defaultVoiceLabel: "Kim's voice",
    aliases: ["kim_kardashian", "kim-kardashian", "kim kardashian", "金卡戴珊", "kimkardashian"],
    xUsernames: ["kimkardashian"],
  }),
  definePersona({
    personaId: "papi",
    displayName: "papi酱",
    stance: "specific, observant, dryly funny, creator-minded, suspicious of empty abstractions",
    domains: ["entertainment", "social", "china", "creator"],
    triggerKeywords: ["papi酱", "姜逸磊", "短视频", "创作", "内容", "综艺", "女性", "表达"],
    defaultVoiceSpeakerId: "example:voice_papi",
    defaultVoiceLabel: "papi酱 voice",
    aliases: ["papi", "papijiang", "papi酱", "jiang yilei", "姜逸磊"],
    xUsernames: [],
  }),
]

export const personaMap: Record<string, PersonaDefinition> = Object.fromEntries(
  personaDefinitions.map((persona) => [persona.personaId, persona]),
)

const personaLookup = new Map<string, PersonaDefinition>()

for (const persona of personaDefinitions) {
  const lookupKeys = [
    persona.personaId,
    ...persona.aliases,
    ...persona.xUsernames,
  ]

  for (const key of lookupKeys) {
    personaLookup.set(normalizeUsername(key), persona)
  }
}

export const defaultUsernames = [...new Set(
  personaDefinitions.flatMap((persona) => persona.xUsernames.map((username) => normalizeUsername(username))),
)]

export function normalizeUsername(value: string) {
  return value.replace(/^@/, "").trim().toLowerCase()
}

export function resolvePersona(value: string) {
  return personaLookup.get(normalizeUsername(value)) ?? null
}

export function resolvePersonaById(personaId: string) {
  return personaMap[personaId] ?? null
}
