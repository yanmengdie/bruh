## 重构 Todo

### 原则

- 默认先做内部重构，不改用户界面。
- 任何会影响用户可见页面、入口、流程、文案、交互的改动，先确认再做。
- 先稳定结构，再继续加功能。
- 先处理单一真相源、模块边界、契约稳定，再做性能、美化和新能力扩展。

### P0 结构稳定

- [x] 收口启动与 seed 逻辑，统一 bootstrap 入口，消除重复初始化。
  已完成：新增 `AppBootstrapper`，统一本地 seed、content graph sync、thread prepare 和远端 starter refresh 入口，移除 `bruhApp` 与 `FeedView` 的重复启动逻辑。
- [x] 拆分 `ContentView.swift` 的职责，只保留 app shell 和导航，不改现有界面表现。
  已完成：拆出 `ContactsView`、`AlbumView`、`SettingsScreen`，`ContentView` 只保留 onboarding gate、导航、badge 计算和 bootstrap hook。
- [x] 统一消息与内容的单一真相源，梳理 `MessageThread`、`PersonaMessage`、`ContentDelivery` 的边界。
  已完成：新增 `ContentGraphSelectors`，统一 accepted contact、message delivery、album delivery 的可见性过滤，`ContentView`、`MessagesScreen`、`AlbumView` 已改为复用同一套规则。
- [x] 把 demo、seed、fallback 逻辑从运行时主链路里剥离，避免线上逻辑和演示逻辑混杂。
  已完成：新增 `AppRuntimeOptions`，把 bundled moments、demo invite order、local starter fallback、message demo artifact、local feed interaction fallback 收口成显式运行时开关；当前 Debug 默认保留现状，Release 默认关闭。
- [x] 核对客户端和后端契约，补齐缺失接口、清理漂移字段。
  已完成：已核对 `feed`、`generate-message`、`message-starters`、`generate-post-interactions` 四条客户端链路，补了更明确的 HTTP/解码错误、历史字段兼容和缺省值兜底，并删除了客户端里无实现也无调用的 `generateAvatar` 死接口。
- [x] 产出一份项目架构说明，明确 persona、content graph、iOS app、backend pipeline 的模块边界。
  已完成：新增 `docs/architecture.md`，明确 shared persona catalog、iOS app layer、local content graph、Supabase backend pipeline 的职责和数据流。

### P1 核心链路收敛

- [x] 拆 `generate-message/index.ts`，把 prompt assembly、news context selection、fallback policy、TTS orchestration、retry 逻辑拆开。
  已完成：新增 `helpers.ts`、`types.ts`、`prompting.ts`、`providers.ts`、`voice.ts`、`fallbacks.ts`，主文件只保留 request parsing、Supabase 读取和 response 编排；同时补上 `deno check supabase/functions/generate-message/index.ts` 校验。
- [x] 拆 `message-starters/index.ts`，把兴趣归一化、候选筛选、图片事件选择、source URL 决策、fallback text 生成分层。
  已完成：新增 `supabase/functions/message-starters/generation.ts`、`selection.ts`、`types.ts`，主文件只保留 request parsing、数据读取和 response assembly；同时修复了仅配置 OpenAI 时直接跳过 starter text 生成、以及 Anthropic 单次异常会中断整批 starter 生成的兜底问题，并补上 `deno check supabase/functions/message-starters/index.ts` 校验。
- [x] 给 `SharedPersonas.json` 加 schema 校验，保证 Swift 和 TypeScript 端一致。
  已完成：新增 `schemas/shared-personas.schema.json` 作为共享 schema，后端通过 `supabase/functions/_shared/persona_catalog_schema.ts` 在启动时校验 persona catalog，iOS 端新增 `PersonaCatalogValidator` 并在 `Persona.loadEntries()` 解码后强校验，保证 Swift 和 TypeScript 读取同一份结构约束。
- [x] 清理 `APIClient.swift` 的硬编码配置，改成环境注入，并核对未落地接口和漂移契约。
  已完成：新增 `APIClientConfiguration`，把 functions base URL 和 anon key 收口到环境变量与 `Info.plist` 注入，支持 `BRUH_FUNCTIONS_BASE_URL`、`SUPABASE_FUNCTIONS_BASE_URL`、`BRUH_SUPABASE_ANON_KEY`、`SUPABASE_ANON_KEY` 四个入口；同时把 `errorCategory` 纳入 `NetworkError` 和 DTO 解码，补齐后端错误分类契约。
- [x] 给核心链路补最小测试：DTO contract、content graph reconciliation、message fallback、ingestion smoke test。
  已完成：补充 `persona_catalog_schema_test.ts`、`news_test.ts`、`fallbacks_test.ts` 三个 Deno 测试，以及 `scripts/api_contract_smoke.swift`、`scripts/content_graph_smoke.swift` 两个 Swift smoke 脚本，并新增 `scripts/run_p1_validation.sh` 一键跑通最小验证链路。
