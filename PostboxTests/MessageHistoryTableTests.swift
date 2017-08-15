import Foundation

import UIKit
import XCTest

import Postbox
@testable import Postbox

import SwiftSignalKit

private let peerId = PeerId(namespace: 1, id: 1)
private let otherPeerId = PeerId(namespace: 1, id: 2)
private let namespace: Int32 = 1
private let authorPeerId = PeerId(namespace: 1, id: 6)
private let peer = TestPeer(id: 6, data: "abc")
private let tag1 = MessageTags(rawValue: 1 << 0)
private let tag2 = MessageTags(rawValue: 1 << 1)
private let summaryTag = MessageTags(rawValue: 1 << 2)

private func ==(lhs: [Media], rhs: [Media]) -> Bool {
    if lhs.count != rhs.count {
        return false
    }
    
    for i in 0 ..< lhs.count {
        if !lhs[i].isEqual(rhs[i]) {
            return false
        }
    }
    return true
}

private enum Entry: Equatable, CustomStringConvertible {
    case Message(Int32, Int32, String, [Media], MessageFlags)
    case Hole(Int32, Int32, Int32)
    
    var description: String {
        switch self {
            case let .Message(id, timestamp, text, media, flags):
                return "Message(\(id), \(timestamp), \(text), \(media), \(flags))"
            case let .Hole(min, max, timestamp):
                return "Hole(\(min), \(max), \(timestamp))"
        }
    }
}

private func ==(lhs: Entry, rhs: Entry) -> Bool {
    switch lhs {
        case let .Message(lhsId, lhsTimestamp, lhsText, lhsMedia, lhsFlags):
            switch rhs {
                case let .Message(rhsId, rhsTimestamp, rhsText, rhsMedia, rhsFlags):
                    return lhsId == rhsId && lhsTimestamp == rhsTimestamp && lhsText == rhsText && lhsMedia == rhsMedia && lhsFlags == rhsFlags
                case .Hole:
                    return false
            }
        case let .Hole(lhsMin, lhsMax, lhsMaxTimestamp):
            switch rhs {
                case .Message:
                    return false
                case let .Hole(rhsMin, rhsMax, rhsMaxTimestamp):
                    return lhsMin == rhsMin && lhsMax == rhsMax && lhsMaxTimestamp == rhsMaxTimestamp
            }
    }
}

private class TestEmbeddedMedia: Media, CustomStringConvertible {
    var id: MediaId? { return nil }
    var peerIds: [PeerId] = []
    let data: String
    
    init(data: String) {
        self.data = data
    }
    
    required init(decoder: Decoder) {
        self.data = decoder.decodeStringForKey("s", orElse: "")
    }
    
    func encode(_ encoder: Encoder) {
        encoder.encodeString(self.data, forKey: "s")
    }
    
    func isEqual(_ other: Media) -> Bool {
        if let other = other as? TestEmbeddedMedia {
            return self.data == other.data
        }
        return false
    }
    
    var description: String {
        return "TestEmbeddedMedia(\(self.data))"
    }
}

private class TestExternalMedia: Media {
    let id: MediaId?
    var peerIds: [PeerId] = []
    let data: String
    
    init(id: Int64, data: String) {
        self.id = MediaId(namespace: namespace, id: id)
        self.data = data
    }
    
    required init(decoder: Decoder) {
        self.id = MediaId(namespace: decoder.decodeInt32ForKey("i.n", orElse: 0), id: decoder.decodeInt64ForKey("i.i", orElse: 0))
        self.data = decoder.decodeStringForKey("s", orElse: "")
    }
    
    func encode(_ encoder: Encoder) {
        encoder.encodeInt32(self.id!.namespace, forKey: "i.n")
        encoder.encodeInt64(self.id!.id, forKey: "i.i")
        encoder.encodeString(self.data, forKey: "s")
    }
    
    func isEqual(_ other: Media) -> Bool {
        if let other = other as? TestExternalMedia {
            return self.id == other.id && self.data == other.data
        }
        return false
    }
    
    var description: String {
        return "TestExternalMedia(\(self.id!.id), \(self.data))"
    }
}

private class TestPeer: Peer {
    let associatedPeerId: PeerId? = nil

    public let notificationSettingsPeerId: PeerId? = nil

    let associatedPeerIds: [PeerId]? = nil

    var indexName: PeerIndexNameRepresentation {
        return .title(title: "Test", addressName: nil)
    }

    let id: PeerId
    let data: String
    
    init(id: Int32, data: String) {
        self.id = PeerId(namespace: namespace, id: id)
        self.data = data
    }
    
    required init(decoder: Decoder) {
        self.id = PeerId(namespace: decoder.decodeInt32ForKey("i.n", orElse: 0), id: decoder.decodeInt32ForKey("i.i", orElse: 0))
        self.data = decoder.decodeStringForKey("s", orElse: "")
    }
    
    func encode(_ encoder: Encoder) {
        encoder.encodeInt32(self.id.namespace, forKey: "i.n")
        encoder.encodeInt32(self.id.id, forKey: "i.i")
        encoder.encodeString(self.data, forKey: "s")
    }
    
    func isEqual(_ other: Peer) -> Bool {
        if let other = other as? TestPeer {
            return self.id == other.id && self.data == other.data
        }
        return false
    }
    
    var description: String {
        return "TestPeer(\(self.id.id), \(self.data))"
    }
}

private enum MediaEntry: Equatable {
    case Direct(Media, Int)
    case MessageReference(Int32)
    
    init(_ entry: DebugMediaEntry) {
        switch entry {
            case let .Direct(media, referenceCount):
                self = .Direct(media, referenceCount)
            case let .MessageReference(index):
                self = .MessageReference(index.id.id)
        }
    }
}

private func ==(lhs: MediaEntry, rhs: MediaEntry) -> Bool {
    switch lhs {
        case let .Direct(lhsMedia, lhsReferenceCount):
            switch rhs {
                case let .Direct(rhsMedia, rhsReferenceCount):
                    return lhsMedia.isEqual(rhsMedia) && lhsReferenceCount == rhsReferenceCount
                case .MessageReference:
                    return false
            }
        case let .MessageReference(lhsId):
            switch rhs {
                case .Direct:
                    return false
                case let .MessageReference(rhsId):
                    return lhsId == rhsId
            }
    }
}

private extension MessageTags {
    static let First = MessageTags(rawValue: 1 << 0)
    static let Second = MessageTags(rawValue: 1 << 1)
    static let Summary = MessageTags(rawValue: 1 << 2)
}

private final class PendingMessageAction1: PendingMessageActionData {
    init() {
    }
    
    init(decoder: Decoder) {
    }
    
    func encode(_ encoder: Encoder) {
    }
    
    func isEqual(to: PendingMessageActionData) -> Bool {
        if let _ = to as? PendingMessageAction1 {
            return true
        } else {
            return false
        }
    }
}

private final class PendingMessageAction2: PendingMessageActionData {
    init() {
    }
    
    init(decoder: Decoder) {
    }
    
    func encode(_ encoder: Encoder) {
    }
    
