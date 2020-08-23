//
//  FuzzingTests.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/28/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import XCTest
@testable import Starscream

class FuzzingTests: XCTestCase {
    
    var websocket: WebSocket!
    var transport: MockTransport!
    var server: MockServer!
    var framer: WSFramer!
    var uuid = ""
    
    override func setUp() {
        super.setUp()
        
        let s = MockServer()
        let _ = s.start(address: "", port: 0)
        server = s
        
        let transport = MockTransport(server: s)
        uuid = transport.uuid
        self.transport = transport
        
        let url = URL(string: "http://vluxe.io/ws")! //domain doesn't matter with the mock transport
        let request = URLRequest(url: url)
        
        framer = WSFramer()
        let engine = WSEngine(transport: transport, certPinner: nil, headerValidator: FoundationSecurity(), httpHandler: FoundationHTTPHandler(), framer: framer, compressionHandler: nil)
        websocket = WebSocket(request: request, engine: engine)
    }
    
    override func tearDown() {
        transport.disconnect()
        websocket.disconnect()
        
        super.tearDown()
    }
    
    func runWebsocket(timeout: TimeInterval = 10, expectedFulfillmentCount: Int = 1, invertExpectation: Bool = false, serverAction: @escaping ((ServerEvent) -> Bool)) {
        let e = expectation(description: "Websocket event timeout")
        e.expectedFulfillmentCount = expectedFulfillmentCount
        e.isInverted = invertExpectation
        server.onEvent = { event in
            let done = serverAction(event)
            if done {
                e.fulfill()
            }
        }
        
        websocket.onEvent = { event in
            switch event {
            case .text(let string):
                self.websocket.write(string: string)
            case .binary(let data):
                self.websocket.write(data: data)
            case .ping(_):
                break
            case .pong(_):
                break
            case .connected(_):
                break
            case .disconnected(let reason, let code):
                print("reason: \(reason) code: \(code)")
            case .error(_):
                break
            case .viabilityChanged(_):
                break
            case .reconnectSuggested(_):
                break
            case .cancelled:
                break
            }
        }
        websocket.connect()
        waitForExpectations(timeout: timeout) { error in
            if let error = error {
                XCTFail("waitForExpectationsWithTimeout errored: \(error)")
            }
        }
    }
    