- [x] 增加后端日志和错误分类，建立最基本的可观测性。
  已完成：新增 `supabase/functions/_shared/observability.ts`，为 `generate-message` 和 `message-starters` 增加 `requestId`、成功/失败结构化日志及 `errorCategory` 返回，便于后续按链路归因和统计异常类型。
- [x] 明确数据库表职责，梳理 `source_posts`、`feed_items`、`news_events`、`persona_news_scores` 的写入和消费关系。
  已完成：在 `docs/architecture.md` 补充 `5. Backend Storage Responsibilities`，明确各表的生产者、消费者、生命周期和职责边界，减少后续 ingestion/feed/message 链路继续耦合。

### P2 工程化补强

- [x] 建立环境分层，拆开 `dev`、`staging`、`prod` 的 API、Supabase 和开关配置，避免实验链路污染正式链路。
  已完成：iOS 端新增 `AppEnvironment`，把 `APIClientConfiguration` 和 `AppRuntimeOptions` 改成按 `BRUH_APP_ENV` 解析环境并优先读取 `KEY__ENV`；Xcode Debug/Release 默认环境分别显式落为 `dev` / `prod`。Supabase Edge Functions 新增 `_shared/environment.ts`，统一使用 `KEY__ENV -> KEY` 的读取顺序，覆盖 Supabase、LLM、TTS、Apify 等关键配置；`scripts/ingest_x.py` 已去掉硬编码 prod 凭据并切到同一套规则；新增 `docs/environment-setup.md` 说明接入方式。
- [x] 建立 SwiftData migration 策略，避免未来模型变更带来数据损坏。
  已完成：新增 `BruhSchemaV1`、`BruhSchemaMigrationPlan` 和 `BruhModelStore`，把主 `ModelContainer` 切到显式版本化 schema 与 migration 入口；容器启动失败时会先备份 `default.store` 及其 `shm/wal` 文件，再执行恢复，不再直接无痕删库；新增 `docs/swiftdata-migrations.md` 记录后续 schema 演进规则与发布约束。
- [x] 统一 cron、幂等性和重试策略，保证 ingestion 和 build pipeline 可重复执行且结果稳定。
  已完成：新增 `pipeline_job_locks` 迁移和 `claim_pipeline_job` / `complete_pipeline_job` RPC，`build-feed`、`ingest-top-news`、`build-news-events`、`ingest-x-posts` 现在会先抢数据库锁再运行，重复触发时直接返回 `already_running`；相关写路径继续使用 `upsert` 保证重复执行稳定，失败后通过 TTL 和下一次 cron tick 或手动重跑完成基线重试；新增 `docs/pipeline-jobs.md` 说明当前 job 与运行约定。
- [x] 建立最小 CI/CD，至少覆盖 iOS build、函数类型检查、关键 smoke test。
  已完成：新增 `.github/workflows/ci.yml`，把最小工程校验收口为两条 job：`backend-validation` 负责 Edge Functions 的 `deno check` 与关键 Deno 测试，`ios-validation` 负责 `xcodebuild` 和 `./scripts/run_p1_validation.sh` smoke 验证；同一套验证也已同步到本地脚本，保证本地和 CI 不再各跑各的。
- [x] 增加 feature flag，方便后续灰度 persona、排序、starter 策略。
  已完成：新增 `supabase/functions/_shared/feature_flags.ts` 和 `feature_flags_test.ts`，统一解析 `BRUH_ENABLED_PERSONA_IDS`、`BRUH_STARTER_SELECTION_STRATEGY`、`BRUH_STARTER_IMAGE_MODE`、`BRUH_STARTER_SOURCE_URL_MODE`、`BRUH_FEED_READ_SOURCE`、`BRUH_FEED_RANKING_STRATEGY` 六类后端 feature flag，默认值保持现状不变；`build-news-events`、`message-starters`、`feed` 已接入该层，支持 persona allowlist、starter 策略回退、feed 数据源切换和排序实验；新增 `docs/feature-flags.md` 说明 rollout 方式。
- [x] 增加成本控制和降级策略，覆盖 LLM、TTS、抓取链路。
  已完成：新增 `supabase/functions/_shared/cost_controls.ts` 和 `cost_controls_test.ts`，统一解析 `BRUH_LLM_GENERATION_MODE`、`BRUH_TTS_MODE`、`BRUH_TTS_MAX_CHARACTERS`、`BRUH_MESSAGE_IMAGE_MODE`、`BRUH_X_INGEST_MODE`、`BRUH_X_INGEST_MAX_USERNAMES_PER_RUN`、`BRUH_X_INGEST_MAX_POSTS_PER_USER` 七类成本控制开关；`generate-message` 现在支持 LLM fallback-only、TTS 降级和消息图片 kill switch，`message-starters` 支持直接退回 deterministic starter 文案，`ingest-x-posts` 支持整条抓取链路停用和硬限流；新增 `docs/cost-controls.md` 说明降级策略和 rollout 示例。