    func isEqual(to: PendingMessageActionData) -> Bool {
        if let _ = to as? PendingMessageAction2 {
            return true
        } else {
            return false
        }
    }
}

private let pendingAction1 = PendingMessageActionType(rawValue: 0)
private let pendingAction2 = PendingMessageActionType(rawValue: 1)

class MessageHistoryTableTests: XCTestCase {
    var valueBox: ValueBox?
    var path: String?
    
    var peerTable: PeerTable?
    var globalMessageIdsTable: GlobalMessageIdsTable?
    var indexTable: MessageHistoryIndexTable?
    var mediaTable: MessageMediaTable?
    var historyTable: MessageHistoryTable?
    var historyMetadataTable: MessageHistoryMetadataTable?
    var unsentTable: MessageHistoryUnsentTable?
    var tagsTable: MessageHistoryTagsTable?
    var readStateTable: MessageHistoryReadStateTable?
    var synchronizeReadStateTable: MessageHistorySynchronizeReadStateTable?
    var globallyUniqueMessageIdsTable: MessageGloballyUniqueIdTable?
    var globalTagsTable: GlobalMessageHistoryTagsTable?
    var reverseAssociatedTable: ReverseAssociatedPeerTable?
    var textIndexTable: MessageHistoryTextIndexTable?
    var messageHistoryTagsSummaryTable: MessageHistoryTagsSummaryTable?
    var pendingMessageActionsTable: PendingMessageActionsTable?
    var pendingMessageActionsMetadataTable: PendingMessageActionsMetadataTable?
    
    override class func setUp() {
        super.setUp()
        
        declareEncodable(TestEmbeddedMedia.self, f: { TestEmbeddedMedia(decoder: $0) })
        declareEncodable(TestExternalMedia.self, f: { TestExternalMedia(decoder: $0) })
        declareEncodable(TestPeer.self, f: { TestPeer(decoder: $0) })
        declareEncodable(PendingMessageAction1.self, f: PendingMessageAction1.init)
        declareEncodable(PendingMessageAction2.self, f: PendingMessageAction2.init)
    }
    
    override func setUp() {
        super.setUp()
        
        var randomId: Int64 = 0
        arc4random_buf(&randomId, 8)
        path = NSTemporaryDirectory() + "\(randomId)"
        self.valueBox = SqliteValueBox(basePath: path!, queue: Queue.mainQueue())
        
        let seedConfiguration = SeedConfiguration(initializeChatListWithHoles: [], initializeMessageNamespacesWithHoles: [], existingMessageTags: [.First, .Second, .Summary], messageTagsWithSummary: [.Summary], existingGlobalMessageTags: [], peerNamespacesRequiringMessageTextIndex: [])
        
        self.globalMessageIdsTable = GlobalMessageIdsTable(valueBox: self.valueBox!, table: GlobalMessageIdsTable.tableSpec(5), namespace: namespace)
        self.historyMetadataTable = MessageHistoryMetadataTable(valueBox: self.valueBox!, table: MessageHistoryMetadataTable.tableSpec(7))
        self.unsentTable = MessageHistoryUnsentTable(valueBox: self.valueBox!, table: MessageHistoryUnsentTable.tableSpec(8))
        self.messageHistoryTagsSummaryTable = MessageHistoryTagsSummaryTable(valueBox: self.valueBox!, table: MessageHistoryTagsSummaryTable.tableSpec(16))
        self.pendingMessageActionsMetadataTable = PendingMessageActionsMetadataTable(valueBox: self.valueBox!, table: PendingMessageActionsMetadataTable.tableSpec(17))
        self.pendingMessageActionsTable = PendingMessageActionsTable(valueBox: self.valueBox!, table: PendingMessageActionsTable.tableSpec(18), metadataTable: self.pendingMessageActionsMetadataTable!)
        self.tagsTable = MessageHistoryTagsTable(valueBox: self.valueBox!, table: MessageHistoryTagsTable.tableSpec(9), seedConfiguration: seedConfiguration, summaryTable: self.messageHistoryTagsSummaryTable!)
        self.indexTable = MessageHistoryIndexTable(valueBox: self.valueBox!, table: MessageHistoryIndexTable.tableSpec(1), globalMessageIdsTable: self.globalMessageIdsTable!, metadataTable: self.historyMetadataTable!, seedConfiguration: seedConfiguration)
        self.mediaTable = MessageMediaTable(valueBox: self.valueBox!, table: MessageMediaTable.tableSpec(2))
        self.readStateTable = MessageHistoryReadStateTable(valueBox: self.valueBox!, table: MessageHistoryReadStateTable.tableSpec(10))
        self.synchronizeReadStateTable = MessageHistorySynchronizeReadStateTable(valueBox: self.valueBox!, table: MessageHistorySynchronizeReadStateTable.tableSpec(11))
        self.globallyUniqueMessageIdsTable = MessageGloballyUniqueIdTable(valueBox: self.valueBox!, table: MessageGloballyUniqueIdTable.tableSpec(12))
        self.globalTagsTable = GlobalMessageHistoryTagsTable(valueBox: self.valueBox!, table: GlobalMessageHistoryTagsTable.tableSpec(13))
        self.textIndexTable = MessageHistoryTextIndexTable(valueBox: self.valueBox!, table: MessageHistoryTextIndexTable.tableSpec(15))
        self.historyTable = MessageHistoryTable(valueBox: self.valueBox!, table: MessageHistoryTable.tableSpec(4), messageHistoryIndexTable: self.indexTable!, messageMediaTable: self.mediaTable!, historyMetadataTable: self.historyMetadataTable!, globallyUniqueMessageIdsTable: self.globallyUniqueMessageIdsTable!, unsentTable: self.unsentTable!, tagsTable: self.tagsTable!, globalTagsTable: self.globalTagsTable!, readStateTable: self.readStateTable!, synchronizeReadStateTable: self.synchronizeReadStateTable!, textIndexTable: self.textIndexTable!, summaryTable: self.messageHistoryTagsSummaryTable!, pendingActionsTable: self.pendingMessageActionsTable!)
        self.reverseAssociatedTable = ReverseAssociatedPeerTable(valueBox: self.valueBox!, table: ReverseAssociatedPeerTable.tableSpec(14))
        self.peerTable = PeerTable(valueBox: self.valueBox!, table: PeerTable.tableSpec(6), reverseAssociatedTable: self.reverseAssociatedTable!)
        self.peerTable!.set(peer)
    }
    
    override func tearDown() {
        super.tearDown()
        
        self.historyTable = nil
        self.indexTable = nil
        self.mediaTable = nil
        self.peerTable = nil
        self.historyMetadataTable = nil
        
        self.valueBox = nil
        let _ = try? FileManager.default.removeItem(atPath: path!)
        self.path = nil
    }
    
