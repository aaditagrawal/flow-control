import XCTest
@testable import FlowControl

final class FlowHIDIntegrationTests: XCTestCase {
    func testCustomLightingMapCanBeReadWithoutWriting() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_CUSTOM_LIGHT_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Set FLOW_HID_CUSTOM_LIGHT_DIAGNOSTIC=1 to inspect the custom-light map.")
        }

        let client = FlowHIDService()
        _ = try await client.connect()
        defer { client.disconnect() }

        let records = try await client.readCustomLightingRecords()
        XCTAssertEqual(records.count, 128)
        XCTAssertTrue(records.allSatisfy { $0.count == 10 })

        let types = Dictionary(grouping: records, by: { $0[0] }).mapValues(\.count)
        let validChecksums = records.filter {
            $0[9] == FlowProtocol.dataChecksum($0.prefix(9))
        }.count
        print("Flow Lite custom-light record types: \(types.sorted { $0.key < $1.key }); valid checksums: \(validChecksums)/128")
        for type in types.keys.sorted() {
            let samples = records.enumerated().filter { $0.element[0] == type }.prefix(5).map {
                let value = $0.element
                return "slot \($0.offset): stream \(value[1])/\(value[2]), running \(value[3])/\(value[4]), speed \(value[5] >> 4), brightness \(value[5] & 0x0F), rgb \(value[6]),\(value[7]),\(value[8])"
            }
            print("Flow Lite custom type \(type) samples: \(samples.joined(separator: "; "))")
        }
    }

    func testEveryLightingEffectHeaderCanBeRead() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_LIGHTING_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Set FLOW_HID_LIGHTING_DIAGNOSTIC=1 to inspect every lighting effect header.")
        }

        let client = FlowHIDService()
        _ = try await client.connect()
        defer { client.disconnect() }

        for mode in UInt8(0)...UInt8(10) {
            let effect = try await client.readLightingEffect(mode: mode)
            let record = try await client.readLightingEffectRecord(mode: mode)
            let hex = record.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("Flow Lite effect slot \(mode): brightness \(effect.brightness), speed \(effect.speed), bytes \(hex)")
        }
    }

    func testUnlistedLightingModeFiveCanBeObservedAndRestored() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_LIGHTING_MODE_FIVE_PROBE"] == "1" else {
            throw XCTSkip("Set FLOW_HID_LIGHTING_MODE_FIVE_PROBE=1 to run the reversible mode-five probe.")
        }

        let client = FlowHIDService()
        _ = try await client.connect()
        let original = try await client.readConfiguration()
        defer { client.disconnect() }

        do {
            try await client.selectLightingModeForDiagnostics(5)
            let selected = try await client.readConfiguration()
            XCTAssertEqual(selected.lighting.mode, 5)
            print("Flow Lite raw lighting mode 5 active for 10 seconds")
            try await Task.sleep(for: .seconds(10))
            try await client.writeConfiguration(original)
            let restored = try await client.readConfiguration()
            XCTAssertEqual(restored.lighting, original.lighting)
        } catch {
            try? await client.writeConfiguration(original)
            throw error
        }
    }

    func testSineWaveModeSelectionCanRoundTripAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_SINE_WRITE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLOW_HID_SINE_WRITE_INTEGRATION=1 to run the reversible Sine Wave selection test.")
        }

        let client = FlowHIDService()
        _ = try await client.connect()
        let original = try await client.readConfiguration()
        let alternateMode: UInt8 = original.lighting.mode == 1 ? 8 : 1
        let alternateEffect = try await client.readLightingEffect(mode: alternateMode)
        let sineEffect = try await client.readLightingEffect(mode: 6)
        defer { client.disconnect() }

        var alternate = original
        alternate.lighting.mode = alternateMode
        alternate.lighting.brightness = alternateEffect.brightness
        alternate.lighting.speed = alternateEffect.speed

        var sine = alternate
        sine.lighting.mode = 6
        sine.lighting.brightness = sineEffect.brightness
        sine.lighting.speed = sineEffect.speed

        do {
            let alternateReadback = try await client.applyConfiguration(
                alternate,
                baseline: original,
                changes: .lighting
            )
            XCTAssertEqual(alternateReadback.lighting, alternate.lighting)

            let sineReadback = try await client.applyConfiguration(
                sine,
                baseline: alternate,
                changes: .lighting
            )
            XCTAssertEqual(sineReadback.lighting, sine.lighting)

            try await client.writeConfiguration(original)
            let restored = try await client.readConfiguration()
            XCTAssertEqual(restored.lighting, original.lighting)
        } catch {
            try? await client.writeConfiguration(original)
            throw error
        }
    }

    func testConnectedFlowLiteCanReadItsCompleteConfiguration() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLOW_HID_INTEGRATION=1 to run against a wired Flow Lite 84.")
        }

        let client = FlowHIDService()
        let identity = try await client.connect()
        defer { client.disconnect() }

        XCTAssertEqual(identity.vendorID, FlowProtocol.vendorID)
        XCTAssertEqual(identity.productID, FlowProtocol.productID)
        XCTAssertTrue(identity.transportType == 2 || identity.transportType == 3)

        let configuration = try await client.readConfiguration()
        XCTAssertEqual(configuration.macros.count, 15)
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?.count, 84)
        XCTAssertEqual(configuration.keymaps[.windows]?[.function]?.count, 84)
        XCTAssertTrue([125, 250, 500, 1_000].contains(configuration.device.pollingRate))
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?["tab"]?.value, 0x2B)
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?["key-q"]?.value, 0x14)
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?["home"]?.value, 0x4A)
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?["end"]?.value, 0x4D)
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?["page-up"]?.value, 0x4B)
        XCTAssertEqual(configuration.keymaps[.mac]?[.base]?["page-down"]?.value, 0x4E)

        if ProcessInfo.processInfo.environment["FLOW_HID_ASSERT_FACTORY_BASE"] == "1" {
            for system in KeyboardSystem.allCases {
                let expected = try XCTUnwrap(FlowDefaults.configuration.keymaps[system]?[.base])
                let actual = try XCTUnwrap(configuration.keymaps[system]?[.base])
                let mismatches = expected.compactMap { keyID, expectedAction -> String? in
                    guard let actualAction = actual[keyID],
                          actualAction.family == expectedAction.family,
                          actualAction.value == expectedAction.value else {
                        let decoded = actual[keyID].map { "\($0.family):\($0.value)" } ?? "missing"
                        return "\(keyID) expected \(expectedAction.family):\(expectedAction.value), got \(decoded)"
                    }
                    return nil
                }
                XCTAssertEqual(mismatches, [], "\(system.title) base map mismatch:\n\(mismatches.joined(separator: "\n"))")
            }
        }

        print("Flow Lite live identity: \(identity.productName), firmware \(identity.deviceVersion), CID \(identity.customerID.map(String.init) ?? "unknown"), MID \(identity.modelID.map(String.init) ?? "unknown")")
        print("Flow Lite live lighting: mode \(configuration.lighting.mode), enabled \(configuration.lighting.isEnabled), brightness \(configuration.lighting.brightness), speed \(configuration.lighting.speed), off-time \(configuration.lighting.offTime)")
    }

    @MainActor
    func testAppStoreCanApplyVerifyAndRestoreOneSafeSetting() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_WRITE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLOW_HID_WRITE_INTEGRATION=1 to run the reversible hardware write test.")
        }

        let client = FlowHIDService()
        let store = AppStore(client: client)
        await store.connectAndRead()
        guard case .ready = store.connectionState else {
            XCTFail("Initial configuration read failed: \(store.connectionState)")
            return
        }

        let original = store.configuration
        let testRate = original.device.pollingRate == 500 ? 1_000 : 500
        do {
            store.configuration.device.pollingRate = testRate
            await store.applyChanges()
            guard case .ready = store.connectionState else {
                throw FlowDeviceError.writeVerificationFailed("test-rate apply failed: \(store.connectionState)")
            }
            XCTAssertEqual(store.savedConfiguration.device.pollingRate, testRate)
            XCTAssertNotNil(store.lastBackupURL)

            store.configuration.device.pollingRate = original.device.pollingRate
            await store.applyChanges()
            guard case .ready = store.connectionState else {
                throw FlowDeviceError.writeVerificationFailed("original-rate restore failed: \(store.connectionState)")
            }
            XCTAssertEqual(store.savedConfiguration.device.pollingRate, original.device.pollingRate)
        } catch {
            // Best-effort restoration uses the same allowlisted, verified path.
            try? await client.writeConfiguration(original)
            client.disconnect()
            throw error
        }
        client.disconnect()
    }

    @MainActor
    func testLightingLevelsCanRoundTripAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_LIGHTING_WRITE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLOW_HID_LIGHTING_WRITE_INTEGRATION=1 to run the reversible lighting write test.")
        }

        let client = FlowHIDService()
        let store = AppStore(client: client)
        await store.connectAndRead()
        guard case .ready = store.connectionState else {
            XCTFail("Initial configuration read failed: \(store.connectionState)")
            return
        }
        let original = store.configuration
        defer { client.disconnect() }

        store.configuration.lighting.brightness = original.lighting.brightness == 3 ? 2 : 3
        store.configuration.lighting.speed = original.lighting.speed == 3 ? 2 : 3
        let expected = store.configuration.lighting

        do {
            let applyStarted = ContinuousClock.now
            await store.applyChanges(scope: .lighting)
            let applyDuration = applyStarted.duration(to: .now)
            guard case .ready = store.connectionState else {
                throw FlowDeviceError.writeVerificationFailed("lighting apply failed: \(store.connectionState)")
            }
            XCTAssertEqual(store.savedConfiguration.lighting, expected)
            let verified = try await client.readConfiguration()
            XCTAssertEqual(verified.lighting, expected)

            store.configuration.lighting = original.lighting
            let restoreStarted = ContinuousClock.now
            await store.applyChanges(scope: .lighting)
            let restoreDuration = restoreStarted.duration(to: .now)
            guard case .ready = store.connectionState else {
                throw FlowDeviceError.writeVerificationFailed("lighting restore failed: \(store.connectionState)")
            }
            let restored = try await client.readConfiguration()
            XCTAssertEqual(restored.lighting, original.lighting)
            print("Flow Lite scoped lighting apply: \(applyDuration); restore: \(restoreDuration)")
        } catch {
            try? await client.writeConfiguration(original)
            throw error
        }
    }

    func testShortcutAndMacroAssignmentsCanRoundTripAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_SHORTCUT_WRITE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLOW_HID_SHORTCUT_WRITE_INTEGRATION=1 to run the reversible shortcut and macro assignment test.")
        }

        let client = FlowHIDService()
        _ = try await client.connect()
        let original = try await client.readConfiguration()
        guard let macroSlot = original.macros.first(where: { $0.events.isEmpty })?.id else {
            client.disconnect()
            throw XCTSkip("No empty macro slot is available for a reversible test.")
        }
        defer { client.disconnect() }

        do {
            var shortcutConfiguration = original
            shortcutConfiguration.keymaps[.mac]?[.base]?["f12"] = FlowDefaults.shortcutAction(
                modifierMask: 0x0a,
                keyUsage: 0x21
            )
            _ = try await client.applyConfiguration(
                shortcutConfiguration,
                baseline: original,
                changes: .keymaps
            )
            let shortcutReadback = try await client.readConfiguration()
            XCTAssertEqual(shortcutReadback.keymaps[.mac]?[.base]?["f12"]?.family, 0x07)
            XCTAssertEqual(shortcutReadback.keymaps[.mac]?[.base]?["f12"]?.value, 0x210a)

            var macroConfiguration = shortcutReadback
            let copy = FlowShortcut(modifierMask: 0x08, keyUsage: 0x06)
            let paste = FlowShortcut(modifierMask: 0x08, keyUsage: 0x19)
            let macroIndex = try XCTUnwrap(macroConfiguration.macros.firstIndex { $0.id == macroSlot })
            macroConfiguration.macros[macroIndex].name = "Flow shortcut test"
            macroConfiguration.macros[macroIndex].events =
                FlowDefaults.macroEvents(for: copy) + FlowDefaults.macroEvents(for: paste)
            macroConfiguration.keymaps[.mac]?[.base]?["f12"] = FlowDefaults.macroAction(slot: macroSlot)

            _ = try await client.applyConfiguration(
                macroConfiguration,
                baseline: shortcutReadback,
                changes: [.keymaps, .macros]
            )
            let macroReadback = try await client.readConfiguration()
            XCTAssertEqual(macroReadback.keymaps[.mac]?[.base]?["f12"]?.family, 0x08)
            XCTAssertEqual(macroReadback.keymaps[.mac]?[.base]?["f12"]?.value, UInt16(0x0100 | macroSlot))
            XCTAssertEqual(macroReadback.macros.first { $0.id == macroSlot }?.events.count, 8)

            try await client.writeConfiguration(original)
            let restored = try await client.readConfiguration()
            XCTAssertTrue(restored.isDeviceEquivalent(to: original))
        } catch {
            try? await client.writeConfiguration(original)
            throw error
        }
    }

    func testLightingModeStateTimeoutAndRapidWritesCanRestore() async throws {
        guard ProcessInfo.processInfo.environment["FLOW_HID_LIGHTING_MATRIX_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLOW_HID_LIGHTING_MATRIX_INTEGRATION=1 to run the reversible lighting matrix test.")
        }

        let client = FlowHIDService()
        _ = try await client.connect()
        let original = try await client.readConfiguration()
        guard let targetMode = FlowDefaults.supportedLightingModeValues.first(where: {
            $0 != original.lighting.mode
        }) else {
            throw XCTSkip("No alternate supported lighting mode is available.")
        }
        let originalTargetEffect = try await client.readLightingEffect(mode: targetMode)

        var targetRestore = original
        targetRestore.lighting.mode = targetMode
        targetRestore.lighting.speed = originalTargetEffect.speed
        targetRestore.lighting.brightness = originalTargetEffect.brightness

        func restore() async {
            // Restore the inactive target mode's levels before returning to the
            // original active mode. Both paths include verified readback.
            try? await client.writeConfiguration(targetRestore)
            try? await client.writeConfiguration(original)
        }

        do {
            var combined = targetRestore
            combined.lighting.isEnabled.toggle()
            combined.lighting.offTime = original.lighting.offTime == 90 ? 60 : 90
            try await client.writeConfiguration(combined)
            let combinedReadback = try await client.readConfiguration().lighting
            XCTAssertEqual(combinedReadback, combined.lighting)

            var minimum = combined
            minimum.lighting.brightness = 0
            minimum.lighting.speed = 0
            var maximum = combined
            maximum.lighting.brightness = 4
            maximum.lighting.speed = 4
            let minimumExpected = minimum.lighting
            let maximumExpected = maximum.lighting

            async let minimumWrite: Void = client.writeConfiguration(minimum)
            async let maximumWrite: Void = client.writeConfiguration(maximum)
            _ = try await (minimumWrite, maximumWrite)
            let rapidResult = try await client.readConfiguration().lighting
            XCTAssertTrue(rapidResult == minimumExpected || rapidResult == maximumExpected)

            await restore()
            let restoredReadback = try await client.readConfiguration().lighting
            XCTAssertEqual(restoredReadback, original.lighting)
        } catch {
            await restore()
            client.disconnect()
            throw error
        }
        client.disconnect()
    }
}