- [x] 做安全清理、数据生命周期治理和开发文档沉淀。
  已完成：新增 `scripts/check_sensitive_strings.sh` 并接入 CI 与本地验证脚本，建立最小 secret hygiene 基线；新增 `supabase/migrations/0019_backend_retention_cleanup.sql`，提供 service-role 手动执行的 `run_backend_retention_cleanup(...)` 清理入口，覆盖 `source_posts/feed_items`、`news_events/persona_news_scores/news_event_articles`、`news_articles`、`pipeline_job_locks` 四类后端数据；新增 `docs/security-and-lifecycle.md`，把安全约束、保留窗口和清理 runbook 沉淀下来。

### P3 系统可持续运行

- [x] 建立环境分层的完整策略，把 `dev`、`staging`、`prod` 的配置、数据源和密钥管理彻底拆开。
  已完成：已在 P2 落地 `AppEnvironment`、后端 `_shared/environment.ts` 和 `docs/environment-setup.md`，客户端、Edge Functions 和运维脚本已统一按 `KEY__ENV -> KEY` 解析环境配置。
- [x] 做 SwiftData 的正式迁移设计，包括版本演进、迁移失败回滚和旧数据兼容策略。
  已完成：已在 P2 落地 `BruhSchemaV1`、`BruhSchemaMigrationPlan`、`BruhModelStore` 与 `docs/swiftdata-migrations.md`，容器启动失败时会先备份再恢复，不再直接无痕删库。
- [x] 清理数据库职责边界，明确 `source_posts`、`feed_items`、`news_events`、`persona_news_scores` 分别是谁写、谁读、谁回收。
  已完成：已在 P1 的 `docs/architecture.md` 中补齐 backend storage responsibilities，明确各表的生产者、消费者、生命周期和回收责任。
- [x] 统一定时任务和幂等性，让所有 ingestion 和 build function 都可以安全重复执行。
  已完成：已在 P2 落地 `pipeline_job_locks`、`claim_pipeline_job` / `complete_pipeline_job` 与相关 runbook，主要 pipeline job 已具备锁保护、幂等 upsert 和 TTL 失效恢复。
- [x] 给媒体链路补规范，统一图片、视频、语音的 URL、缓存、失效和失败回退策略。
  已完成：新增 `supabase/functions/_shared/media.ts` 和 `media_test.ts`，统一 source link 与 image/video/audio asset 的 URL 规范；`ingest-top-news`、`ingest-x-posts`、`build-feed`、`feed`、`generate-message`、`message-starters` 已接入该层，确保不安全协议、私网地址、重复媒体和坏链接在入库或出参前被剔除。iOS 端新增 `RemoteMediaPolicy`，在 DTO 解码和 Feed/Message 渲染阶段再次收口媒体 URL；语音播放仍保留现有 UI，但现在明确了本地缓存、坏缓存删除后重试一次、最终失败保留文本内容的回退策略。新增 `docs/media-policy.md` 记录规则。

### P4 平台化与成本控制

- [x] 建立 CI/CD 最小流水线，至少包含 iOS build、函数 lint 或类型检查、核心 smoke test 和 deploy check。
  已完成：已在 P2 落地 `.github/workflows/ci.yml`，并新增 shell 语法校验；当前 CI 覆盖 secret scan、shell syntax、Deno check/test、iOS build 和 `run_p1_validation.sh`。
- [x] 增加 feature flag 和灰度能力，后续改 persona 策略、feed 排序、starter 逻辑时不要直接硬切。
  已完成：已在 P2 落地 `_shared/feature_flags.ts`、相关测试和 `docs/feature-flags.md`，当前 feed / starter / persona rollout 已支持按环境和策略灰度。
- [x] 加成本控制，给 LLM、TTS、抓取链路增加调用统计、限额和降级策略。
  已完成：已在 P2 落地 `_shared/cost_controls.ts`、相关测试和 `docs/cost-controls.md`，消息、starter 和 X ingestion 已接入成本开关与降级模式。
- [x] 做错误恢复机制，消息发送失败、starter 拉取失败、feed 构建失败，都要有统一 retry 和 fallback policy。
  已完成：iOS 端在 `APIClient` 新增统一 `NetworkRetryPolicy`，把 `feed`、`message-starters`、`generate-message`、`generate-post-interactions` 四条链路收口到同一套瞬时失败判定和退避重试规则；仅对 timeout / network / provider / unknown 与 `408/429/500/502/503/504` 做有限重试，`validation/auth/config/database` 继续立即失败，避免误重试。`MessageService.refreshStarterMessages()` 现在会返回远端刷新结果，`AppBootstrapper` 改成只有远端成功才标记 starter 已加载，失败后保留本地 seed 并设置 20 秒冷却后可再次拉取，修复原来“一次失败整次会话都不再重试”的问题。后端 `feed` / `build-feed` 已补 `errorCategory` 和结构化日志，方便客户端和 cron 链路做更准确的恢复判断；新增 `docs/error-recovery.md` 记录当前策略。
