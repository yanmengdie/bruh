import fs from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

export const TOOL_DIR = __dirname
export const AUTH_DIR = path.join(TOOL_DIR, ".auth")
export const OUTPUT_DIR = path.join(TOOL_DIR, "output")
export const DEFAULT_HOME_URL = "https://www.xiaohongshu.com/explore?source=tourist_search"
export const XHS_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
export const X_S_COMMON =
  "2UQAPsHCPUIjqArjwjHjNsQhPsHCH0rjNsQhPaHCH0c1PUhAHjIj2eHjwjQ+GnPW/MPjNsQhPUHCHdYiqUMIGUM78nHjNsQh+sHCH0G1+shlHjIj2eLjwjHlwnc9w/LF+fHA8g8fJBM0JdkU+fQjJ9k6+o80JBEk+fQF4fYU+BlM80PIPeZIP0WhP/cFHjIj2eGjwjHjNsQh+UHCHjHVHdWhH0k14nlVNsQhwaHCN/DAP/DM+eWAPUIj2erIH0iINsQhP/rjwjQ1J7QTGnIjNsQhP/HjwjHl+AqM+/Wh+0PA+0DhwAr7+AcFP0qU+0rEw/HjKc=="

export function parseArgs(argv) {
  const args = {}
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]
    if (!token.startsWith("--")) continue
    const key = token.slice(2)
    const next = argv[index + 1]
    if (!next || next.startsWith("--")) {
      args[key] = true
      continue
    }
    args[key] = next
    index += 1
  }
  return args
}

export async function ensureLocalDirs() {
  await fs.mkdir(AUTH_DIR, { recursive: true })
  await fs.mkdir(OUTPUT_DIR, { recursive: true })
}

function parseCookieString(cookieString) {
  return cookieString
    .split(";")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const separatorIndex = part.indexOf("=")
      if (separatorIndex <= 0) return null
      return {
        name: part.slice(0, separatorIndex).trim(),
        value: part.slice(separatorIndex + 1).trim(),
        domain: ".xiaohongshu.com",
        path: "/",
        secure: true,
        httpOnly: false,
        sameSite: "Lax",
      }
    })
    .filter(Boolean)
}

export async function createContext({ headless = false, cookieString = "" } = {}) {
  await ensureLocalDirs()
  const context = await chromium.launchPersistentContext(AUTH_DIR, {
    headless,
    locale: "zh-CN",
    viewport: { width: 1440, height: 1200 },
    userAgent: XHS_USER_AGENT,
  })

  if (cookieString.trim()) {
    const cookies = parseCookieString(cookieString)
    if (cookies.length > 0) {
      await context.addCookies(cookies)
    }
  }

  return context
}

export async function getMainPage(context, url = DEFAULT_HOME_URL) {
  const existingPage = context.pages()[0] ?? (await context.newPage())
  await existingPage.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 })
  await existingPage.waitForTimeout(6000)
  return existingPage
}

export async function signedFetch(page, { path: requestPath, method = "GET", body = null }) {
  return page.evaluate(
    async ({ requestPath: innerPath, method: innerMethod, body: innerBody, xSCommon }) => {
      function randomHex(size = 16) {
        const chars = "abcdef0123456789"
        let output = ""
        for (let index = 0; index < size; index += 1) {
          output += chars[Math.floor(Math.random() * chars.length)]
        }
        return output
      }

      const payload = innerBody == null ? "" : JSON.stringify(innerBody)
      const signed = await window._webmsxyw(innerPath, payload)
      let xS = String(signed["X-s"] ?? signed["x-s"] ?? "")
      if (xS.startsWith("XYW_")) {
        xS = `XYS_${xS.slice(4)}`
      }

      const response = await fetch(`https://edith.xiaohongshu.com${innerPath}`, {
        method: innerMethod,
        credentials: "include",
        headers: {
          "content-type": "application/json;charset=UTF-8",
          "x-s": xS,
          "x-t": String(signed["X-t"] ?? signed["x-t"] ?? ""),
          "x-s-common": xSCommon,
          "x-b3-traceid": randomHex(16),
          "x-xray-traceid": randomHex(32),
          xsecappid: "xhs-pc-web",
        },
        body: innerMethod === "GET" ? undefined : payload,
      })

      const text = await response.text()
      let json = null
      try {
        json = JSON.parse(text)
      } catch {
        json = null
      }

      return {
        ok: response.ok,
        status: response.status,
        text,
        json,
      }
    },
    { requestPath, method, body, xSCommon: X_S_COMMON },
  )
}

