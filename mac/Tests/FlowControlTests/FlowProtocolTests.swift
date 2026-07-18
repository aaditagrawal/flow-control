import XCTest
@testable import FlowControl

final class FlowProtocolTests: XCTestCase {
    func testOfficialReportEightGoldenVectors() throws {
        XCTAssertEqual(
            try FlowProtocol.readCommand(.online),
            [3, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 202]
        )
        XCTAssertEqual(
            try FlowProtocol.identityCommand(nonce: [1, 2, 3, 4, 0, 0, 0, 0]),
            [1, 0, 0, 0, 136, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 186]
        )
        XCTAssertTrue(FlowProtocol.isValidReport(try FlowProtocol.readCommand(.battery)))
    }

    func testFlashFramingUsesTenByteChunksAndBigEndianAddresses() throws {
        let read = try FlowProtocol.readFlashCommand(address: 0x1234, length: 10)
        XCTAssertEqual(read, [8, 0, 0x12, 0x34, 138, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 117])

        let writes = try FlowProtocol.writeFlashCommands(
            address: 0x0102,
            data: Array(1...12).map(UInt8.init)
        )
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0], [7, 0, 1, 2, 138, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 130])
        XCTAssertEqual(writes[1], [7, 0, 1, 12, 130, 11, 12, 0, 0, 0, 0, 0, 0, 0, 0, 160])
    }

    func testReadOnlyResponsesMatchOfficialOffsets() throws {
        let identity = try FlowProtocol.parseIdentity(
            [1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 0, 0, 0, 0]
        )
        XCTAssertEqual(identity, .init(customerID: 1, modelID: 2, transportType: 2))
        XCTAssertTrue(identity.isWired)

        XCTAssertEqual(
            try FlowProtocol.parseBattery([4, 0, 0, 0, 0, 87, 1, 0x0F, 0xA0, 0, 0, 0, 0, 0, 0, 0]),
            .init(percent: 87, isCharging: true, voltageMillivolts: 4_000)
        )
        XCTAssertEqual(
            try FlowProtocol.parseVersion([18, 0, 0, 0, 0, 1, 0x66, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            "v1.66"
        )

        var flashResponse = [UInt8](repeating: 0, count: 16)
        flashResponse[0] = FlowProtocol.Command.readFlash.rawValue
        flashResponse[2] = 0x12
        flashResponse[3] = 0x34
        flashResponse[4] = 0x80 | 3
        flashResponse.replaceSubrange(5..<8, with: [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(
            try FlowProtocol.parseFlashRead(flashResponse, expectedAddress: 0x1234),
            [0xAA, 0xBB, 0xCC]
        )
    }

    func testKeyAssignmentCodecPreservesFlagsButClassifiesLowNibble() throws {
        let encoded = FlowProtocol.encodeKeyAssignment(family: 0x82, value: 0x003A)
        XCTAssertEqual(encoded, [0x82, 0x3A, 0, 0x99])
        let decoded = try FlowProtocol.decodeKeyAssignment(encoded)
        XCTAssertEqual(decoded.rawFamily, 0x82)
        XCTAssertEqual(decoded.family, 0x02)
        XCTAssertEqual(decoded.value, 0x003A)
        XCTAssertEqual(FlowProtocol.keymapLayerAddress(system: .mac, layer: .function), 2_048)
    }

    func testLightingAndMacroCodecsRoundTrip() throws {
        let lighting = FlowProtocol.LightingState(mode: 10, isEnabled: true, offTime: 5)
        let encodedLighting = try FlowProtocol.encodeLightingState(lighting)
        XCTAssertEqual(encodedLighting, [10, 75, 1, 84, 5, 80])
        XCTAssertEqual(try FlowProtocol.decodeLightingState(encodedLighting), lighting)

        let header = try FlowProtocol.lightEffectHeader([2, 3, 3, 77], speed: 4, brightness: 1)
        XCTAssertEqual(header, [2, 4, 1, 78])
        XCTAssertEqual(try FlowProtocol.decodeLightEffect(header), .init(speed: 4, brightness: 1))
        XCTAssertThrowsError(try FlowProtocol.lightEffectHeader([2, 3, 3, 77], speed: 5, brightness: 1))

        let macro = FlowProtocol.MacroRecord(
            name: "Copy",
            events: [
                .init(status: 0, family: 2, value: 6, delayMilliseconds: 25),
                .init(status: 1, family: 2, value: 6, delayMilliseconds: 0),
            ]
        )
        let encodedMacro = try FlowProtocol.encodeMacro(macro)
        XCTAssertEqual(Array(encodedMacro[31...]), [2, 130, 6, 0, 0, 25, 66, 6, 0, 0, 0, 106])
        var slot = [UInt8](repeating: 0xFF, count: 384)
        slot.replaceSubrange(0..<encodedMacro.count, with: encodedMacro)
        XCTAssertEqual(try FlowProtocol.decodeMacro(slot), macro)
    }

    func testEveryFlowLiteLightingBoundaryProducesValidRecords() throws {
        for mode in UInt8(0)...UInt8(11) {
            for enabled in [false, true] {
                for offTime in [UInt8(0), 1, 3, 6, 12, 30, 60, 90] {
                    let state = FlowProtocol.LightingState(
                        mode: mode,
                        isEnabled: enabled,
                        offTime: offTime
                    )
                    let encoded = try FlowProtocol.encodeLightingState(state)
                    XCTAssertEqual(try FlowProtocol.decodeLightingState(encoded), state)
                    for offset in stride(from: 0, through: 4, by: 2) {
                        XCTAssertEqual((Int(encoded[offset]) + Int(encoded[offset + 1])) & 0xFF, 0x55)
                    }
                }
            }
        }

        for speed in UInt8(0)...UInt8(4) {
            for brightness in UInt8(0)...UInt8(4) {
                let header = try FlowProtocol.lightEffectHeader(
                    [0xFF, 2, 2, 0x54],
                    speed: speed,
                    brightness: brightness
                )
                XCTAssertEqual(header.count, 4)
                XCTAssertEqual(header[3], FlowProtocol.dataChecksum(header.prefix(3)))
                XCTAssertEqual(
                    try FlowProtocol.decodeLightEffect(header),
                    .init(speed: speed, brightness: brightness)
                )
            }
        }
    }

    func testComplementPairsUseByteArithmeticForFifteenMinuteTimeout() throws {
        XCTAssertEqual(try FlowProtocol.complementPair(90), [90, 251])
        XCTAssertEqual(try FlowProtocol.decodeComplementPair([90, 251]), 90)
        XCTAssertThrowsError(try FlowProtocol.decodeComplementPair([90, 250]))
    }

    func testComplementSettingsAndConfirmedPollingRates() throws {
        XCTAssertEqual(try FlowProtocol.complementPair(1), [1, 84])
        XCTAssertEqual(try FlowProtocol.decodeComplementPair([1, 84]), 1)
        XCTAssertEqual(
            try FlowProtocol.encodeLightingSelection(mode: 6, isEnabled: true),
            [6, 79, 1, 84]
        )
        XCTAssertEqual(try FlowProtocol.pollingRate(from: 8), 125)
        XCTAssertEqual(try FlowProtocol.pollingRateEncoding(for: 1_000), 1)
        XCTAssertThrowsError(try FlowProtocol.pollingRateEncoding(for: 2_000))
    }

    func testWriteAllowlistExcludesProtectedAndUnknownStorage() {
        XCTAssertTrue(FlowHIDService.isOrdinaryConfigurationRange(address: 0, length: 512))
        XCTAssertTrue(FlowHIDService.isOrdinaryConfigurationRange(address: 8_496, length: 6))
        XCTAssertTrue(FlowHIDService.isOrdinaryConfigurationRange(address: 10_064, length: 384))
        XCTAssertFalse(FlowHIDService.isOrdinaryConfigurationRange(address: 2_560, length: 1))
        XCTAssertFalse(FlowHIDService.isOrdinaryConfigurationRange(address: 0, length: 1_537))
        XCTAssertFalse(FlowHIDService.isOrdinaryConfigurationRange(address: 15_824, length: 1))
    }
}