- [x] 建立接口版本约束，DTO 一旦变更要有兼容策略，不能依赖前后端同步上线。
  已完成：新增 `supabase/functions/_shared/api_contract.ts`，为 `feed`、`generate-message`、`message-starters`、`generate-post-interactions` 四条 app-facing Edge Function 统一返回 `X-Bruh-Server-Version`、`X-Bruh-Contract`、`X-Bruh-Compat-Mode`，并接受客户端的 `X-Bruh-Client-Version`、`X-Bruh-Accept-Contract`；客户端 `APIClient` 现在会为每条请求声明期望 contract，并在成功响应时校验服务端实际 contract，防止错接到不兼容 payload。iOS 端 DTO decoder 同时补上 camelCase / snake_case 和少量历史字段别名兼容，例如消息 `content/text`、starter `sourceUrl/articleUrl`、`topSummary/top_summary`，避免前后端非同步发布时直接解码失败；新增 `docs/api-versioning.md`、`api_contract_test.ts` 和扩展后的 `scripts/api_contract_smoke.swift` 作为最小契约回归基线。

### P5 长期治理

- [x] 做安全治理，清理硬编码配置，检查脚本里潜在敏感信息，梳理 publishable key 和内部服务边界。
  已完成：前面阶段已经去掉 `scripts/ingest_x.py` 的硬编码 prod 凭据并建立 `check_sensitive_strings.sh`，本轮继续补上 `scripts/check_client_boundary.sh`，专门扫描 `bruh/` 和 `bruh.xcodeproj/project.pbxproj`，阻止 `SERVICE_ROLE_KEY`、`OPENAI_API_KEY`、`ANTHROPIC_API_KEY`、`VOICE_API_KEY`、`NANO_BANANA_API_KEY`、`APIFY_TOKEN` 等服务端密钥或 provider 凭据进入 iOS app surface；同时在 `docs/security-and-lifecycle.md` 明确只有 publishable / anon Supabase key 可以出现在客户端，其余密钥必须留在 backend。该检查已接入本地验证脚本和 CI。
- [x] 做内容治理和风控，生成内容、persona 回复、外部抓取内容都加最基础的审核和异常拦截层。
  已完成：新增 `supabase/functions/_shared/content_safety.ts` 和 `content_safety_test.ts`，统一清理控制字符、普通 HTML、危险脚本/markup、明显 prompt injection 和模型自我泄露语句；`generate-message`、`message-starters`、`generate-post-interactions` 现在会在返回前先过共享安全层，命中异常时回退到现有 deterministic fallback，不改 UI。`ingest-top-news`、`ingest-x-posts`、`ingest-xhs-posts` 也已在入库前接入同一套规则，遇到危险内容直接拦截，普通脏数据则做裁剪/清洗并记录结构化日志；新增 `docs/content-governance.md` 说明策略，并把测试接入 CI 与本地验证脚本。
- [x] 做归档与数据生命周期治理，明确旧 feed、旧事件、旧媒体、旧日志保留多久、何时清理。
  已完成：前面阶段已新增 `supabase/migrations/0019_backend_retention_cleanup.sql` 和 `docs/security-and-lifecycle.md`，明确 `source_posts/feed_items`、`news_events/persona_news_scores/news_event_articles`、`news_articles`、`pipeline_job_locks` 的保留窗口与手动清理入口 `run_backend_retention_cleanup(...)`；当前策略是先保守落人工 cleanup runbook，再根据线上运行情况决定是否接 cron，生命周期基线已建立。
- [x] 做开发者文档，补齐架构、数据流、cron 流、部署方式、persona 配置规则，让后续协作成本下降。
  已完成：目前已沉淀 `docs/architecture.md`、`environment-setup.md`、`swiftdata-migrations.md`、`pipeline-jobs.md`、`feature-flags.md`、`cost-controls.md`、`media-policy.md`、`error-recovery.md`、`api-versioning.md`、`security-and-lifecycle.md`、`content-governance.md` 等文档，分别覆盖模块边界、环境分层、迁移、cron/幂等、灰度、成本控制、媒体规范、错误恢复、契约治理、安全/生命周期和内容风控，P5 文档基线已足够支撑后续协作。

### P6 运维可观测性

