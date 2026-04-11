import { defaultNewsFeeds, parseFeedsFromBody, parseRssItems, topNewsSummaryBlock } from "./news.ts"

Deno.test("parseRssItems extracts normalized RSS entries", () => {
  const xml = `
    <rss>
      <channel>
        <item>
          <title><![CDATA[Markets rally after AI earnings beat]]></title>
          <link>https://example.com/markets-rally</link>
          <guid>story-1</guid>
          <description><![CDATA[Stocks jump after strong AI infrastructure demand.]]></description>
          <pubDate>Sat, 11 Apr 2026 10:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
  `

  const items = parseRssItems(xml)
  if (items.length !== 1) {
    throw new Error(`Expected 1 RSS item, got ${items.length}`)
  }

  if (items[0].title !== "Markets rally after AI earnings beat") {
    throw new Error(`Unexpected title: ${items[0].title}`)
  }

  if (items[0].link !== "https://example.com/markets-rally") {
    throw new Error(`Unexpected link: ${items[0].link}`)
  }
})

Deno.test("parseFeedsFromBody falls back to defaults and accepts valid custom feeds", () => {
  const defaultFeeds = parseFeedsFromBody({})
  if (defaultFeeds.length !== defaultNewsFeeds.length) {
    throw new Error("Expected default feed definitions when body has no custom feeds")
  }

  const customFeeds = parseFeedsFromBody({
    feeds: [{
      slug: "custom-tech",
      url: "https://example.com/rss.xml",
      sourceName: "Example",
      category: "tech",
    }],
  })

  if (customFeeds.length !== 1 || customFeeds[0].slug !== "custom-tech") {
    throw new Error("Expected custom feed definition to be parsed")
  }
})

Deno.test("topNewsSummaryBlock renders rank and tags", () => {
  const summary = topNewsSummaryBlock([{
    id: "event-1",
    title: "Open-source model demand surges",
    summary: "Summary",
    category: "tech",
    interest_tags: ["global", "tech", "ai"],
    representative_url: "https://example.com/story",
    representative_source_name: "Example",
    importance_score: 4.2,
    global_rank: 1,
    is_global_top: true,
    published_at: "2026-04-11T10:00:00Z",
  }])

  if (!summary.includes("#1 Open-source model demand surges [tech, ai]")) {
    throw new Error(`Unexpected summary block: ${summary}`)
  }
})