export async function getLoginState(page) {
  const response = await signedFetch(page, {
    path: "/api/sns/web/v2/user/me",
    method: "GET",
  })

  const payload = response.json?.data ?? {}
  return {
    ok: response.ok,
    status: response.status,
    raw: response,
    guest: payload.guest !== false,
    userId: payload.user_id ?? null,
    payload,
  }
}

export async function waitForLogin(page, timeoutMs = 5 * 60 * 1000) {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    const state = await getLoginState(page)
    if (state.userId && state.guest === false) {
      return state
    }
    await page.waitForTimeout(3000)
  }
  return null
}

export async function searchUsers(page, query) {
  return page.evaluate(async ({ query: searchQuery }) => {
    let req = null
    window.webpackChunkxhs_pc_web.push([[Symbol("probe")], {}, (r) => {
      req = r
    }])
    const api = req(40122)
    return api._F({
      searchUserRequest: {
        keyword: searchQuery,
        searchId: crypto.randomUUID().replace(/-/g, ""),
        page: 1,
        pageSize: 15,
        bizType: "web_search_user",
        requestId: crypto.randomUUID(),
      },
    })
  }, { query })
}

function walkObject(value, visitor) {
  if (value == null) return
  if (Array.isArray(value)) {
    for (const item of value) walkObject(item, visitor)
    return
  }
  if (typeof value !== "object") return
  visitor(value)
  for (const nestedValue of Object.values(value)) {
    walkObject(nestedValue, visitor)
  }
}

function firstStringByKeys(record, keys) {
  let found = null
  walkObject(record, (candidate) => {
    if (found) return
    for (const key of keys) {
      const value = candidate[key]
      if (typeof value === "string" && value.trim()) {
        found = value.trim()
        return
      }
    }
  })
  return found
}

export function normalizeUserCandidate(record) {
  const nickname = firstStringByKeys(record, ["nickname", "nickName", "name", "title", "displayName"])
  const userId = firstStringByKeys(record, ["userId", "user_id", "id"])
  const xsecToken = firstStringByKeys(record, ["xsecToken", "xsec_token"])
  const explicitUrl = firstStringByKeys(record, ["url", "jumpUrl", "link", "profileUrl", "profile_url"])
  const webUrl = explicitUrl && /^https?:\/\//i.test(explicitUrl) ? explicitUrl : null
  const profileUrl =
    webUrl ??
    (userId
      ? `https://www.xiaohongshu.com/user/profile/${userId}${xsecToken ? `?xsec_token=${encodeURIComponent(xsecToken)}&xsec_source=pc_search` : ""}`
      : null)

  return {
    nickname,
    userId,
    xsecToken,
    profileUrl,
    raw: record,
  }
}

export function chooseBestUser(records, query) {
  const candidates = records
    .map(normalizeUserCandidate)
    .filter((candidate) => candidate.nickname || candidate.userId || candidate.profileUrl)

  const normalizedQuery = query.trim().toLowerCase()
  const exact = candidates.find((candidate) => candidate.nickname?.trim().toLowerCase() === normalizedQuery)
  return {
    picked: exact ?? candidates[0] ?? null,
    candidates,
  }
}

export async function collectProfileNoteLinks(page) {
  return page.evaluate(() => {
    const links = Array.from(document.querySelectorAll('a[href*="/explore/"], a[href*="/discovery/item/"]'))
      .map((anchor) => ({
        href: anchor.href,
        text: (anchor.textContent ?? "").trim().replace(/\s+/g, " "),
      }))
      .filter((item) => item.href)

    const unique = []
    const seen = new Set()
    for (const link of links) {
      const normalizedHref = link.href.split("#")[0]
      if (seen.has(normalizedHref)) continue
      seen.add(normalizedHref)
      unique.push({ ...link, href: normalizedHref })
    }
    return unique.slice(0, 12)
  })
}