- [x] 统一 requestId、结构化起止日志和耗时指标，覆盖 app-facing function 与 pipeline job。
  已完成：扩展 `supabase/functions/_shared/observability.ts`，新增 `createObservationContext`、`responseHeadersWithRequestId`、`logEdgeStart`、`logEdgeSuccess`、`logEdgeFailure`，统一产出 `request_started/request_succeeded/request_rejected/request_failed` 和 `job_started/job_skipped/job_succeeded/job_failed` 事件，并附带 `durationMs`。`feed`、`generate-message`、`message-starters`、`generate-post-interactions` 现在都会通过 `X-Bruh-Request-Id` 暴露请求 ID；`build-feed`、`build-news-events`、`ingest-top-news`、`ingest-x-posts`、`ingest-xhs-posts` 也已接入同一套 job 观测层。新增 `docs/observability.md` 和 `observability_test.ts`，并接入 CI 与本地验证脚本。
- [x] 增加后台健康快照/诊断脚本，能快速看 cron、ingestion、feed build 是否卡住或退化。
  已完成：新增 `scripts/backend_health_snapshot.ts` 和 `backend_health_snapshot_lib.ts`，通过 service-role 只读查询 `pipeline_job_locks`、`news_articles`、`news_events`、`persona_news_scores`、`feed_items`、`source_posts`，输出统一的 `healthy/running/degraded/stale/failed/error/unknown` 健康结论，并附带 freshness、最近成功时间、最近错误、总量和 recent-window 计数；支持 `--json` 和 `--strict`，便于人工排障和自动化巡检。新增 `scripts/backend_health_snapshot_test.ts`，并把它接入 CI、本地验证脚本与 `docs/observability.md` / `docs/environment-setup.md`。
- [x] 增加 provider 维度的失败率、fallback 率和耗时统计，方便判断模型/语音/抓取供应商是否不稳定。
  已完成：新增 `supabase/functions/_shared/provider_metrics.ts` 和 `provider_metrics_test.ts`，统一产出 `provider_metric` 结构化事件，标准字段覆盖 `operation`、`provider`、`outcome`、`durationMs` 以及请求上下文。`generate-message`、`message-starters`、`generate-post-interactions`、`ingest-x-posts` 现在都已接入 provider 级 success/failure/fallback/skipped 指标，覆盖 LLM、图片、语音和 Apify actor fallback 链路；同时补齐 `docs/observability.md` 中的 provider 查询说明，并接入 CI 与本地验证脚本。
- [x] 增加发布前 preflight/runbook，把环境变量、关键表、函数契约、最小 smoke 验证收口成一次性检查。
  已完成：新增 `scripts/release_preflight.ts`、`release_preflight_lib.ts`、`release_preflight_test.ts` 和 `run_release_preflight.sh`，把环境变量解析、关键表探测、后台健康快照、契约/smoke 验证收口成单次发布前检查；支持 `--strict` / `--json`，并新增 `docs/release-preflight.md` 记录操作 runbook。对应测试已接入 CI 和本地验证脚本。
- [x] 给 operator 脚本补本地 env loader 和模板，降低 preflight / 健康巡检的启动成本。
  已完成：新增 `scripts/load_env.sh`，统一为 `run_release_preflight.sh` 和新增的 `run_backend_health_snapshot.sh` 自动加载 `.env`、`.env.local`、`.env.<env>`、`.env.<env>.local`，并打印实际加载的本地配置文件，方便排查“为什么 preflight 读不到环境变量”。同时新增 `scripts/preflight.env.template` 作为可复制的本地模板，并把 shell 语法检查接入 CI 与本地验证脚本；`docs/environment-setup.md`、`docs/release-preflight.md`、`docs/observability.md` 也已同步更新 runbook。

### P7 后端互动链路继续收敛

- [x] 拆 `generate-post-interactions/index.ts` 的基础层，把 types、helpers、fallback 文本和 storage mapping 从 handler 中分离。
  已完成：新增 `supabase/functions/generate-post-interactions/types.ts`、`helpers.ts`、`fallbacks.ts`、`storage.ts`，把字符串清洗、fallback 回复、legacy comment 归一化、transient/stored state 映射和 Supabase 持久化从主 handler 移出，`index.ts` 现在更聚焦在 ranking、provider orchestration 和 request flow；同时新增 `fallbacks_test.ts` 并接入 CI 与本地验证脚本。
- [x] 继续拆 `generate-post-interactions` 的 provider orchestration，把 Anthropic/OpenAI fallback 与 stateless/persistent 分支收口成独立模块。
  已完成：新增 `supabase/functions/generate-post-interactions/selection.ts`、`providers.ts`、`handlers.ts`，把 ranking 选择、provider 生成与 Anthropic/OpenAI fallback、以及 stateless/persistent 两条请求分支从主入口拆出；`index.ts` 已收口为 request parsing、环境解析和响应包装入口，文件从 1700+ 行降到约 200 行，同时保持现有行为不变。对应改动已通过 `deno check`、`generate-post-interactions/fallbacks_test.ts` 和完整 `run_p1_validation.sh`。