    private func addMessage(_ id: Int32, _ timestamp: Int32, _ text: String = "", _ media: [Media] = [], _ flags: StoreMessageFlags = [], _ tags: MessageTags = []) {
        var operationsByPeerId: [PeerId: [MessageHistoryOperation]] = [:]
        var unsentMessageOperations: [IntermediateMessageHistoryUnsentOperation] = []
        var updatedPeerReadStateOperations: [PeerId: PeerReadStateSynchronizationOperation?] = [:]
        var globalTagsOperations: [GlobalMessageHistoryTagsOperation] = []
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        let _ = self.historyTable!.addMessages([StoreMessage(id: MessageId(peerId: peerId, namespace: namespace, id: id), globallyUniqueId: nil, timestamp: timestamp, flags: flags, tags: tags, globalTags: [], forwardInfo: StoreMessageForwardInfo(authorId: peerId, sourceId: peerId, sourceMessageId: MessageId(peerId: peerId, namespace: 0, id: 10), date: 10, authorSignature: "abc"), authorId: authorPeerId, text: text, attributes: [], media: media)], location: .Random, operationsByPeerId: &operationsByPeerId, unsentMessageOperations: &unsentMessageOperations, updatedPeerReadStateOperations: &updatedPeerReadStateOperations, globalTagsOperations: &globalTagsOperations, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations, updatedMessageTagSummaries: &updatedMessageTagSummaries)
    }

    private func updateMessage(_ previousId: Int32, _ id: Int32, _ timestamp: Int32, _ text: String = "", _ media: [Media] = [], _ flags: StoreMessageFlags, _ tags: MessageTags) {
        var operationsByPeerId: [PeerId: [MessageHistoryOperation]] = [:]
        var unsentMessageOperations: [IntermediateMessageHistoryUnsentOperation] = []
        var updatedPeerReadStateOperations: [PeerId: PeerReadStateSynchronizationOperation?] = [:]
        var globalTagsOperations: [GlobalMessageHistoryTagsOperation] = []
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        self.historyTable!.updateMessage(MessageId(peerId: peerId, namespace: namespace, id: previousId), message: StoreMessage(id: MessageId(peerId: peerId, namespace: namespace, id: id), globallyUniqueId: nil, timestamp: timestamp, flags: flags, tags: tags, globalTags: [], forwardInfo: nil, authorId: authorPeerId, text: text, attributes: [], media: media), operationsByPeerId: &operationsByPeerId, unsentMessageOperations: &unsentMessageOperations, updatedPeerReadStateOperations: &updatedPeerReadStateOperations, globalTagsOperations: &globalTagsOperations, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations, updatedMessageTagSummaries: &updatedMessageTagSummaries)
    }
    
    private func addHole(_ id: Int32) {
        var operationsByPeerId: [PeerId: [MessageHistoryOperation]] = [:]
        var unsentMessageOperations: [IntermediateMessageHistoryUnsentOperation] = []
        var updatedPeerReadStateOperations: [PeerId: PeerReadStateSynchronizationOperation?] = [:]
        var globalTagsOperations: [GlobalMessageHistoryTagsOperation] = []
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        self.historyTable!.addHoles([MessageId(peerId: peerId, namespace: namespace, id: id)], operationsByPeerId: &operationsByPeerId, unsentMessageOperations: &unsentMessageOperations, updatedPeerReadStateOperations: &updatedPeerReadStateOperations, globalTagsOperations: &globalTagsOperations, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations, updatedMessageTagSummaries: &updatedMessageTagSummaries)
    }
    
    private func removeMessages(_ ids: [Int32]) {
        var operationsByPeerId: [PeerId: [MessageHistoryOperation]] = [:]
        var unsentMessageOperations: [IntermediateMessageHistoryUnsentOperation] = []
        var updatedPeerReadStateOperations: [PeerId: PeerReadStateSynchronizationOperation?] = [:]
        var globalTagsOperations: [GlobalMessageHistoryTagsOperation] = []
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        self.historyTable!.removeMessages(ids.map({ MessageId(peerId: peerId, namespace: namespace, id: $0) }), operationsByPeerId: &operationsByPeerId, unsentMessageOperations: &unsentMessageOperations, updatedPeerReadStateOperations: &updatedPeerReadStateOperations, globalTagsOperations: &globalTagsOperations, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations, updatedMessageTagSummaries: &updatedMessageTagSummaries)
    }
    
    private func fillHole(_ id: Int32, _ fillType: HoleFill, _ messages: [(Int32, Int32, String, [Media])], _ tagMask: MessageTags? = nil) {
        var operationsByPeerId: [PeerId: [MessageHistoryOperation]] = [:]
        var unsentMessageOperations: [IntermediateMessageHistoryUnsentOperation] = []
        var updatedPeerReadStateOperations: [PeerId: PeerReadStateSynchronizationOperation?] = [:]
        var globalTagsOperations: [GlobalMessageHistoryTagsOperation] = []
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        self.historyTable!.fillHole(MessageId(peerId: peerId, namespace: namespace, id: id), fillType: fillType, tagMask: tagMask, messages: messages.map({ StoreMessage(id: MessageId(peerId: peerId, namespace: namespace, id: $0.0), globallyUniqueId: nil, timestamp: $0.1, flags: [], tags: [], globalTags: [], forwardInfo: nil, authorId: authorPeerId, text: $0.2, attributes: [], media: $0.3) }), operationsByPeerId: &operationsByPeerId, unsentMessageOperations: &unsentMessageOperations, updatedPeerReadStateOperations: &updatedPeerReadStateOperations, globalTagsOperations: &globalTagsOperations, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations, updatedMessageTagSummaries: &updatedMessageTagSummaries)
    }
    
    private func fillMultipleHoles(_ id: Int32, _ fillType: HoleFill, _ messages: [(Int32, Int32, String, [Media])], _ tagMask: MessageTags? = nil, _ tags: MessageTags = []) {
        var operationsByPeerId: [PeerId: [MessageHistoryOperation]] = [:]
        var unsentMessageOperations: [IntermediateMessageHistoryUnsentOperation] = []
        var updatedPeerReadStateOperations: [PeerId: PeerReadStateSynchronizationOperation?] = [:]
        var globalTagsOperations: [GlobalMessageHistoryTagsOperation] = []
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        self.historyTable!.fillMultipleHoles(mainHoleId: MessageId(peerId: peerId, namespace: namespace, id: id), fillType: fillType, tagMask: tagMask, messages: messages.map({ StoreMessage(id: MessageId(peerId: peerId, namespace: namespace, id: $0.0), globallyUniqueId: nil, timestamp: $0.1, flags: [], tags: tags, globalTags: [], forwardInfo: nil, authorId: authorPeerId, text: $0.2, attributes: [], media: $0.3) }), operationsByPeerId: &operationsByPeerId, unsentMessageOperations: &unsentMessageOperations, updatedPeerReadStateOperations: &updatedPeerReadStateOperations, globalTagsOperations: &globalTagsOperations, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations, updatedMessageTagSummaries: &updatedMessageTagSummaries)
    }
    
    private func replaceSummary(_ count: Int32, _ maxId: MessageId.Id) {
        
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        self.messageHistoryTagsSummaryTable!.replace(key: MessageHistoryTagsSummaryKey(tag: .Summary, peerId: peerId, namespace: namespace), count: count, maxId: maxId, updatedSummaries: &updatedMessageTagSummaries)
    }
    
