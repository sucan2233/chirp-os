import Foundation
import XCTest
@testable import BirdingCore

/// Transport contracts only. Persistence, quota and civil-time tests belong to GiftLedgerTests.
final class VisitorGiftAuthorizationTests:XCTestCase {
    private let binding=GiftBinding(requestID:"17",visitorArchiveSeed:"73",visitorID:"99",
        birdID:BirdID(1),species:.azureWingedMagpie,source:.automatic,leafID:ScenePropID(5),
        receiverSlot:1,receiverRevision:3)
    private let tokenID=UUID(uuidString:"00000000-0000-4000-8000-000000000017")!

    private func object<T:Encodable>(_ value:T) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
    }
    private func decode<T:Decodable>(_ type:T.Type,_ object:[String:Any]) throws -> T {
        try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:object))
    }

    func testRequestAndGrantedTokenRetainEveryIdentityAndSourceAcrossEncoding() throws {
        XCTAssertTrue(binding.isValid)
        let request=GiftAuthorizationRequest(binding:binding)
        XCTAssertEqual(try JSONDecoder().decode(GiftAuthorizationRequest.self,
            from:JSONEncoder().encode(request)),request)
        let token=GiftAuthorizationToken(id:tokenID,binding:binding)
        let result=GiftAuthorizationResult(granted:token)
        XCTAssertTrue(result.isValid);XCTAssertNil(result.denial)
        let restored=try JSONDecoder().decode(GiftAuthorizationResult.self,from:JSONEncoder().encode(result))
        XCTAssertEqual(restored,result);XCTAssertEqual(restored.token?.id,tokenID)
        XCTAssertEqual(restored.binding.requestID,"17")
        XCTAssertEqual(restored.binding.visitorArchiveSeed,"73")
        XCTAssertEqual(restored.binding.visitorID,"99")
        XCTAssertEqual(restored.binding.birdID,BirdID(1))
        XCTAssertEqual(restored.binding.species,.azureWingedMagpie)
        XCTAssertEqual(restored.binding.source,.automatic)
        XCTAssertEqual(restored.binding.leafID,ScenePropID(5))
        XCTAssertEqual(restored.binding.receiverSlot,1)
        XCTAssertEqual(restored.binding.receiverRevision,3)
    }

    func testBindingDecoderRejectsInvalidIdentitiesWithoutCoercingTextOrNumbers() throws {
        let original=try object(binding)
        let invalid:[(String,[Any])]=[
            ("requestID",["0","01","+1"," 1","1 ","-1","18446744073709551616",1,true]),
            ("visitorArchiveSeed",["00","+0","-1","18446744073709551616",0]),
            ("visitorID",["0","099","-1","","18446744073709551616",99]),
            ("birdID",[["rawValue":0],["rawValue":-1],"1"]),
            ("species",["treeSparrow","yellowRumpedFlycatcher","unknown"]),
            ("source",["user","unknown"]),
            ("leafID",[["rawValue":0],["rawValue":-1],"1"]),
            ("receiverSlot",[0,4,-1,"1"]),
            ("receiverRevision",[0,-1,"3"])
        ]
        for (key,values) in invalid {
            for value in values {
                var bad=original;bad[key]=value
                XCTAssertThrowsError(try decode(GiftBinding.self,bad),"\(key)=\(value)")
            }
            var absent=original;absent.removeValue(forKey:key)
            XCTAssertThrowsError(try decode(GiftBinding.self,absent),key)
        }
        var boundary=original
        for key in ["requestID","visitorArchiveSeed","visitorID"] {boundary[key]="18446744073709551615"}
        XCTAssertTrue(try decode(GiftBinding.self,boundary).isValid)
        boundary["visitorArchiveSeed"]="0";boundary["source"]="preview";boundary["receiverSlot"]=3
        XCTAssertTrue(try decode(GiftBinding.self,boundary).isValid)
    }

    func testResultRequiresExactlyOneOutcomeAndTokenBoundToAllNineFields() throws {
        let token=GiftAuthorizationToken(id:tokenID,binding:binding)
        let granted=try object(GiftAuthorizationResult(granted:token))
        var both=granted;both["denial"]="timedOut"
        XCTAssertThrowsError(try decode(GiftAuthorizationResult.self,both))
        var neither=granted;neither.removeValue(forKey:"token")
        XCTAssertThrowsError(try decode(GiftAuthorizationResult.self,neither))
        let alternate:[(String,Any)]=[
            ("requestID","18"),("visitorArchiveSeed","74"),("visitorID","100"),
            ("birdID",try JSONSerialization.jsonObject(with:JSONEncoder().encode(BirdID(2)))),
            ("source","preview"),
            ("leafID",try JSONSerialization.jsonObject(with:JSONEncoder().encode(ScenePropID(6)))),
            ("receiverSlot",2),("receiverRevision",4)
        ]
        for (key,value) in alternate {
            var outer=granted,inner=try object(token),other=try object(binding)
            other[key]=value;inner["binding"]=other;outer["token"]=inner
            XCTAssertThrowsError(try decode(GiftAuthorizationResult.self,outer),key)
        }
        // The ninth identity is species; no second species is authorized even
        // when both the outer binding and token claim it consistently.
        var unsupported=granted,other=try object(binding),inner=try object(token)
        other["species"]="treeSparrow";inner["binding"]=other
        unsupported["binding"]=other;unsupported["token"]=inner
        XCTAssertThrowsError(try decode(GiftAuthorizationResult.self,unsupported))
    }

    func testAllPlatformDenialsIncludingTimeoutAreExplicitReplayableInputs() throws {
        let reasons:[GiftAuthorizationDenial]=[.invalidRequest,.namespaceUnavailable,.notEligible,.alreadyGranted,
            .globalCooldown,.clockRollback,.storageUnavailable,.unsupportedVersion,.invalidLedger,.ledgerFull,.busy,.timedOut]
        let names=["invalidRequest","namespaceUnavailable","notEligible","alreadyGranted","globalCooldown",
            "clockRollback","storageUnavailable","unsupportedVersion","invalidLedger","ledgerFull","busy","timedOut"]
        XCTAssertEqual(reasons.map(\.rawValue),names)
        for reason in reasons {
            let result=GiftAuthorizationResult(denied:binding,reason:reason)
            XCTAssertTrue(result.isValid);XCTAssertNil(result.token)
            XCTAssertEqual(try JSONDecoder().decode(GiftAuthorizationResult.self,
                from:JSONEncoder().encode(result)),result)
        }
        var invalid=try object(GiftAuthorizationResult(denied:binding,reason:.timedOut))
        invalid["denial"]="futureDenial"
        XCTAssertThrowsError(try decode(GiftAuthorizationResult.self,invalid))
    }
}