- [x] 拆 `MessageService.swift` 的 thread/store/starter lifecycle，把远端同步、本地 fallback、去重和 thread 更新拆层。
  已完成：新增 `bruh/Services/MessageThreadStore.swift`，收口 accepted persona 查询、thread ensure、recent conversation、starter/message artifact 查询与 unread 计算；新增 `bruh/Services/StarterMessageLifecycle.swift`，收口远端 starter 同步、本地 fallback seed、starter 去重归一和 demo 注入；`MessageService.swift` 现在只保留 prepare/refresh/send/read 等公共编排接口，不改现有消息链路与 UI 行为。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `FeedInteractionService.swift` 的本地生成与持久化边界，减少 service 内的规则、fallback 和 store 逻辑耦合。
  已完成：新增 `bruh/Services/FeedInteractionStore.swift`，收口 likes/comments/seed-state 的查询、upsert、remote DTO 映射、reply target 解析和持久化保存；新增 `bruh/Services/FeedLocalInteractionGenerator.swift`，收口 deterministic 本地 seed/reply 生成规则；`FeedInteractionService.swift` 现在只保留 seed orchestration、viewer comment/like 提交和 remote/local fallback 编排，不改 feed UI 与互动行为。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。

### P8 客户端核心边界继续收敛

- [x] 拆 `SourceItem.swift`，把 `ContentGraphStore` 写侧同步逻辑从内容图模型定义里分离，避免 model file 同时承担 schema 与存储编排。
  已完成：新增 `bruh/Models/ContentGraphStore.swift`，把 feed/message 的 content graph sync、backfill、source/event/delivery upsert 和 preview/url 归一化逻辑从 `SourceItem.swift` 分离；`SourceItem.swift` 现在只保留 `SourceItem` / `ContentEvent` / `ContentDelivery` 及其枚举扩展。同步补齐 `scripts/run_p1_validation.sh` 的 smoke 编译输入，确保 `content_graph_smoke.swift` 继续覆盖新边界。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `APIClient.swift` 的 transport、contract/header、DTO mapping 边界，减少单文件协议和接口耦合。
  已完成：新增 `bruh/Networking/NetworkSupport.swift`，收口 `RemoteMediaPolicy`、`NetworkError`、API contract header 校验和 retry policy；新增 `bruh/Networking/APIClientDTOs.swift`，收口 feed/message/starter/interaction 全部 DTO 和兼容解码规则；`APIClient.swift` 现在只保留 session 初始化、请求发送、错误包装和 endpoint 编排。同步更新 `scripts/run_p1_validation.sh` 的 API contract smoke 编译输入，确保分层后脚本仍覆盖契约兼容性。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `Persona.swift` 的 persona catalog 资源加载、排序策略与 `Persona` / `Contact` 模型边界，降低模型文件体积和资源耦合。
  已完成：新增 `bruh/Models/PersonaCatalog.swift`，把 persona 资源解码、bundle 加载、invite 排序和 catalog lookup 逻辑从 `Persona.swift` 分离；`Persona.swift` 现在只保留 `Persona` / `UserProfile` / `Contact` 的 SwiftData 模型和 `CurrentUserProfileStore`。同步更新工程文件，确保新 catalog 文件进入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `SeedData.swift` 的 persona/contact 引导写入、demo feed seed、`pengyou` seed catalog 与 legacy invite 迁移逻辑，避免单文件同时承担数据定义、迁移和写侧编排。
  已完成：`SeedData.swift` 现在只保留轻量 bootstrap 入口；新增 `bruh/Models/PersonaSeedStore.swift` 收口 persona/contact 写侧编排与 retired 数据清理，新增 `bruh/Models/ContactInviteSeedSupport.swift` 收口 invite 迁移和联系人目录 helper，新增 `bruh/Models/DemoFeedSeedStore.swift` 收口 demo post seed，新增 `bruh/Models/PengyouMomentSeedStore.swift` 收口 `pengyou` seed catalog 与导入逻辑。同步更新工程文件，把新模型文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `FeedLocalInteractionGenerator.swift` 的候选选择、文案模板和 fallback 评分逻辑，降低本地互动生成器的规则耦合，给后续测试补点留下稳定边界。
  已完成：`FeedLocalInteractionGenerator.swift` 现在只保留 seed/reply 两个入口；新增 `bruh/Services/FeedInteractionCandidateRanker.swift` 收口 persona 候选排序、mention/social-circle 匹配和稳定 hash，新增 `bruh/Services/FeedInteractionCommentTemplates.swift` 收口 seed/reply 评论模板、cue 提取、语言判断和低信号 fallback 规则。同步更新工程文件，把两个 helper 文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `StarterMessageLifecycle.swift` 的远端 starter 同步、fallback seed、starter 去重归一化与 artifact 清理逻辑，降低消息首条生命周期编排的职责耦合。
  已完成：`StarterMessageLifecycle.swift` 现在只保留依赖注入与结构体定义；新增 `bruh/Services/StarterMessageRemoteSync.swift` 收口远端 starter 拉取和线程预览刷新，新增 `bruh/Services/StarterMessageFallbackSeeder.swift` 收口 fallback starter seed 与 Trump web preview demo 注入，新增 `bruh/Services/StarterMessageNormalizer.swift` 收口 starter 去重合并、评分选择和 artifact 清理。同步更新工程文件，把扩展文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `FeedInteractionStore.swift` 的 SwiftData 读写、reply target 归一化与远端 DTO 映射/apply 逻辑，降低互动状态存储层的职责耦合。
  已完成：`FeedInteractionStore.swift` 现在只保留 interaction seed state、like/comment 的 SwiftData 查询与 upsert；新增 `bruh/Services/FeedInteractionRemoteStateBridge.swift` 收口 reply target 归一化、primary responder 选择、request DTO 映射和 remote interaction state apply。同步更新工程文件，把 bridge 文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `NetworkSupport.swift` 的媒体 URL 规范化、API contract/header 校验与 retry policy 逻辑，降低网络基础支持层的规则耦合。
  已完成：`NetworkSupport.swift` 现在只保留 `NetworkError`；新增 `bruh/Networking/RemoteMediaPolicy.swift` 收口媒体 URL 归一化与私网/loopback 过滤，新增 `bruh/Networking/APIContract.swift` 收口 request header 注入与 contract 校验，新增 `bruh/Networking/NetworkRetryPolicy.swift` 收口 retry profile 与错误重试规则。同步更新 `scripts/run_p1_validation.sh` 的 networking smoke 编译输入，并把新文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `Persona.swift` 的 `CurrentUserProfileStore`、interest 归一化与 legacy preference 迁移 helper，降低模型定义与用户配置写侧逻辑的耦合。
  已完成：新增 `bruh/Models/CurrentUserProfileStore.swift`，把 `CurrentUserProfileStore`、interest 去重归一化、legacy onboarding interest 迁移和 `bruhHandle` 生成逻辑从 `Persona.swift` 分离；`Persona.swift` 现在只保留 `Persona` / `UserProfile` / `Contact` 模型定义及其轻量扩展。同步更新工程文件，把新 store 文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `PersonaCatalog.swift` 的 bundle 资源加载、catalog lookup 与 invite ranking 策略，降低 persona 资源解析与排序规则耦合。
  已完成：新增 `bruh/Models/PersonaCatalogStore.swift` 收口 `SharedPersonas.json` 的 bundle 发现、资源解码、schema 校验和 catalog lookup，新增 `bruh/Models/PersonaCatalogInviteRanker.swift` 收口 interest 命中排序、lead persona 选择与 invite order map 生成；`PersonaCatalog.swift` 现在只保留 `PersonaPlatformAccount` / `PersonaCatalogEntry` 模型定义和 facade 入口。同步更新工程文件，把新 helper 文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `ContentGraphStore.swift` 的 feed/message 同步编排、delivery upsert 与 preview/url 归一化 helper，降低内容图存储层职责耦合。
  已完成：新增 `bruh/Models/ContentGraphStoreSupport.swift` 收口 content graph 的 fetch helper、preview 文本生成、URL 提取和去重归一化规则；新增 `bruh/Models/ContentGraphFeedSync.swift` 收口 feed post 的 source/event/delivery 同步；新增 `bruh/Models/ContentGraphMessageSync.swift` 收口 incoming message 与 album delivery 的 event/delivery 同步；`ContentGraphStore.swift` 现在只保留 backfill 入口。同步更新工程文件和 `scripts/run_p1_validation.sh` 的 smoke 编译输入，确保新边界继续被验证。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `APIClientDTOs.swift` 的 feed/message/starter/interaction DTO 与兼容解码 helper，降低网络契约文件体积和跨接口耦合。
  已完成：`APIClientDTOs.swift` 现在只保留共享解码 helper 和 `APIErrorResponseDTO`；新增 `bruh/Networking/APIClientFeedDTOs.swift` 收口 feed DTO，新增 `bruh/Networking/APIClientMessageDTOs.swift` 收口 message/starter DTO，新增 `bruh/Networking/APIClientInteractionDTOs.swift` 收口 interaction request/reply DTO 与兼容解码。同步更新工程文件和 `scripts/run_p1_validation.sh` 的 API contract smoke 编译输入，确保拆分后契约校验持续有效。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `PengyouMomentSeedStore.swift` 的 seed catalog、媒体/时间归一化与 SwiftData 写入编排，降低 demo moments 导入链路的单文件职责耦合。
  已完成：新增 `bruh/Models/PengyouMomentSeedCatalog.swift` 收口 `pengyou` moments 静态 seed catalog，新增 `bruh/Models/PengyouMomentSeedSupport.swift` 收口 ISO8601 时间解析和媒体字段归一化，新增 `bruh/Models/PengyouMomentSeedWriter.swift` 收口 SwiftData 的删旧、upsert 和保存逻辑；`PengyouMomentSeedStore.swift` 现在只保留 seed 入口。同步更新工程文件，把新模型文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `PersonaSeedStore.swift` 的 persona seed 写入、retired persona 清理与 system contact/demo invite 编排，降低 seed 写侧入口的职责耦合。
  已完成：新增 `bruh/Models/PersonaCatalogSeedWriter.swift` 收口 persona catalog seed 写入，新增 `bruh/Models/PersonaRetirementCleaner.swift` 收口 retired persona 及关联数据清理，新增 `bruh/Models/SystemContactSeedWriter.swift` 收口 system contact 同步与 demo invite order 重置；`PersonaSeedStore.swift` 现在只保留顶层 seed 入口并委托给各自 helper。同步更新工程文件，把新模型文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `MessageThreadStore.swift` 的 thread query、消息预览/support helper 与 read state 计算逻辑，降低消息存储层与消息展示规则耦合。
  已完成：新增 `bruh/Services/MessageServiceSupport.swift` 收口 starter id/text、音频可播放判断和消息 preview 生成逻辑，新增 `bruh/Services/MessageThreadReadState.swift` 收口线程已读标记与 unread 计数规则；`MessageThreadStore.swift` 现在只保留 thread query、starter 查询和线程状态更新。同步更新工程文件，把新 service 文件接入 app target。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 拆 `APIClient.swift` 的 feed/message/starter/interaction endpoint 方法，降低 transport 核心与具体接口编排耦合。
  已完成：`APIClient.swift` 现在只保留 actor 初始化、decoder/错误包装和通用 `performDecodableRequest` transport 核心；新增 `bruh/Networking/APIClientFeedEndpoints.swift` 收口 feed 拉取，新增 `bruh/Networking/APIClientMessageEndpoints.swift` 收口消息发送与 starter 拉取，新增 `bruh/Networking/APIClientInteractionEndpoints.swift` 收口 feed interaction 生成。同步更新工程文件和 `scripts/run_p1_validation.sh` 的 API contract smoke 编译输入，确保拆分后 transport 与 endpoint 边界继续被验证。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。