    func sendMessage(string: String, isBinary: Bool) {
        let payload = string.data(using: .utf8)!
        let code: FrameOpCode = isBinary ? .binaryFrame : .textFrame
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: payload, opcode: code)
            case .text(let conn, let text):
                if text == string && !isBinary {
                    conn.write(data: Data(), opcode: .connectionClose)
                    return true //success!
                } else {
                    XCTFail("text does not match: source: [\(string)] response: [\(text)]")
                }
            case .binary(let conn, let data):
                if payload.count == data.count && isBinary {
                    conn.write(data: Data(), opcode: .connectionClose)
                    return true //success!
                } else {
                    XCTFail("binary does not match: source: [\(payload.count)] response: [\(data.count)]")
                }
            case .disconnected(_, _, _):
                return false
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func sendPing(payload: String, isBinary: Bool = false, expectSuccess: Bool = true) {
        let payload = payload.data(using: .utf8)!
        let code: FrameOpCode = .ping
        
        let connection = server.connection(for: self.transport)
        if connection != nil {
            connection!.write(data: payload, opcode: code)
        }
        
        runWebsocket { event in
            switch event {
            case .connected(let conn, _) where connection == nil:
                conn.write(data: payload, opcode: code)
            case .pong(let conn, let pong):
                if pong == payload {
                    conn.write(data: Data(), opcode: .connectionClose)
                    return true
                } else {
                    XCTFail()//"text does not match: source: [\(string)] response: [\(text)]")
                }
            case .disconnected(_, _, _):
                return !expectSuccess
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func sendPong(payload: String, isBinary: Bool = false) {
        let payload = payload.data(using: .utf8)!
        let code: FrameOpCode = .pong
        runWebsocket(timeout: 5.0, invertExpectation: true) { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: payload, opcode: code)
            case .disconnected(_, _, _):
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    //These are the Autobahn test cases as unit tests
    
    // MARK: - Framing cases
    
    // case 1.1.1
    func testCase1() {
        sendMessage(string: "", isBinary: false)
    }
    
    // case 1.1.2
    func testCase2() {
        sendMessage(string: String(repeating: "*", count: 125), isBinary: false)
    }
    
    // case 1.1.3
    func testCase3() {
        sendMessage(string: String(repeating: "*", count: 126), isBinary: false)
    }
    
    // case 1.1.4
    func testCase4() {
        sendMessage(string: String(repeating: "*", count: 127), isBinary: false)
    }
    
    // case 1.1.5
    func testCase5() {
        sendMessage(string: String(repeating: "*", count: 128), isBinary: false)
    }
    
    // case 1.1.6
    func testCase6() {
        sendMessage(string: String(repeating: "*", count: 65535), isBinary: false)
    }
    
    // case 1.1.7, 1.1.8
    func testCase7() {
        sendMessage(string: String(repeating: "*", count: 65536), isBinary: false)
    }
    
    // case 1.2.1
    func testCase9() {
        sendMessage(string: "", isBinary: true)
    }
    
    // case 1.2.2
    func testCase10() {
        sendMessage(string: String(repeating: "*", count: 125), isBinary: true)
    }
    
    // case 1.2.3
    func testCase11() {
        sendMessage(string: String(repeating: "*", count: 126), isBinary: true)
    }
    
    // case 1.2.4
    func testCase12() {
        sendMessage(string: String(repeating: "*", count: 127), isBinary: true)
    }
    
    // case 1.2.5
    func testCase13() {
        sendMessage(string: String(repeating: "*", count: 128), isBinary: true)
    }
    
    // case 1.2.6
    func testCase14() {
        sendMessage(string: String(repeating: "*", count: 65535), isBinary: true)
    }
    
    // case 1.2.7, 1.2.8
    func testCase15() {
        sendMessage(string: String(repeating: "*", count: 65536), isBinary: true)
    }
    
    // case 2.1
    func testCase2_1() {
        sendPing(payload: "")
    }
    
    // case 2.2
    func testCase2_2() {
        sendPing(payload: "*")
    }
    
    // case 2.3
    func testCase2_3() {
        sendPing(payload: "*", isBinary: true)
    }
    
    // case 2.4
    func testCase2_4() {
        sendPing(payload: String(repeating: "*", count: 125), isBinary: true)
    }
    
    // case 2.5, 2.6
    func testCase2_5_6() {
        sendPing(payload: String(repeating: "*", count: 126), isBinary: true, expectSuccess: false)
    }
    
    // case 2.7
    func testCase2_7() {
        sendPong(payload: "")
    }
    
    // case 2.8
    func testCase2_8() {
        sendPong(payload: "*")
    }
    
    // case 2.9
    func testCase2_9() {
        sendPong(payload: "*")
        sendPing(payload: "*")
    }
    
    // case 2.10, 2.11
    func testCase2_10_11() {
        for _ in 0..<10 {
            sendPing(payload: "*")
        }
    }
    
    
    // case 3...
    
    // case 4.1.1
    func testCase4_1_1() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: Data(), opcode: FrameOpCode(rawValue: 3)!)
            case .disconnected(_, _, _):
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_1_2() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: FrameOpCode(rawValue: 4)!)
            case .disconnected(_, _, _):
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_1_3() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .textFrame)
                conn.write(data: Data(), opcode: .raw(value: 0x5))
            case .text(let conn, let text):
                XCTAssertEqual(text, "*")
                conn.write(data: Data(), opcode: .ping)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_1_4() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .textFrame)
                conn.write(data: Data(), opcode: .raw(value: 0x6))
            case .text(let conn, let text):
                XCTAssertEqual(text, "*")
                conn.write(data: Data(), opcode: .ping)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_1_5() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .textFrame)
                conn.write(data: Data(), opcode: .raw(value: 0x7))
            case .text(let conn, let text):
                XCTAssertEqual(text, "*")
                conn.write(data: Data(), opcode: .ping)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_2_1() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: Data(), opcode: .raw(value: 0x11))
            case .disconnected(_, _, _):
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_2_2() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .raw(value: 0x12))
            case .disconnected(_, _, _):
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_2_3() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .textFrame)
                conn.write(data: Data(), opcode: .raw(value: 0x13))
            case .text(let conn, let text):
                XCTAssertEqual(text, "*")
                conn.write(data: Data(), opcode: .ping)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_2_4() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .textFrame)
                conn.write(data: "*".data(using: .utf8)!, opcode: .raw(value: 0x14))
            case .text(let conn, let text):
                XCTAssertEqual(text, "*")
                conn.write(data: Data(), opcode: .ping)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase4_2_5() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "*".data(using: .utf8)!, opcode: .textFrame)
                conn.write(data: "*".data(using: .utf8)!, opcode: .raw(value: 0x15))
            case .text(let conn, let text):
                XCTAssertEqual(text, "*")
                conn.write(data: Data(), opcode: .ping)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_1() {
        runWebsocket(expectedFulfillmentCount: 2) { [weak self] event in
            guard let self = self else { return false }
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .ping, payload: Data(), isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: lastFrame)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func stestCase5_2() { // Error with control frame
        runWebsocket(expectedFulfillmentCount: 2) { [weak self] event in
            guard let self = self else { return false }
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .pong, payload: Data(), isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: lastFrame)
            case .disconnected(_, _, _):
                return true
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_3() { // textCase5_5
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: "*".data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: lastFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "**")
                return true
            case .disconnected(_, _, _):
                return false
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_5() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: "***".data(using: .utf8)!, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: "***".data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: lastFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "******")
                return true
            case .disconnected(_, _, _):
                return false
            case .pong:
                XCTFail("Pong for ping should not be received.")
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_6() { // testCase5_7
        runWebsocket(expectedFulfillmentCount: 2) { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: "**".data(using: .utf8)!, isCompressed: false)
                let ping = conn.createWriteFrame(opcode: .ping, payload: "xx".data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: ping)
                self.transport.received(data: lastFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "****")
                return true
            case .disconnected(_, _, _):
                return false
            case .pong:
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_8() {
        runWebsocket(expectedFulfillmentCount: 2) { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: "*".data(using: .utf8)!, isCompressed: false)
                let ping = conn.createWriteFrame(opcode: .ping, payload: "xx".data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: ping)
                self.transport.received(data: lastFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "**")
                return true
            case .disconnected(_, _, _):
                return false
            case .pong:
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_9() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                var continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isCompressed: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!, isCompressed: false)
                continuationFrame.append(textFrame)
                
                self.transport.received(data: continuationFrame)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect() // Forcefully disconnect transport to stop receiving
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_10() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isCompressed: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: continuationFrame)
                self.transport.received(data: textFrame)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_11() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isCompressed: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: continuationFrame)
                self.transport.received(data: textFrame)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_12() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                var continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isFinal: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!, isCompressed: false)
                continuationFrame.append(textFrame)
                
                self.transport.received(data: continuationFrame)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_13() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isFinal: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!)
                
                self.transport.received(data: continuationFrame)
                self.transport.received(data: textFrame)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_14() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isFinal: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!)
                
                self.transport.received(data: continuationFrame)
                self.transport.received(data: textFrame)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_15() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                var textFrame1 = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isFinal: false)
                let textFrame2 = conn.createWriteFrame(opcode: .continueFrame, payload: "*".data(using: .utf8)!)
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isFinal: false)
                let textFrame = conn.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!)
                
                // One chop
                textFrame1.append(textFrame2)
                textFrame1.append(continuationFrame)
                textFrame1.append(textFrame)
                
                self.transport.received(data: textFrame1)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_16() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data(), isFinal: false)
                
                let textFrame1 = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isFinal: false)
                let textFrame2 = conn.createWriteFrame(opcode: .continueFrame, payload: "*".data(using: .utf8)!)
                
                
                (0..<2).forEach { _ in
                    self.transport.received(data: continuationFrame)
                    self.transport.received(data: textFrame1)
                    self.transport.received(data: textFrame2)
                }
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_17() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let continuationFrame = conn.createWriteFrame(opcode: .continueFrame, payload: Data())
                
                let textFrame1 = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isFinal: false)
                let textFrame2 = conn.createWriteFrame(opcode: .continueFrame, payload: "*".data(using: .utf8)!)
                
                
                (0..<2).forEach { _ in
                    self.transport.received(data: continuationFrame)
                    self.transport.received(data: textFrame1)
                    self.transport.received(data: textFrame2)
                }
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_18() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                var textFrame1 = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!, isFinal: false)
                let textFrame2 = conn.createWriteFrame(opcode: .textFrame, payload: "*".data(using: .utf8)!)
                textFrame1.append(textFrame2)
                
                self.transport.received(data: textFrame1)
            case .text:
                XCTFail("Text should not be received after FIN")
            case .disconnected(_, _, _):
                self.transport.disconnect()
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase5_19() {
        runWebsocket(expectedFulfillmentCount: 3) { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                var textFrames = [
                    conn.createWriteFrame(opcode: .textFrame, payload: "1".data(using: .utf8)!, isFinal: false),
                    conn.createWriteFrame(opcode: .continueFrame, payload: "2".data(using: .utf8)!, isFinal: false),
                    conn.createWriteFrame(opcode: .continueFrame, payload: "3".data(using: .utf8)!, isFinal: false),
                    conn.createWriteFrame(opcode: .continueFrame, payload: "4".data(using: .utf8)!, isFinal: false),
                    conn.createWriteFrame(opcode: .continueFrame, payload: "5".data(using: .utf8)!)
                ]
                let ping = conn.createWriteFrame(opcode: .ping, payload: "ping".data(using: .utf8)!)
                
                self.transport.received(data: textFrames.removeFirst())
                self.transport.received(data: textFrames.removeFirst())
                self.transport.received(data: ping)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.transport.received(data: textFrames.removeFirst())
                    self.transport.received(data: textFrames.removeFirst())
                    self.transport.received(data: ping)
                    self.transport.received(data: textFrames.removeFirst())
                }
            case .pong(_, let data):
                guard let data = data, let text = String(data: data, encoding: .utf8) else { return false }
                XCTAssertEqual(text, "ping")
                return true
            case .text(_, let text):
                XCTAssertEqual(text, "12345")
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    // testCase 5.20
    
    func testCase6_1_1() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: "".data(using: .utf8)!, opcode: .textFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "")
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_1_2() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let textData = "".data(using: .utf8)!
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: textData, isFinal: false)
                let secondFrame = conn.createWriteFrame(opcode: .continueFrame, payload: textData, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: textData, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: secondFrame)
                self.transport.received(data: lastFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "")
                return true
            default:
                print("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_1_3() {
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let emptyText = "".data(using: .utf8)!
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: emptyText, isFinal: false)
                let secondFrame = conn.createWriteFrame(opcode: .continueFrame, payload: "**".data(using: .utf8)!, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: emptyText, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: secondFrame)
                self.transport.received(data: lastFrame)
            case .text(_, let text):
                XCTAssertEqual(text, "**")
                return true
            default:
                print("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_2_1() {
        let text = """
        MESSAGE:
        Hello-µ@ßöäüàá-UTF-8!!
        48656c6c6f2dc2b540c39fc3b6c3a4c3bcc3a0c3a12d5554462d382121
        """
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: text.data(using: .utf8)!, opcode: .textFrame)
            case .text(_, let receivedText):
                XCTAssertEqual(receivedText, text)
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_2_2() {
        let text1 = """
        Hello-µ@ßöä
        48656c6c6f2dc2b540c39fc3b6c3a4
        """
        let text2 = """
        üàá-UTF-8!!
        c3bcc3a0c3a12d5554462d382121
        """
        
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: text1.data(using: .utf8)!, isFinal: false)
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: text2.data(using: .utf8)!, isCompressed: false)
                
                self.transport.received(data: firstFrame)
                self.transport.received(data: lastFrame)
            case .text(_, let receivedText):
                XCTAssertEqual(receivedText, "\(text1)\(text2)")
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_2_3() {
        let text = """
        Hello-µ@ßöäüàá-UTF-8!!
        48656c6c6f2dc2b540c39fc3b6c3a4c3bcc3a0c3a12d5554462d382121
        """
        let datas = text.compactMap { String($0).data(using: .utf8) }
        
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: datas[0], isFinal: false)
                self.transport.received(data: firstFrame)
                
                for i in 1..<(datas.count - 1) {
                    let frame = conn.createWriteFrame(opcode: .continueFrame, payload: datas[i], isFinal: false)
                    self.transport.received(data: frame)
                }
                
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: datas.last!, isCompressed: false)
                self.transport.received(data: lastFrame)
            case .text(_, let receivedText):
                XCTAssertEqual(receivedText, text)
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_2_4() {
        let text = """
        κόσμε
        cebae1bdb9cf83cebcceb5
        """
        let datas = text.compactMap { String($0).data(using: .utf8) }
        
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                guard let conn = (conn as? MockConnection) else { return false }
                
                let firstFrame = conn.createWriteFrame(opcode: .textFrame, payload: datas[0], isFinal: false)
                self.transport.received(data: firstFrame)
                
                for i in 1..<(datas.count - 1) {
                    let frame = conn.createWriteFrame(opcode: .continueFrame, payload: datas[i], isFinal: false)
                    self.transport.received(data: frame)
                }
                
                let lastFrame = conn.createWriteFrame(opcode: .continueFrame, payload: datas.last!, isCompressed: false)
                self.transport.received(data: lastFrame)
            case .text(_, let receivedText):
                XCTAssertEqual(receivedText, text)
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    func testCase6_3_1() {
        let data = Data([0xce, 0xba, 0xe1, 0xbd, 0xb9, 0xcf, 0x83, 0xce, 0xbc, 0xce, 0xb5, 0xed, 0xa0, 0x80])
        
        runWebsocket { event in
            switch event {
            case .connected(let conn, _):
                conn.write(data: data, opcode: .textFrame)
            case .disconnected:
                return true
            default:
                XCTFail("recieved unexpected server event: \(event)")
            }
            return false
        }
    }
    
    
    //TODO: the rest of them.
}

extension Data {
    func split(into chunkCount: Int) -> [Data] {
        let dataLen = (self as NSData).length
        
        assert(dataLen > chunkCount)
        
        let diff = dataLen / chunkCount
        var chunks:[Data] = [Data]()
        
        for chunkCounter in 0..<chunkCount {
            var chunk:Data
            let chunkBase = chunkCounter * diff
            
            let range = chunkBase..<(chunkBase + diff)
            chunk = self.subdata(in: range)
            
            chunks.append(chunk)
        }
        return chunks
    }
}
