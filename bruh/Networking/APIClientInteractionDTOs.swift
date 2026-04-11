import Foundation

struct FeedInteractionRequestDTO: Codable {
    let postId: String
    let personaId: String
    let postContent: String
    let topic: String?
    let viewerComment: String?
    let viewerCommentId: String?
    let replyToCommentId: String?
    let replyTargetAuthorId: String?
    let existingLikes: [FeedInteractionLikeRequestDTO]
    let existingComments: [FeedInteractionCommentRequestDTO]
    let persistRemote: Bool
}

struct FeedInteractionLikeRequestDTO: Codable {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let reasonCode: String
    let createdAt: Date
}

struct FeedInteractionCommentRequestDTO: Codable {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let content: String
    let reasonCode: String
    let inReplyToCommentId: String?
    let isViewer: Bool
    let createdAt: Date
    let generationMode: String
}

struct FeedInteractionLikeDTO: Decodable {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let reasonCode: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case postId
        case post_id
        case authorId
        case author_id
        case authorDisplayName
        case author_display_name
        case reasonCode
        case reason_code
        case createdAt
        case created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        postId = try container.decodeFirst(String.self, forKeys: [.postId, .post_id])
        authorId = try container.decodeFirst(String.self, forKeys: [.authorId, .author_id])
        authorDisplayName = try container.decodeFirst(String.self, forKeys: [.authorDisplayName, .author_display_name])
        reasonCode = try container.decodeFirst(String.self, forKeys: [.reasonCode, .reason_code])
        createdAt = try container.decodeFirst(Date.self, forKeys: [.createdAt, .created_at])
    }
}

struct FeedInteractionCommentDTO: Decodable {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let content: String
    let reasonCode: String
    let inReplyToCommentId: String?
    let isViewer: Bool
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case postId
        case post_id
        case authorId
        case author_id
        case authorDisplayName
        case author_display_name
        case content
        case reasonCode
        case reason_code
        case inReplyToCommentId
        case in_reply_to_comment_id
        case isViewer
        case is_viewer
        case createdAt
        case created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        postId = try container.decodeFirst(String.self, forKeys: [.postId, .post_id])
        authorId = try container.decodeFirst(String.self, forKeys: [.authorId, .author_id])
        authorDisplayName = try container.decodeFirst(String.self, forKeys: [.authorDisplayName, .author_display_name])
        content = try container.decode(String.self, forKey: .content)
        reasonCode = try container.decodeFirst(String.self, forKeys: [.reasonCode, .reason_code])
        inReplyToCommentId = try container.decodeFirstIfPresent(String.self, forKeys: [.inReplyToCommentId, .in_reply_to_comment_id])
        isViewer = try container.decodeFirstIfPresent(Bool.self, forKeys: [.isViewer, .is_viewer]) ?? false
        createdAt = try container.decodeFirst(Date.self, forKeys: [.createdAt, .created_at])
    }
}

struct FeedInteractionReplyDTO: Decodable {
    let postId: String
    let likes: [FeedInteractionLikeDTO]
    let comments: [FeedInteractionCommentDTO]
    let generatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case postId
        case post_id
        case likes
        case comments
        case generatedAt
        case generated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        postId = try container.decodeFirst(String.self, forKeys: [.postId, .post_id])
        likes = try container.decodeIfPresent([FeedInteractionLikeDTO].self, forKey: .likes) ?? []
        comments = try container.decodeIfPresent([FeedInteractionCommentDTO].self, forKey: .comments) ?? []
        generatedAt = try container.decodeFirst(Date.self, forKeys: [.generatedAt, .generated_at])
    }
}