- [x] 优化 `FeedService` 和 `ContentGraphStore` 的 feed 刷新查询路径，减少 SwiftData 的逐条 fetch 与 reconcile 开销。
  已完成：`FeedService.refreshFeed()` 现在会预取本地 `PersonaPost` 快照并复用内存 map，避免对每条远端 `PostDTO` 单独做 `FetchDescriptor`；`reconcileVisibleFeedWindow()` 也改成批量抓取 feed delivery 后再统一更新可见性。与此同时，`ContentGraphStore` 新增 feed 批量同步入口，预取对应的 `SourceItem`、`ContentEvent` 和 `ContentDelivery`，把原来每条 post 各查一次 source/event/delivery 的 N+1 路径收口成批量 fetch + 内存 cache，不改 UI 和业务结果。对应改动已通过 `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build` 和 `./scripts/run_p1_validation.sh`。

### P9 真实环境验证

- [ ] 配置 `.env.staging.local` 或 `.env.prod.local`，用真实 Supabase URL、service-role、functions base URL 和 anon key 跑通 `./scripts/run_release_preflight.sh`。
  说明：当前 preflight 脚本和 env loader 已就绪，但本机尚未提供真实环境密钥；没有这些值时只能验证本地代码与脚本，不可能完成关键表探测和 backend health 判断。
