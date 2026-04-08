# XHS Sync Tools

本目录用于本地拿你自己的小红书登录态，抓某个账号最近的笔记文案。

## 安装

```bash
cd /Users/nayi/bruh/tools/xhs
npm install
```

## 登录一次

```bash
npm run login
```

- 会弹出浏览器
- 你扫码或手机号登录即可
- 登录态会保存在 `tools/xhs/.auth/`
- 该目录已被 `.gitignore` 忽略

## 同步某个账号

```bash
npm run sync -- --query 科技薯 --limit 5
```

- 会先搜索用户
- 自动挑选最匹配的账号
- 打开资料页
- 抓最近几条笔记详情
- 输出到 `tools/xhs/output/*.json`

如果要直接写入你现有的朋友圈库：

```bash
npm run sync -- --query 影石刘靖康 --limit 5 --persona-id 影石刘靖康 --ingest
```

- 会调用 `ingest-xhs-posts`
- 然后自动调用 `build-feed`
- iOS 端下拉刷新后就能从同一套 feed 链路读到这些帖子

## 如果你想直接给凭证

不建议直接把单个 auth token 发进聊天。

如果一定要走凭证方式，建议给 **完整 cookie 字符串**，然后本地执行：

```bash
XHS_COOKIE='a1=...; webId=...; websectiga=...; gid=...;' npm run login
```

但单个 token 往往不够，小红书网页通常至少依赖整组 cookie。