    private func expectEntries(_ entries: [Entry], tagMask: MessageTags? = nil) {
        var stableIds = Set<UInt32>()
        
        let list: [RenderedMessageHistoryEntry]
        if let tagMask = tagMask {
            list = self.historyTable!.debugList(tagMask, peerId: peerId, peerTable: self.peerTable!)
        } else {
            list = self.historyTable!.debugList(peerId, peerTable: self.peerTable!)
        }
        
        let actualEntries = list.map({ entry -> Entry in
            let stableId: UInt32
            switch entry {
                case let .RenderedMessage(message):
                    stableId = message.stableId
                    if let messagePeer = message.author {
                        if !peer.isEqual(messagePeer) {
                            XCTFail("Expected peer \(peer), actual: \(messagePeer)")
                        }
                    } else {
                        XCTFail("Expected peer \(peer), actual: nil")
                    }
                    if stableIds.contains(stableId) {
                        XCTFail("Stable id not unique \(stableId)")
                    } else {
                        stableIds.insert(stableId)
                    }
                    return .Message(message.id.id, message.timestamp, message.text, message.media, message.flags)
                case let .Hole(hole):
                    stableId = hole.stableId
                    if stableIds.contains(stableId) {
                        XCTFail("Stable id not unique \(stableId)")
                    } else {
                        stableIds.insert(stableId)
                    }
                    return .Hole(hole.min, hole.maxIndex.id.id, hole.maxIndex.timestamp)
            }
        })
        if actualEntries != entries {
            XCTFail("Expected\n\(entries)\nActual\n\(actualEntries)")
        }
    }
    
    private func expectUnsent(_ indices: [Int32]) {
        let actualUnsent = self.unsentTable!.get().map({ $0.id })
        var match = true
        if actualUnsent.count == indices.count {
            for i in 0 ..< indices.count {
                if indices[i] != actualUnsent[i] {
                    match = false
                    break
                }
            }
        } else {
            match = false
        }
        if !match {
            XCTFail("Expected\n\(indices)\nActual\n\(actualUnsent)")
        }
    }
    
    private func expectMedia(_ media: [MediaEntry]) {
        let actualMedia = self.mediaTable!.debugList().map({MediaEntry($0)})
        if media != actualMedia {
            XCTFail("Expected\n\(media)\nActual\n\(actualMedia)")
        }
    }
    
    private func expectSummary(_ summary: MessageHistoryTagNamespaceSummary?) {
        let actualSummary = self.messageHistoryTagsSummaryTable!.get(MessageHistoryTagsSummaryKey(tag: .Summary, peerId: peerId, namespace: namespace))
        if actualSummary != summary {
            XCTFail("Expected\n\(String(describing: summary))\nActual\n\(String(describing: actualSummary))\n")
        }
    }
    
    private func setMessageAction(_ id: Int32, _ type: PendingMessageActionType, _ data: PendingMessageActionData?) {
        var pendingActionsOperations: [PendingMessageActionsOperation] = []
        var pendingActionsMetadataOperations: [PendingMessageActionsSummaryOperation] = []
        var updatedMessageTagSummaries: [MessageHistoryTagsSummaryKey: MessageHistoryTagNamespaceSummary] = [:]
        
        self.historyTable!.setPendingMessageAction(id: MessageId(peerId: peerId, namespace: namespace, id: id), type: type, action: data, pendingActionsOperations: &pendingActionsOperations, pendingActionsMetadataOperations: &pendingActionsMetadataOperations)
    }
    
    private func expectMessageAction(_ id: Int32, _ type: PendingMessageActionType, _ data: PendingMessageActionData?) {
        let current = self.pendingMessageActionsTable!.getAction(id: MessageId(peerId: peerId, namespace: namespace, id: id), type: type)
        var changed = false
        if let current = current, let data = data {
            if !current.isEqual(to: data) {
                changed = true
            }
        } else if (current != nil) != (data != nil) {
            changed = true
        }
        if changed {
            XCTFail("Expected\n\(String(describing: data))\nActual\n\(String(describing: current))\n")
        }
    }
    
    private func expectPeerNamespaceMessageActionCount(_ count: Int32) {
        let current = self.pendingMessageActionsMetadataTable!.getCount(.peerNamespace(peerId, namespace))
        if count != current {
            XCTFail("Expected\n\(count)\nActual\n\(current)\n")
        }
    }
    
    private func expectPeerNamespaceActionMessageActionCount(_ count: Int32, _ type: PendingMessageActionType) {
        let current = self.pendingMessageActionsMetadataTable!.getCount(.peerNamespaceAction(peerId, namespace, type))
        if count != current {
            XCTFail("Expected\n\(count)\nActual\n\(current)\n")
        }
    }
    
    private func expectPeerMessageActions(_ type: PendingMessageActionType, _ actions: [(Int32, PendingMessageActionData)]) {
        let current = self.pendingMessageActionsTable!.getActions(type: type).map {
            ($0.id.id, $0.action)
        }
        var changed = false
        if current.count != actions.count {
            changed = true
        } else {
            for i in 0 ..< current.count {
                if current[i].0 != actions[i].0 {
                    changed = true
                    break
                } else if !current[i].1.isEqual(to: actions[i].1) {
                    changed = true
                    break
                }
            }
        }
        if changed {
            XCTFail("Expected\n\(actions)\nActual\n\(current)\n")
        }
    }
    
    func testInsertMessageIntoEmpty() {
        addMessage(100, 100, "t100")
        addMessage(200, 200, "t200")
        
        expectEntries([.Message(100, 100, "t100", [], []), .Message(200, 200, "t200", [], [])])
    }
    
    func testInsertMessageIgnoreOverwrite() {
        addMessage(100, 100, "t100")
        addMessage(100, 200, "t200")
        
        expectEntries([.Message(100, 100, "t100", [], [])])
    }
    
    func testInsertMessageWithEmbeddedMedia() {
        addMessage(100, 100, "t100", [TestEmbeddedMedia(data: "abc1")])
        
        expectEntries([.Message(100, 100, "t100", [TestEmbeddedMedia(data: "abc1")], [])])
        expectMedia([])
    }
    
    func testInsertMessageWithExternalMedia() {
        let media = TestExternalMedia(id: 10, data: "abc1")
        addMessage(100, 100, "t100", [media])
        
        expectEntries([.Message(100, 100, "t100", [media], [])])
        expectMedia([.MessageReference(100)])
    }
    
    func testUnembedExternalMedia() {
        let media = TestExternalMedia(id: 10, data: "abc1")
        addMessage(100, 100, "t100", [media])
        addMessage(200, 200, "t200", [media])
        
        expectEntries([.Message(100, 100, "t100", [media], []), .Message(200, 200, "t200", [media], [])])
        expectMedia([.Direct(media, 2)])
    }
    