- [ ] 用真实环境执行 `./scripts/run_backend_health_snapshot.sh --strict`，确认 `pipeline_job_locks`、`news_articles`、`news_events`、`persona_news_scores`、`feed_items`、`source_posts` 的 freshness 和 job 状态达标。
  说明：这是下一阶段最有价值的非 UI 工作，能把“结构上可运行”推进到“真实环境上可发布”。

### 时间映射

- 立即做：P0
- 本周做：P1
- 下阶段做：P2
- 中期做：P3、P4
- 长期治理：P5

### 需确认后再做

- Home、消息、Feed、相册的页面结构调整。
- 入口顺序、导航路径、按钮位置变化。
- loading、empty、error 的用户可见样式改动。
- onboarding 流程和文案改动。
- 任何视觉风格或交互方式变化。

### 建议顺序

- 第一轮：`bootstrap -> ContentView 拆分 -> 单一真相源 -> seed/demo 剥离`
- 第二轮：`backend handler 拆分 -> schema -> 配置注入 -> tests/logging`
- 第三轮：`环境分层 -> migration -> CI/CD -> feature flag -> 成本控制`
- 第四轮：`媒体规范 -> cron 幂等 -> 错误恢复 -> 接口版本治理`
- 第五轮：`安全 -> 风控 -> 生命周期治理 -> 文档沉淀`
- 第六轮：`可观测性 -> 健康诊断 -> provider 指标 -> 发布 preflight`
