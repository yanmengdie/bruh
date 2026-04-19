import {
  chooseBestUser,
  collectProfileNotes,
  createContext,
  getLoginState,
  getMainPage,
  parseArgs,
  scrapeNotePage,
  searchUsers,
  writeOutputFile,
} from "./_shared.mjs"

const defaultFunctionsURL = "https://frequencies-main-saver-eggs.trycloudflare.com/functions/v1"
const defaultAnonKey = "bruh-local-anon"

function readBooleanArg(value, fallback) {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    if (["1", "true", "yes", "y", "on"].includes(normalized)) return true
    if (["0", "false", "no", "n", "off"].includes(normalized)) return false
  }
  return fallback
}

function isUsableNoteImage(url) {
  return typeof url === "string" &&
    /xhscdn\.com/i.test(url) &&
    !/avatar|user-avatar|default-avatar|fe-avatar/i.test(url) &&
    /webpic|spectrum|sns-img|sns-webpic/i.test(url)
}

async function invokeFunction(baseURL, anonKey, functionName, body) {
  const response = await fetch(`${baseURL}/${functionName}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  })

  const text = await response.text()
  let json = null
  try {
    json = JSON.parse(text)
  } catch {
    json = null
  }

  if (!response.ok) {
    throw new Error(json?.error ?? text ?? `${functionName} failed with ${response.status}`)
  }

  return json
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const query = String(args.query ?? args.q ?? "科技薯").trim()
  const limitRaw = Number.parseInt(String(args.limit ?? "5"), 10)
  const limit = Number.isNaN(limitRaw) ? 5 : Math.min(Math.max(limitRaw, 1), 10)
  const headless = !readBooleanArg(args.headful, false)
  const cookieString = process.env.XHS_COOKIE ?? ""
  const shouldIngest = readBooleanArg(args.ingest, false)
  const shouldBuildFeed = readBooleanArg(args["build-feed"], true)
  const functionsURL = process.env.SUPABASE_FUNCTIONS_URL ?? defaultFunctionsURL
  const anonKey = process.env.SUPABASE_ANON_KEY ?? defaultAnonKey

  const context = await createContext({ headless, cookieString })
  try {
    const page = await getMainPage(context)
    const loginState = await getLoginState(page)
    if (!loginState.userId || loginState.guest !== false) {
      throw new Error("当前没有可用的小红书登录态，请先运行 `npm run login`。")
    }

    const searchResult = await searchUsers(page, query)
    const records = Array.isArray(searchResult?.users)
      ? searchResult.users
      : Array.isArray(searchResult?.data?.users)
        ? searchResult.data.users
        : []

    if (records.length === 0) {
      throw new Error(`没有搜到用户：${query}`)
    }

    const { picked, candidates } = chooseBestUser(records, query)
    const personaId = String(args["persona-id"] ?? args.personaId ?? picked.nickname ?? query).trim()
    if (!picked?.profileUrl) {
      throw new Error(`搜到了候选用户，但无法构造资料页链接：${query}`)
    }

    await page.goto(picked.profileUrl, { waitUntil: "domcontentloaded", timeout: 120000 })
    await page.waitForTimeout(5000)

    const notes = await collectProfileNotes(page, limit)
    if (notes.length === 0) {
      throw new Error(`已进入资料页，但没有抓到笔记卡片：${picked.profileUrl}`)
    }

    const enrichedNotes = []
    for (const note of notes) {
      const targetUrl = note.noteUrl || note.exploreUrl
      if (!targetUrl) {
        enrichedNotes.push(note)
        continue
      }

      const detail = await scrapeNotePage(context, targetUrl).catch(() => null)
      const detailImageUrls = Array.isArray(detail?.imageUrls)
        ? detail.imageUrls.filter(isUsableNoteImage)
        : []

      enrichedNotes.push({
        ...note,
        rawText: String(detail?.content ?? note.rawText ?? "").trim() || note.rawText,
        imageUrls: detailImageUrls.length > 0
          ? detailImageUrls
          : note.imageUrls,
        coverImageUrl: detailImageUrls.length > 0
          ? detailImageUrls[0]
          : note.coverImageUrl,
        videoUrl: typeof detail?.videoUrl === "string" && detail.videoUrl
          ? detail.videoUrl
          : note.videoUrl ?? null,
        publishedAt: typeof detail?.publishedAt === "string" && detail.publishedAt
          ? detail.publishedAt
          : note.publishedAt ?? null,
      })
    }

    const payload = {
      query,
      syncedAt: new Date().toISOString(),
      matchedUser: {
        personaId,
        nickname: picked.nickname,
        userId: picked.userId,
        xsecToken: picked.xsecToken,
        profileUrl: picked.profileUrl,
      },
      candidates: candidates.slice(0, 5).map((candidate) => ({
        nickname: candidate.nickname,
        userId: candidate.userId,
        profileUrl: candidate.profileUrl,
      })),
      notes: enrichedNotes,
    }

    if (shouldIngest) {
      const ingestResult = await invokeFunction(functionsURL, anonKey, "ingest-xhs-posts", {
        personaId,
        displayName: picked.nickname ?? query,
        userId: picked.userId,
        sourceHandle: `xhs:${picked.userId ?? personaId}`,
        profileUrl: picked.profileUrl,
        notes: enrichedNotes.map((note) => ({
          noteId: note.noteId,
          title: note.title,
          rawText: note.rawText,
          noteUrl: note.noteUrl,
          exploreUrl: note.exploreUrl,
          coverImageUrl: note.coverImageUrl,
          imageUrls: Array.isArray(note.imageUrls) ? note.imageUrls : [],
          videoUrl: note.videoUrl ?? null,
          publishedAt: note.publishedAt ?? null,
          likeCount: note.likeCount,
          isPinned: note.isPinned,
          rawPayload: note,
        })),
      })

      payload.ingestResult = ingestResult

      if (shouldBuildFeed) {
        payload.buildFeedResult = await invokeFunction(functionsURL, anonKey, "build-feed", {
          limit: 200,
        })
      }
    }

    const outputFile = await writeOutputFile(`xhs-${query}`, payload)

    console.log(`匹配用户: ${picked.nickname ?? "未知"} (${picked.userId ?? "no-user-id"})`)
    console.log(`资料页: ${picked.profileUrl}`)
    console.log(`输出文件: ${outputFile}`)
    if (shouldIngest) {
      console.log(`入库 personaId: ${personaId}`)
      if (payload.ingestResult) {
        console.log(`ingest-xhs-posts: ${JSON.stringify(payload.ingestResult)}`)
      }
      if (payload.buildFeedResult) {
        console.log(`build-feed: ${JSON.stringify(payload.buildFeedResult)}`)
      }
    }
    console.log("")
    for (const [index, note] of enrichedNotes.entries()) {
      console.log(`${index + 1}. ${note.title}`)
      console.log(`   ${note.noteUrl || note.exploreUrl || "no-url"}`)
      console.log(`   ${String(note.rawText ?? "").slice(0, 140)}`)
    }
  } finally {
    await context.close()
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