    func testIgnoreOverrideExternalMedia() {
        let media = TestExternalMedia(id: 10, data: "abc1")
        let media1 = TestExternalMedia(id: 10, data: "abc2")
        addMessage(100, 100, "t100", [media])
        addMessage(200, 200, "t200", [media1])
        
        expectEntries([.Message(100, 100, "t100", [media], []), .Message(200, 200, "t200", [media], [])])
        expectMedia([.Direct(media, 2)])
    }
    
    func testRemoveSingleMessage() {
        addMessage(100, 100, "t100", [])
        
        removeMessages([100])
        
        expectEntries([])
        expectMedia([])
    }
    
    func testRemoveMessageWithEmbeddedMedia() {
        let media = TestEmbeddedMedia(data: "abc1")
        addMessage(100, 100, "t100", [media])
        self.removeMessages([100])
        
        expectEntries([])
        expectMedia([])
    }
    
    func testRemoveOnlyReferenceToExternalMedia() {
        let media = TestExternalMedia(id: 10, data: "abc1")
        addMessage(100, 100, "t100", [media])
        removeMessages([100])
        
        expectEntries([])
        expectMedia([])
    }
    
    func testRemoveReferenceToExternalMedia() {
        let media = TestExternalMedia(id: 10, data: "abc1")
        addMessage(100, 100, "t100", [media])
        addMessage(200, 200, "t200", [media])
        removeMessages([100])
        
        expectEntries([.Message(200, 200, "t200", [media], [])])
        expectMedia([.Direct(media, 1)])
        
        removeMessages([200])
        
        expectEntries([])
        expectMedia([])
    }
    
