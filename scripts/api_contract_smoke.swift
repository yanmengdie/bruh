import Foundation

@main
struct APIContractSmoke {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let feedPayload = Data(
            """
            [
              {
                "id": "feed-post-1",
                "personaId": "musk",
                "content": "Ship the next thing.",
                "sourceType": "x",
                "sourceUrl": "javascript:alert(1)",
                "topic": "tech",
                "importanceScore": 1.25,
                "mediaUrls": [
                  "https://cdn.example.com/hero.jpg#section",
                  "https://cdn.example.com/hero.jpg",
                  "http://cdn.example.com/insecure.jpg"
                ],
                "videoUrl": "https://video.example.com/clip.mp4#preview",
                "publishedAt": "2026-04-11T00:00:00Z"
              }
            ]
            """.utf8
        )

        let posts = try decoder.decode([PostDTO].self, from: feedPayload)
        expect(posts.count == 1, "Expected a single feed post DTO")
        expect(posts[0].personaId == "musk", "Expected feed DTO persona id to round-trip")
        expect(posts[0].sourceUrl == nil, "Expected invalid feed source URL to be dropped")
        expect(posts[0].mediaUrls == ["https://cdn.example.com/hero.jpg"], "Expected feed media URLs to be normalized and deduplicated")
        expect(posts[0].videoUrl == "https://video.example.com/clip.mp4", "Expected feed video URL to be normalized")

        let legacyFeedPayload = Data(
            """
            [
              {
                "id": "feed-post-legacy",
                "persona_id": "sam_altman",
                "content": "Infra keeps compounding.",
                "source_type": "news",
                "source_url": "http://example.com/news/1#read",
                "importance_score": 2.5,
                "media_urls": ["https://cdn.example.com/legacy.jpg#hero"],
                "video_url": null,
                "published_at": "2026-04-11T00:01:00Z"
              }
            ]
            """.utf8
        )
        let legacyPosts = try decoder.decode([PostDTO].self, from: legacyFeedPayload)
        expect(legacyPosts[0].personaId == "sam_altman", "Expected legacy snake_case feed payload to decode")
        expect(legacyPosts[0].sourceUrl == "http://example.com/news/1", "Expected legacy feed source URL to normalize")

        let messagePayload = Data(
            """
            {
              "id": "msg-1",
              "personaId": "musk",
              "content": "The constraint is usually the real product.",
              "imageUrl": "http://cdn.example.com/insecure.png",
              "sourceUrl": "https://example.com/source",
              "audioUrl": "file:///tmp/audio.wav",
              "audioDuration": null,
              "voiceLabel": null,
              "audioError": null,
              "audioOnly": false,
              "sourcePostIds": [],
              "generatedAt": "2026-04-11T00:05:00Z"
            }
            """.utf8
        )

        let message = try decoder.decode(MessageReplyDTO.self, from: messagePayload)
        expect(message.sourcePostIds.isEmpty, "Expected message DTO to default empty sourcePostIds")
        expect(message.imageUrl == nil, "Expected insecure message image URL to be dropped")
        expect(message.audioUrl == nil, "Expected invalid message audio URL to be dropped")

        let legacyMessagePayload = Data(
            """
            {
              "id": "msg-legacy",
              "persona_id": "musk",
              "text": "Move faster.",
              "image_url": "https://cdn.example.com/reply.png#preview",
              "source_url": "http://example.com/source/legacy#top",
              "audio_url": "https://cdn.example.com/reply.m4a#play",
              "audio_duration": 3.5,
              "voice_label": "calm",
              "audio_error": null,
              "audio_only": true,
              "source_post_ids": ["ctx-1"],
              "generated_at": "2026-04-11T00:06:00Z"
            }
            """.utf8
        )
        let legacyMessage = try decoder.decode(MessageReplyDTO.self, from: legacyMessagePayload)
        expect(legacyMessage.content == "Move faster.", "Expected legacy message text alias to decode")
        expect(legacyMessage.imageUrl == "https://cdn.example.com/reply.png", "Expected legacy image alias to normalize")
        expect(legacyMessage.audioUrl == "https://cdn.example.com/reply.m4a", "Expected legacy audio alias to normalize")
        expect(legacyMessage.sourcePostIds == ["ctx-1"], "Expected legacy sourcePostIds alias to decode")

        let starterPayload = Data(
            """
            {
              "starters": [
                {
                  "id": "starter-1",
                  "personaId": "sam_altman",
                  "text": "This is really about what ships next.",
                  "imageUrl": "https://cdn.example.com/starter.png#hero",
                  "articleUrl": "http://example.com/news/1#top",
                  "sourcePostIds": ["event-1"],
                  "createdAt": "2026-04-11T00:10:00Z",
                  "category": "tech",
                  "headline": "AI infra ramps again",
                  "isGlobalTop": true
                }
              ],
              "topSummary": "#1 AI infra ramps again [tech]"
            }
            """.utf8
        )

        let starterReply = try decoder.decode(MessageStarterReplyDTO.self, from: starterPayload)
        expect(starterReply.starters.count == 1, "Expected one starter DTO")
        expect(starterReply.starters[0].imageUrl == "https://cdn.example.com/starter.png", "Expected starter image URL to be normalized")
        expect(starterReply.starters[0].sourceUrl == "http://example.com/news/1", "Expected articleUrl compatibility fallback")

