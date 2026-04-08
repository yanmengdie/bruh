import {
  chooseBestUser,
  collectProfileNotes,
  createContext,
  getLoginState,
  getMainPage,
  parseArgs,
  searchUsers,
  writeOutputFile,
} from "./_shared.mjs"

const defaultFunctionsURL = "https://mrxctelezutprdeemqla.supabase.co/functions/v1"
const defaultAnonKey = "sb_publishable_ry_i_qMeMDzxeE7qhSl1UA_XcAwgQL1"

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
  const headless = args.headful !== true
  const cookieString = process.env.XHS_COOKIE ?? ""
  const shouldIngest = args.ingest === true
  const shouldBuildFeed = args["build-feed"] !== false
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
      notes,
    }

    if (shouldIngest) {
      const ingestResult = await invokeFunction(functionsURL, anonKey, "ingest-xhs-posts", {
        personaId,
        displayName: picked.nickname ?? query,
        userId: picked.userId,
        sourceHandle: `xhs:${picked.userId ?? personaId}`,
        profileUrl: picked.profileUrl,
        notes: notes.map((note) => ({
          noteId: note.noteId,
          title: note.title,
          rawText: note.rawText,
          noteUrl: note.noteUrl,
          exploreUrl: note.exploreUrl,
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
    for (const [index, note] of notes.entries()) {
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