    func testAddHoleToEmpty() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
    }
    
    func testAddHoleToFullHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        addHole(110)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
    }
    
    func testAddMessageToFullHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        addMessage(90, 90, "m90")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
    }
    
    func testAddMessageDividingUpperHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        addMessage(90, 90, "m90")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
        addMessage(100, 100, "m100")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, 99, 100), .Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)])
    }
    
    func testAddMessageDividingLowerHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        addMessage(90, 90, "m90")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
        addMessage(80, 80, "m80")
        expectEntries([.Hole(1, 79, 80), .Message(80, 80, "m80", [], []), .Hole(81, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
    }
    
    func testAddMessageOffsettingUpperHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        
        addMessage(90, 90, "m90")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
        addMessage(91, 91, "m91")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Message(91, 91, "m91", [], []), .Hole(92, Int32.max, Int32.max)])
    }
    
    func testAddMessageOffsettingLowerHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        
        addMessage(90, 90, "m90")
        expectEntries([.Hole(1, 89, 90), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
        addMessage(89, 89, "m89")
        expectEntries([.Hole(1, 88, 89), .Message(89, 89, "m89", [], []), .Message(90, 90, "m90", [], []), .Hole(91, Int32.max, Int32.max)])
    }
    
    func testAddMessageOffsettingLeftmostHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        
        addMessage(1, 1, "m1")
        
        expectEntries([.Message(1, 1, "m1", [], []), .Hole(2, Int32.max, Int32.max)])
    }
    
    func testAddMessageRemovingLefmostHole() {
        addHole(100)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        
        addMessage(2, 2, "m2")
        expectEntries([.Hole(1, 1, 2), .Message(2, 2, "m2", [], []), .Hole(3, Int32.max, Int32.max)])
        
        addMessage(1, 1, "m1")
        expectEntries([.Message(1, 1, "m1", [], []), .Message(2, 2, "m2", [], []), .Hole(3, Int32.max, Int32.max)])
    }
    
    func testAddHoleLowerThanMessage() {
        addMessage(100, 100, "m100")
        addHole(1)
        
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], [])])
    }
    
    func testAddHoleHigherThanMessage() {
        addMessage(100, 100, "m100")
        addHole(200)
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)])
    }
    
    func testIgnoreHigherHole() {
        addHole(200)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
        addHole(400)
        expectEntries([.Hole(1, Int32.max, Int32.max)])
    }
    
    func testIgnoreHigherHoleAfterMessage() {
        addMessage(100, 100, "m100")
        addHole(200)
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)])
        addHole(400)
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)])
    }
    
    func testAddHoleBetweenMessages() {
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        addHole(150)
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testFillHoleEmpty() {
        fillHole(1, HoleFill(complete: true, direction: .UpperToLower), [])
        expectEntries([])
    }
    
    func testFillHoleComplete() {
        addHole(100)
        
        fillHole(1, HoleFill(complete: true, direction: .UpperToLower), [(100, 100, "m100", []), (200, 200, "m200", [])])
        expectEntries([.Message(100, 100, "m100", [], []), .Message(200, 200, "m200", [], [])])
    }
    
    func testFillHoleUpperToLowerPartial() {
        addHole(100)
        
        fillHole(1, HoleFill(complete: false, direction: .UpperToLower), [(100, 100, "m100", []), (200, 200, "m200", [])])
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], []), .Message(200, 200, "m200", [], [])])
    }
    
    func testFillHoleUpperToLowerToBounds() {
        addHole(100)
        
        fillHole(1, HoleFill(complete: false, direction: .UpperToLower), [(1, 1, "m1", []), (200, 200, "m200", [])])
        expectEntries([.Message(1, 1, "m1", [], []), .Message(200, 200, "m200", [], [])])
    }
    
    func testFillHoleLowerToUpperToBounds() {
        addHole(100)
        
        fillHole(1, HoleFill(complete: false, direction: .LowerToUpper), [(100, 100, "m100", []), (Int32.max, 200, "m200", [])])
        expectEntries([.Message(100, 100, "m100", [], []), .Message(Int32.max, 200, "m200", [], [])])
    }
    
    func testFillHoleLowerToUpperPartial() {
        addHole(100)
        
        fillHole(1, HoleFill(complete: false, direction: .LowerToUpper), [(100, 100, "m100", []), (200, 200, "m200", [])])
        expectEntries([.Message(100, 100, "m100", [], []), .Message(200, 200, "m200", [], []), .Hole(201, Int32.max, Int32.max)])
    }
    
    func testFillHoleBetweenMessagesUpperToLower() {
        addHole(1)
        
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        
        fillHole(199, HoleFill(complete: false, direction: .UpperToLower), [(150, 150, "m150", [])])
        
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], []), .Hole(101, 149, 150), .Message(150, 150, "m150", [], []), .Message(200, 200, "m200", [], []), .Hole(201, Int32.max, Int32.max)])
    }
    
    func testFillHoleBetweenMessagesLowerToUpper() {
        addHole(1)
        
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        
        fillHole(199, HoleFill(complete: false, direction: .LowerToUpper), [(150, 150, "m150", [])])
        
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], []), .Message(150, 150, "m150", [], []), .Hole(151, 199, 200), .Message(200, 200, "m200", [], []), .Hole(201, Int32.max, Int32.max)])
    }
    
    func testFillHoleBetweenMessagesComplete() {
        addHole(1)
        
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        
        fillHole(199, HoleFill(complete: true, direction: .UpperToLower), [(150, 150, "m150", [])])
        
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], []), .Message(150, 150, "m150", [], []), .Message(200, 200, "m200", [], []), .Hole(201, Int32.max, Int32.max)])
    }
    
    func testFillHoleBetweenMessagesWithMessage() {
        addMessage(200, 200, "m200")
        addMessage(202, 202, "m202")
        addHole(201)
        addMessage(201, 201, "m201")
        
        expectEntries([.Message(200, 200, "m200", [], []), .Message(201, 201, "m201", [], []), .Message(202, 202, "m202", [], [])])
    }
    
    func testFillHoleWithNoMessagesComplete() {
        addMessage(100, 100, "m100")
        addHole(1)
        
        fillHole(99, HoleFill(complete: true, direction: .UpperToLower), [])
        
        expectEntries([.Message(100, 100, "m100", [], [])])
    }
    
    func testFillHoleIgnoreOverMessage() {
        addMessage(100, 100, "m100")
        addMessage(101, 101, "m101")
        
        fillHole(100, HoleFill(complete: true, direction: .UpperToLower), [(90, 90, "m90", [])])
        
        expectEntries([.Message(90, 90, "m90", [], []), .Message(100, 100, "m100", [], []), .Message(101, 101, "m101", [], [])])
    }
    
    func testFillHoleWithOverflow() {
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .UpperToLower), [(150, 150, "m150", []), (300, 300, "m300", [])])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 149, 150), .Message(150, 150, "m150", [], []), .Message(200, 200, "m200", [], []), .Message(300, 300, "m300", [], [])])
    }
    
    func testIgnoreHoleOverMessageBetweenMessages() {
        addMessage(199, 199, "m199")
        addMessage(200, 200, "m200")
        addHole(200)
        
        expectEntries([.Message(199, 199, "m199", [], []), .Message(200, 200, "m200", [], [])])
    }
    
    func testMergeHoleAfterDeletingMessage() {
        addMessage(100, 100, "m100")
        addHole(1)
        addHole(200)
        
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)])
        
        removeMessages([100])
        
        expectEntries([.Hole(1, Int32.max, Int32.max)])
    }
    
    func testMergeHoleLowerAfterDeletingMessage() {
        addMessage(100, 100, "m100")
        addHole(1)
        addMessage(200, 200, "m200")
        
        removeMessages([100])
        
        expectEntries([.Hole(1, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testMergeHoleUpperAfterDeletingMessage() {
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        addHole(300)
        
        removeMessages([200])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)])
    }
    
    func testExtendLowerHoleAfterDeletingMessage() {
        addMessage(100, 100, "m100")
        addHole(100)
        
        removeMessages([100])
        
        expectEntries([.Hole(1, Int32.max, Int32.max)])
    }
    
    func testExtendUpperHoleAfterDeletingMessage() {
        addMessage(100, 100, "m100")
        addHole(101)
        
        removeMessages([100])
        
        expectEntries([.Hole(1, Int32.max, Int32.max)])
    }
    
    func testDeleteMessageBelowMessage() {
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        removeMessages([100])
        
        expectEntries([.Message(200, 200, "m200", [], [])])
    }
    
    func testDeleteMessageAboveMessage() {
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        removeMessages([200])
        
        expectEntries([.Message(100, 100, "m100", [], [])])
    }
    
    func testDeleteMessageBetweenMessages() {
        addMessage(100, 100, "m100")
        addMessage(200, 200, "m200")
        addMessage(300, 300, "m300")
        removeMessages([200])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Message(300, 300, "m300", [], [])])
    }
    
    func testAddUnsent() {
        addMessage(100, 100, "m100", [], [.Unsent])
        expectEntries([.Message(100, 100, "m100", [], [.Unsent])])
        expectUnsent([100])
    }
    
    func testRemoveUnsent() {
        addMessage(100, 100, "m100", [], [.Unsent])
        expectEntries([.Message(100, 100, "m100", [], [.Unsent])])
        expectUnsent([100])
        
        removeMessages([100])
        expectEntries([])
        expectUnsent([])
    }
    
    func testUpdateUnsentToSentSameIndex() {
        addMessage(100, 100, "m100", [], [.Unsent])
        expectEntries([.Message(100, 100, "m100", [], [.Unsent])])
        expectUnsent([100])
        
        updateMessage(100, 100, 100, "m100", [], [], [])
        expectEntries([.Message(100, 100, "m100", [], [])])
        expectUnsent([])
    }
    
    func testUpdateUnsentToFailed() {
        addMessage(100, 100, "m100", [], [.Unsent])
        expectEntries([.Message(100, 100, "m100", [], [.Unsent])])
        expectUnsent([100])
        
        updateMessage(100, 100, 100, "m100", [], [.Unsent, .Failed], [])
        expectEntries([.Message(100, 100, "m100", [], [.Unsent, .Failed])])
        expectUnsent([])
    }
    
    func testUpdateDifferentIndex() {
        addMessage(100, 100, "m100", [], [.Unsent])
        expectEntries([.Message(100, 100, "m100", [], [.Unsent])])
        expectUnsent([100])
        
        updateMessage(100, 200, 200, "m100", [], [], [])
        expectEntries([.Message(200, 200, "m100", [], [])])
        expectUnsent([])
    }
    
    func testUpdateDifferentIndexBreakHole() {
        addHole(1)
        
        addMessage(100, 100, "m100", [], [.Unsent])
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], [.Unsent]), .Hole(101, Int32.max, Int32.max)])
        expectUnsent([100])
        
        updateMessage(100, 200, 200, "m100", [], [], [])
        expectEntries([.Hole(1, 199, 200), .Message(200, 200, "m100", [], []), .Hole(201, Int32.max, Int32.max)])
        expectUnsent([])
    }
    
    func testInsertTaggedIntoEmpty() {
        addMessage(100, 100, "m100", [], [], MessageTags(rawValue: 1))
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: MessageTags(rawValue: 1))
    }
    
    func testInsertMultipleTagsIntoEmpty() {
        addMessage(200, 200, "m200", [], [], MessageTags(rawValue: 2))
        addMessage(100, 100, "m100", [], [], MessageTags(rawValue: 1 | 2))
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: MessageTags(rawValue: 1))
        expectEntries([.Message(100, 100, "m100", [], []), .Message(200, 200, "m200", [], [])], tagMask: MessageTags(rawValue: 2))
    }
    
    func testRemoveSingleTagged() {
        addMessage(100, 100, "m100", [], [], MessageTags(rawValue: 1))
        removeMessages([100])
        
        expectEntries([], tagMask: MessageTags(rawValue: 1))
    }
    
    func testRemoveMultipleTagged() {
        addMessage(200, 200, "m200", [], [], MessageTags(rawValue: 2))
        addMessage(100, 100, "m100", [], [], MessageTags(rawValue: 1 | 2))
        removeMessages([100])
        expectEntries([], tagMask: MessageTags(rawValue: 1))
        expectEntries([.Message(200, 200, "m200", [], [])], tagMask: MessageTags(rawValue: 2))
    }
    
    func testTagsInsertHoleIntoEmpty() {
        addHole(1)
        expectEntries([.Hole(1, Int32.max, Int32.max)], tagMask: [.First])
        expectEntries([.Hole(1, Int32.max, Int32.max)], tagMask: [.Second])
    }
    
    func testTagsBreakHoleWithMessage() {
        addHole(1)
        addMessage(100, 100, "m100", [], [], [.First])
        
        expectEntries([.Hole(1, 99, 100), .Message(100, 100, "m100", [], []), .Hole(101, Int32.max, Int32.max)], tagMask: [.First])
        expectEntries([.Hole(1, 99, 100), .Hole(101, Int32.max, Int32.max)], tagMask: [.Second])
    }
    
    func testTagsFillHoleUpperToLowerAllTags() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .UpperToLower), [(180, 180, "m180", [])])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 179, 180)], tagMask: [.First])
        expectEntries([.Hole(101, 179, 180), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 179, 180), .Message(180, 180, "m180", [], []), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleLowerToUpperAllTags() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .LowerToUpper), [(180, 180, "m180", [])])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(181, 199, 200)], tagMask: [.First])
        expectEntries([.Hole(181, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Message(180, 180, "m180", [], []), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleCompleteAllTags() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: true, direction: .UpperToLower), [(180, 180, "m180", [])])
        
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: [.First])
        expectEntries([.Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Message(180, 180, "m180", [], []), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleUpperToLowerSingleTagWithMessages() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .UpperToLower), [(180, 180, "m180", [])], [.First])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 179, 180)], tagMask: [.First])
        expectEntries([.Hole(101, 179, 180), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 179, 180), .Message(180, 180, "m180", [], []), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleLowerToUpperSingleTagWithMessages() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .LowerToUpper), [(180, 180, "m180", [])], [.First])
        
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(181, 199, 200)], tagMask: [.First])
        expectEntries([.Hole(101, 179, 180), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 179, 180), .Message(180, 180, "m180", [], []), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleCompleteSingleTagWithMessages() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: true, direction: .UpperToLower), [(180, 180, "m180", [])], [.First])
        
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: [.First])
        expectEntries([.Hole(101, 179, 180), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 179, 180), .Message(180, 180, "m180", [], []), .Hole(181, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleUpperToLowerSingleTagWithEmpty() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .UpperToLower), [], [.First])
        
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: [.First])
        expectEntries([.Hole(101, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleLowerToUpperSingleTagWithEmpty() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: false, direction: .LowerToUpper), [], [.First])
        
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: [.First])
        expectEntries([.Hole(101, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillHoleCompleteSingleTagWithEmpty() {
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.Second])
        addHole(150)
        
        fillHole(199, HoleFill(complete: true, direction: .UpperToLower), [], [.First])
        
        expectEntries([.Message(100, 100, "m100", [], [])], tagMask: [.First])
        expectEntries([.Hole(101, 199, 200), .Message(200, 200, "m200", [], [])], tagMask: [.Second])
        expectEntries([.Message(100, 100, "m100", [], []), .Hole(101, 199, 200), .Message(200, 200, "m200", [], [])])
    }
    
    func testTagsFillMultipleHolesSingleHole() {
        addHole(1)
        addMessage(100, 100, "m100", [], [], [.First])
        addMessage(200, 200, "m200", [], [], [.First])
        addMessage(300, 300, "m300", [], [], [.First])
        addMessage(400, 400, "m400", [], [], [.First])
        
        expectEntries([
            .Hole(1, 99, 100),
            .Message(100, 100, "m100", [], []),
            .Hole(101, 199, 200),
            .Message(200, 200, "m200", [], []),
            .Hole(201, 299, 300),
            .Message(300, 300, "m300", [], []),
            .Hole(301, 399, 400),
            .Message(400, 400, "m400", [], []),
            .Hole(401, Int32.max, Int32.max)
        ], tagMask: [.First])
        
        expectEntries([
            .Hole(1, 99, 100),
            .Hole(101, 199, 200),
            .Hole(201, 299, 300),
            .Hole(301, 399, 400),
            .Hole(401, Int32.max, Int32.max)
        ], tagMask: [.Second])
        
        fillMultipleHoles(500, HoleFill(complete: false, direction: .UpperToLower), [(500, 500, "m500", []), (350, 350, "m350", [])], [.Second], [.Second])
        
        expectEntries([
            .Hole(1, 99, 100),
            .Hole(101, 199, 200),
            .Hole(201, 299, 300),
            .Hole(301, 349, 350),
            .Message(350, 350, "m350", [], []),
            .Message(500, 500, "m500", [], [])
        ], tagMask: [.Second])
        
        expectEntries([
            .Hole(1, 99, 100),
            .Message(100, 100, "m100", [], []),
            .Hole(101, 199, 200),
            .Message(200, 200, "m200", [], []),
            .Hole(201, 299, 300),
            .Message(300, 300, "m300", [], []),
            .Hole(301, 349, 350),
            .Hole(351, 399, 400),
            .Message(400, 400, "m400", [], []),
            .Hole(401, 499, 500),
            .Hole(501, Int32.max, Int32.max)
        ], tagMask: [.First])
    }
    
    func testFullTextGetEmpty() {
        XCTAssert(self.textIndexTable!.search(peerId: nil, text: "abc", tags: nil).isEmpty)
    }
    
    func testFullTextMatch1() {
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 1), text: "a b c", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 2), text: "a b c d", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 3), text: "c d e", tags: [])
        
        var result = self.textIndexTable!.search(peerId: nil, text: "a", tags: nil).sorted()
        let testIds1: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 1),
            MessageId(peerId: peerId, namespace: 0, id: 2),
        ]
        XCTAssert(result == testIds1)
        
        result = self.textIndexTable!.search(peerId: nil, text: "c", tags: nil).sorted()
        let testIds2: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 1),
            MessageId(peerId: peerId, namespace: 0, id: 2),
            MessageId(peerId: peerId, namespace: 0, id: 3)
        ]
        XCTAssert(result == testIds2)
        
        result = self.textIndexTable!.search(peerId: nil, text: "d", tags: nil).sorted()
        let testIds3: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 2),
            MessageId(peerId: peerId, namespace: 0, id: 3)
        ]
        XCTAssert(result == testIds3)
        
        result = self.textIndexTable!.search(peerId: nil, text: "a b c", tags: nil).sorted()
        XCTAssert(result == testIds1)
        
        result = self.textIndexTable!.search(peerId: nil, text: "a b c d e", tags: nil).sorted()
        let testIds4: [MessageId] = [
        ]
        XCTAssert(result == testIds4)
        
        self.textIndexTable!.remove(messageId: MessageId(peerId: peerId, namespace: 0, id: 2))
        let testIds5: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 1),
            MessageId(peerId: peerId, namespace: 0, id: 3)
        ]
        result = self.textIndexTable!.search(peerId: nil, text: "c", tags: nil).sorted()
        XCTAssert(result == testIds5)
    }
    
    func testFullTextMatchLocal() {
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 1), text: "a b c", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 2), text: "a b c d", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: otherPeerId, namespace: 0, id: 1), text: "c d e", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: otherPeerId, namespace: 0, id: 2), text: "d e f", tags: [])
        
        var result = self.textIndexTable!.search(peerId: peerId, text: "a", tags: nil).sorted()
        let testIds1: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 1),
            MessageId(peerId: peerId, namespace: 0, id: 2),
            ]
        XCTAssert(result == testIds1)
        
        result = self.textIndexTable!.search(peerId: otherPeerId, text: "c", tags: nil).sorted()
        let testIds2: [MessageId] = [
            MessageId(peerId: otherPeerId, namespace: 0, id: 1),
        ]
        XCTAssert(result == testIds2)
        
        result = self.textIndexTable!.search(peerId: otherPeerId, text: "d", tags: nil).sorted()
        let testIds3: [MessageId] = [
            MessageId(peerId: otherPeerId, namespace: 0, id: 1),
            MessageId(peerId: otherPeerId, namespace: 0, id: 2)
        ]
        XCTAssert(result == testIds3)
    }
    
    func testFullTextMatchLocalTags() {
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 1), text: "a b c", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 2), text: "a b c d", tags: [])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 3), text: "a b c", tags: [tag1])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 4), text: "a b c", tags: [tag1, tag2])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 5), text: "a b c", tags: [tag1, tag2])
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 6), text: "a b c", tags: [tag2])
        
        var result = self.textIndexTable!.search(peerId: peerId, text: "a b c", tags: nil).sorted()
        let testIds1: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 1),
            MessageId(peerId: peerId, namespace: 0, id: 2),
            MessageId(peerId: peerId, namespace: 0, id: 3),
            MessageId(peerId: peerId, namespace: 0, id: 4),
            MessageId(peerId: peerId, namespace: 0, id: 5),
            MessageId(peerId: peerId, namespace: 0, id: 6),
        ]
        XCTAssert(result == testIds1)
        
        result = self.textIndexTable!.search(peerId: peerId, text: "a b c", tags: [tag1]).sorted()
        let testIds2: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 3),
            MessageId(peerId: peerId, namespace: 0, id: 4),
            MessageId(peerId: peerId, namespace: 0, id: 5),
        ]
        XCTAssert(result == testIds2)
        
        result = self.textIndexTable!.search(peerId: peerId, text: "a b c", tags: [tag2]).sorted()
        let testIds3: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 4),
            MessageId(peerId: peerId, namespace: 0, id: 5),
            MessageId(peerId: peerId, namespace: 0, id: 6),
        ]
        XCTAssert(result == testIds3)
        
        result = self.textIndexTable!.search(peerId: peerId, text: "a b c", tags: [tag1, tag2]).sorted()
        let testIds4: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 4),
            MessageId(peerId: peerId, namespace: 0, id: 5),
        ]
        XCTAssert(result == testIds4)
    }
    
    func testFullTextEscape1() {
        self.textIndexTable!.add(messageId: MessageId(peerId: peerId, namespace: 0, id: 1), text: "abc' def'", tags: [])
        var result = self.textIndexTable!.search(peerId: nil, text: "abc'", tags: nil).sorted()
        let testIds1: [MessageId] = [
            MessageId(peerId: peerId, namespace: 0, id: 1)
            ]
        XCTAssert(result == testIds1)
        
        result = self.textIndexTable!.search(peerId: nil, text: "abc' def'", tags: nil).sorted()
        XCTAssert(result == testIds1)
        
        result = self.textIndexTable!.search(peerId: nil, text: "abc' AND def", tags: nil).sorted()
        XCTAssert(result.isEmpty)
    }
    
    func testSummary1() {
        expectSummary(nil)
        addMessage(100, 100, "m100", [], [], [.First])
        expectSummary(nil)
        addMessage(200, 200, "m200", [], [], [.Summary])
        expectSummary(MessageHistoryTagNamespaceSummary(version: 0, count: 1, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 0)))
        replaceSummary(2, 200)
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 2, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        addMessage(150, 150, "m200", [], [], [.Summary])
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 2, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        removeMessages([150])
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 1, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        removeMessages([200])
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 0, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        addMessage(300, 300, "m300", [], [], [.Summary])
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 1, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        addHole(400)
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 1, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
    }
    
    func testSummary2() {
        addHole(400)
        expectSummary(nil)
    }
    
    func testSummary3() {
        addMessage(200, 200, "m200", [], [], [.Summary])
        addHole(100)
        replaceSummary(0, 200)
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 0, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        addMessage(300, 300, "m300", [], [], [.Summary])
        addHole(250)
        expectSummary(MessageHistoryTagNamespaceSummary(version: 1, count: 1, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 200)))
        replaceSummary(10, 300)
        expectSummary(MessageHistoryTagNamespaceSummary(version: 2, count: 10, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 300)))
        self.updateMessage(300, 300, 300, "m300", [], [], [])
        expectSummary(MessageHistoryTagNamespaceSummary(version: 2, count: 9, range: MessageHistoryTagNamespaceCountValidityRange(maxId: 300)))
    }
    
    func testPendingMessageActions1() {
        expectMessageAction(100, pendingAction1, nil)
        expectPeerNamespaceMessageActionCount(0)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction1)
        setMessageAction(100, pendingAction1, PendingMessageAction1())
        expectMessageAction(100, pendingAction1, nil)
        expectPeerNamespaceMessageActionCount(0)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction1)
        addMessage(100, 100)
        expectMessageAction(100, pendingAction1, nil)
        expectPeerNamespaceMessageActionCount(0)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction1)
        setMessageAction(100, pendingAction1, PendingMessageAction1())
        expectMessageAction(100, pendingAction1, PendingMessageAction1())
        expectPeerNamespaceMessageActionCount(1)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction2)
        removeMessages([100])
        expectMessageAction(100, pendingAction1, nil)
        expectPeerNamespaceMessageActionCount(0)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction2)
        
        addMessage(100, 100)
        setMessageAction(100, pendingAction1, PendingMessageAction1())
        expectPeerNamespaceMessageActionCount(1)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction2)
        
        setMessageAction(100, pendingAction1, PendingMessageAction1())
        expectPeerNamespaceMessageActionCount(1)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction2)
        
        setMessageAction(100, pendingAction2, PendingMessageAction2())
        expectPeerNamespaceMessageActionCount(2)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction2)
        
        addMessage(200, 200)
        setMessageAction(200, pendingAction1, PendingMessageAction1())
        expectPeerNamespaceMessageActionCount(3)
        expectPeerNamespaceActionMessageActionCount(2, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction2)
        expectPeerMessageActions(pendingAction1, [(100, PendingMessageAction1()), (200, PendingMessageAction1())])
        expectPeerMessageActions(pendingAction2, [(100, PendingMessageAction2())])
        
        removeMessages([100])
        expectPeerNamespaceMessageActionCount(1)
        expectPeerNamespaceActionMessageActionCount(1, pendingAction1)
        expectPeerNamespaceActionMessageActionCount(0, pendingAction2)
        expectPeerMessageActions(pendingAction2, [])
        expectPeerMessageActions(pendingAction1, [(200, PendingMessageAction1())])
    }
    
    func testPendingMessageActions2() {
        
    }
}