        let legacyStarterPayload = Data(
            """
            {
              "starters": [
                {
                  "id": "starter-legacy",
                  "persona_id": "musk",
                  "text": "That changes the board.",
                  "image_url": "https://cdn.example.com/starter-legacy.png#hero",
                  "article_url": "http://example.com/news/2#top",
                  "source_post_ids": ["event-2"],
                  "created_at": "2026-04-11T00:11:00Z",
                  "category": "tech",
                  "headline": "Robotics capex rises",
                  "is_global_top": false
                }
              ],
              "top_summary": "#2 Robotics capex rises [tech]"
            }
            """.utf8
        )
        let legacyStarterReply = try decoder.decode(MessageStarterReplyDTO.self, from: legacyStarterPayload)
        expect(legacyStarterReply.topSummary == "#2 Robotics capex rises [tech]", "Expected legacy top_summary alias to decode")
        expect(legacyStarterReply.starters[0].sourceUrl == "http://example.com/news/2", "Expected legacy article_url alias to decode")

        let interactionPayload = Data(
            """
            {
              "postId": "feed-post-1",
              "generatedAt": "2026-04-11T00:15:00Z"
            }
            """.utf8
        )

        let interactionReply = try decoder.decode(FeedInteractionReplyDTO.self, from: interactionPayload)
        expect(interactionReply.likes.isEmpty, "Expected interaction reply to default empty likes")
        expect(interactionReply.comments.isEmpty, "Expected interaction reply to default empty comments")

        let legacyInteractionPayload = Data(
            """
            {
              "post_id": "feed-post-legacy",
              "likes": [
                {
                  "id": "like-1",
                  "post_id": "feed-post-legacy",
                  "author_id": "musk",
                  "author_display_name": "Elon Musk",
                  "reason_code": "topic_match",
                  "created_at": "2026-04-11T00:14:00Z"
                }
              ],
              "comments": [
                {
                  "id": "comment-1",
                  "post_id": "feed-post-legacy",
                  "author_id": "viewer",
                  "author_display_name": "你",
                  "content": "Say more.",
                  "reason_code": "viewer_input",
                  "in_reply_to_comment_id": null,
                  "is_viewer": true,
                  "created_at": "2026-04-11T00:15:00Z"
                }
              ],
              "generated_at": "2026-04-11T00:16:00Z"
            }
            """.utf8
        )
        let legacyInteractionReply = try decoder.decode(FeedInteractionReplyDTO.self, from: legacyInteractionPayload)
        expect(legacyInteractionReply.postId == "feed-post-legacy", "Expected legacy post_id alias to decode")
        expect(legacyInteractionReply.likes.first?.authorId == "musk", "Expected legacy like alias to decode")
        expect(legacyInteractionReply.comments.first?.isViewer == true, "Expected legacy comment alias to decode")

        expect(
            NetworkRetryPolicy.shouldRetry(URLError(.timedOut), attempt: 1, profile: .feedRead),
            "Expected timed out feed requests to be retryable"
        )
        expect(
            NetworkRetryPolicy.shouldRetry(
                NetworkError.httpError(503, "upstream timeout", "timeout"),
                attempt: 1,
                profile: .starterPrefetch
            ),
            "Expected transient starter errors to be retryable"
        )
        expect(
            !NetworkRetryPolicy.shouldRetry(
                NetworkError.httpError(400, "personaId is required", "validation"),
                attempt: 1,
                profile: .messageSend
            ),
            "Expected validation failures to remain terminal"
        )
        expect(
            NetworkRetryPolicy.delayNanoseconds(forAttempt: 2, profile: .messageSend) > 0,
            "Expected retry delay to be positive"
        )

        let compatibleResponse = try requireResponse(
            url: "https://example.com/feed",
            headerFields: [APIContract.contractHeader: APIContractName.feedV1.rawValue]
        )
        try APIContract.validateResponse(compatibleResponse, expectedContract: .feedV1)

        let mismatchedResponse = try requireResponse(
            url: "https://example.com/feed",
            headerFields: [APIContract.contractHeader: APIContractName.generateMessageV1.rawValue]
        )

        do {
            try APIContract.validateResponse(mismatchedResponse, expectedContract: .feedV1)
            expect(false, "Expected mismatched response contract to fail validation")
        } catch let error as NetworkError {
            switch error {
            case .incompatibleContract(let expected, let actual):
                expect(expected == APIContractName.feedV1.rawValue, "Expected feed contract in mismatch error")
                expect(actual == APIContractName.generateMessageV1.rawValue, "Expected actual contract in mismatch error")
            default:
                expect(false, "Expected incompatibleContract error, got \(error.localizedDescription)")
            }
        }

        print("API contract smoke passed")
    }

    private static func requireResponse(
        url: String,
        statusCode: Int = 200,
        headerFields: [String: String]
    ) throws -> HTTPURLResponse {
        guard let url = URL(string: url),
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headerFields) else {
            throw NSError(domain: "APIContractSmoke", code: 1)
        }
        return response
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Assertion failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