export async function collectProfileNotes(page, limit = 5) {
  return page.evaluate(({ maxItems }) => {
    function clean(value) {
      return value.replace(/\s+/g, " ").trim()
    }

    function normalizeUrl(value) {
      if (!value) return ""
      const trimmed = String(value).trim()
      if (!trimmed) return ""
      if (trimmed.startsWith("//")) return `${location.protocol}${trimmed}`
      return trimmed
    }

    function collectImageUrls(section) {
      const coverRoot =
        section.querySelector("a.cover") ??
        section.querySelector('[class*="cover"]') ??
        section

      const urls = Array.from(coverRoot.querySelectorAll("img"))
        .flatMap((image) => {
          const srcset = image.getAttribute("srcset") ?? ""
          return [
            image.currentSrc,
            image.getAttribute("src"),
            image.getAttribute("data-src"),
            srcset.split(",").map((item) => item.trim().split(" ")[0] ?? ""),
          ].flat()
        })
        .map(normalizeUrl)
        .filter((value) => /^https?:\/\//i.test(value))

      return [...new Set(urls)].slice(0, 9)
    }

    const items = Array.from(document.querySelectorAll("section.note-item"))
      .map((section, index) => {
        const hiddenExploreLink = section.querySelector('a[href*="/explore/"]')
        const coverLink = section.querySelector('a.cover[href]')
        const titleNode = section.querySelector(".title span, .title")
        const authorNode = section.querySelector(".author .name, .name")
        const likeNode = section.querySelector(".like-wrapper .count, .like-wrapper")
        const topNode = section.querySelector(".top-wrapper")

        const imageUrls = collectImageUrls(section)

        return {
          index,
          title: clean(titleNode?.textContent ?? ""),
          author: clean(authorNode?.textContent ?? ""),
          likeCount: clean(likeNode?.textContent ?? ""),
          isPinned: clean(topNode?.textContent ?? "") === "置顶",
          noteId:
            hiddenExploreLink?.getAttribute("href")?.match(/\/explore\/([^/?]+)/)?.[1] ??
            coverLink?.getAttribute("href")?.match(/\/user\/profile\/[^/]+\/([^/?]+)/)?.[1] ??
            "",
          noteUrl: coverLink ? new URL(coverLink.getAttribute("href"), location.origin).href : "",
          exploreUrl: hiddenExploreLink ? new URL(hiddenExploreLink.getAttribute("href"), location.origin).href : "",
          coverImageUrl: imageUrls[0] ?? "",
          imageUrls,
          rawText: clean(section.textContent ?? ""),
        }
      })
      .filter((item) => item.title)

    return items.slice(0, maxItems)
  }, { maxItems: limit })
}

export async function scrapeNotePage(context, url) {
  const page = await context.newPage()
  try {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 })
    await page.waitForTimeout(4000)
    const data = await page.evaluate(() => {
      function clean(value) {
        return value.replace(/\s+/g, " ").trim()
      }

      function normalizeUrl(value) {
        if (!value) return ""
        const trimmed = String(value).trim()
        if (!trimmed) return ""
        if (trimmed.startsWith("//")) return `${location.protocol}${trimmed}`
        return trimmed.replace(/^http:\/\//i, "https://")
      }

      function isoFromTimestamp(value) {
        if (typeof value === "number" && Number.isFinite(value)) {
          const date = new Date(value)
          if (!Number.isNaN(date.getTime())) {
            return date.toISOString()
          }
        }

        if (typeof value === "string" && value.trim()) {
          const date = new Date(value)
          if (!Number.isNaN(date.getTime())) {
            return date.toISOString()
          }
        }

        return null
      }

      function collectStateImageUrls(detailNote) {
        if (!detailNote || !Array.isArray(detailNote.imageList)) return []

        const urls = detailNote.imageList
          .map((item) => {
            const infoList = Array.isArray(item?.infoList) ? item.infoList : []
            const preferredInfoUrl =
              infoList.find((info) => info?.imageScene === "WB_DFT" && typeof info?.url === "string")?.url ??
              infoList.find((info) => info?.imageScene === "WB_PRV" && typeof info?.url === "string")?.url

            return preferredInfoUrl ?? item?.urlDefault ?? item?.urlPre ?? item?.url ?? ""
          })
          .map(normalizeUrl)
          .filter((value) => /xhscdn\.com/i.test(value))
          .filter((value) => !/avatar|user-avatar|default-avatar|fe-avatar/i.test(value))
          .filter((value) => /webpic|spectrum|sns-img|sns-webpic/i.test(value))

        return [...new Set(urls)].slice(0, 9)
      }

      function pickVideoUrl(detailNote) {
        const stream = detailNote?.video?.media?.stream
        if (!stream || typeof stream !== "object") return null

        const h264List = Array.isArray(stream.h264) ? stream.h264 : []
        const h265List = Array.isArray(stream.h265) ? stream.h265 : []
        const av1List = Array.isArray(stream.av1) ? stream.av1 : []
        const candidates = [...h264List, ...h265List, ...av1List]

        for (const item of candidates) {
          const direct = normalizeUrl(item?.masterUrl)
          if (direct) return direct

          const backup = Array.isArray(item?.backupUrls)
            ? normalizeUrl(item.backupUrls.find((url) => typeof url === "string") ?? "")
            : ""
          if (backup) return backup
        }

        return null
      }

      const noteMap = window.__INITIAL_STATE__?.note?.noteDetailMap ?? {}
      const noteEntry =
        Object.values(noteMap).find((candidate) => candidate?.note?.noteId || candidate?.note?.title) ??
        Object.values(noteMap)[0] ??
        {}
      const detailNote = noteEntry?.note ?? {}
      const stateImageUrls = collectStateImageUrls(detailNote)
      const videoUrl = pickVideoUrl(detailNote)

      const imageUrls = Array.from(
        document.querySelectorAll('img, source'),
      )
        .flatMap((node) => {
          if (node instanceof HTMLImageElement) {
            return [
              node.currentSrc,
              node.getAttribute("src"),
              node.getAttribute("data-src"),
              node.getAttribute("data-xhs-img"),
            ]
          }

          if (node instanceof HTMLSourceElement) {
            return (node.getAttribute("srcset") ?? "")
              .split(",")
              .map((item) => item.trim().split(" ")[0] ?? "")
          }

          return []
        })
        .map(normalizeUrl)
        .filter((value) => /xhscdn\.com/i.test(value))
        .filter((value) => !/avatar|user-avatar|default-avatar|fe-avatar/i.test(value))
        .filter((value) => /webpic|spectrum|sns-img|sns-webpic/i.test(value))
        .filter((value, index, values) => values.indexOf(value) === index)
        .slice(0, 9)

      const title =
        clean(detailNote.title ?? "") ||
        document.querySelector('meta[property="og:title"]')?.getAttribute("content")?.trim() ||
        document.title.trim()

      const metaDescription =
        document.querySelector('meta[name="description"]')?.getAttribute("content")?.trim() ?? ""

      const description = clean(detailNote.desc ?? "") || metaDescription

      const textCandidates = Array.from(
        document.querySelectorAll('article, main, section, [class*="desc"], [class*="content"], [class*="note"]'),
      )
        .map((element) => clean(element.textContent ?? ""))
        .filter(Boolean)
        .filter((value, index, values) => value.length > 20 && values.indexOf(value) === index)
        .sort((left, right) => right.length - left.length)

      const domAuthor =
        Array.from(document.querySelectorAll('[class*="author"], [class*="user"], a[href*="/user/profile/"]'))
          .map((element) => clean(element.textContent ?? ""))
          .find(Boolean) ?? ""

      const author = clean(detailNote.user?.nickname ?? "") || domAuthor

      return {
        title,
        description,
        author,
        content: clean(detailNote.desc ?? "") || textCandidates[0] || description,
        imageUrls: stateImageUrls.length > 0 ? stateImageUrls : imageUrls,
        videoUrl,
        publishedAt: isoFromTimestamp(detailNote.time) ?? isoFromTimestamp(detailNote.lastUpdateTime),
        noteType: typeof detailNote.type === "string" ? detailNote.type : null,
        textCandidates: textCandidates.slice(0, 5),
      }
    })

    return {
      url,
      ...data,
    }
  } finally {
    await page.close()
  }
}

export async function writeOutputFile(prefix, payload) {
  await ensureLocalDirs()
  const safePrefix = prefix.replace(/[^\w\u4e00-\u9fa5-]+/g, "-")
  const filePath = path.join(OUTPUT_DIR, `${safePrefix}-${Date.now()}.json`)
  await fs.writeFile(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8")
  return filePath
}
