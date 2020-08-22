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
            case .text(let conn, let text):
                XCTFail("Should not happen")
            case .binary(let conn, let data):
                XCTFail("Should not happen")
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
            case .text:
                XCTFail("Should not happen")
            case .binary:
                XCTFail("Should not happen")
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
            case .binary:
                XCTFail("Should not happen")
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
            case .binary:
                XCTFail("Should not happen")
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
            case .binary:
                XCTFail("Should not happen")
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
            case .binary(let conn, let data):
                print("Data:\(data)")
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

    // func testCase5...
    func testCase5_1() {
        let ping = framer.createWriteFrame(opcode: .ping, payload: Data(), isCompressed: false)
        let datas = splitData(ping, into: 2)
        
        runWebsocket(expectedFulfillmentCount: 2) { [weak self] event in
            guard let self = self else { return false }
            switch event {
            case .connected:
                self.transport.received(data: datas[0])
                self.transport.received(data: datas[1])
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
    
    func testCase5_2() {
        let ping = framer.createWriteFrame(opcode: .pong, payload: Data(), isCompressed: false)
        let datas = splitData(ping, into: 2)
        
        runWebsocket(expectedFulfillmentCount: 2) { [weak self] event in
            guard let self = self else { return false }
            switch event {
            case .connected:
                self.transport.received(data: datas[0])
                self.transport.received(data: datas[1])
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

    func testCase5_3() {
        let ping = framer.createWriteFrame(opcode: .textFrame, payload: "**".data(using: .utf8)!, isCompressed: false)
        let datas = splitData(ping, into: 2)
        
        runWebsocket(expectedFulfillmentCount: 2) { [weak self] event in
            guard let self = self else { return false }
            switch event {
            case .connected:
                self.transport.received(data: datas[0])
                self.transport.received(data: datas[1])
            case .binary(let conn, let data):
                print("DATA:\(data)")
            case .text(let conn, let text):
                print("TExt:\(text)")
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

    
    func splitData(_ data: Data, into chunkCount: Int) -> [Data] {
        let dataLen = (data as NSData).length
        
//        assert(dataLen > chunkCount)
        
        let diff = dataLen / chunkCount
        let fullChunks = Int(dataLen / 1024) // 1 Kbyte
        let totalChunks = fullChunks + (dataLen % 1024 != 0 ? 1 : 0)

        var chunks:[Data] = [Data]()
        for chunkCounter in 0..<chunkCount {
            var chunk:Data
            let chunkBase = chunkCounter * diff
//            var diff = 1024
//            if chunkCounter == totalChunks - 1
//            {
//                diff = dataLen - chunkBase
//            }

            let range = chunkBase..<(chunkBase + diff)
            chunk = data.subdata(in: range)

            chunks.append(chunk)
        }
        return chunks
    }
    //TODO: the rest of them.
}
