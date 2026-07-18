import { describe, expect, test } from "bun:test";
import {
  buildBatteryCommand,
  buildIdentityCommand,
  buildOnlineCommand,
  buildReadFlashCommands,
  buildWriteFlashCommands,
  decodeCustomLight,
  decodeKeyboardSettings,
  decodeKeyAssignment,
  decodeLightEffect,
  decodeLightingState,
  decodeMacro,
  encodeCustomLight,
  encodeKeyboardSettings,
  encodeKeyAssignment,
  encodeLightEffect,
  encodeLightingState,
  encodeLightingSelection,
  encodeMacro,
  isValidMacroChecksum,
  isValidReport,
  FlashAddress,
  isSafeConfigurationRange,
  keymapEntryAddress,
  macroAddress,
  parseBatteryResponse,
  parseIdentityResponse,
  parseFlashReadResponse,
  parseOnlineResponse,
  parseVersionResponse,
} from "../src";

describe("report-8 golden vectors", () => {
  test("builds the official keyboard online read frame", () => {
    expect([...buildOnlineCommand()]).toEqual([3, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 202]);
    expect(isValidReport(buildOnlineCommand())).toBe(true);
  });

  test("builds a deterministic identity frame", () => {
    expect([...buildIdentityCommand([1, 2, 3, 4, 0, 0, 0, 0])]).toEqual([1, 0, 0, 0, 136, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 186]);
  });

  test("chunks flash reads and writes with big-endian addresses", () => {
    const reads = buildReadFlashCommands(0x1234, 12);
    expect(reads.map((report) => [...report])).toEqual([
      [8, 0, 0x12, 0x34, 138, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 117],
      [8, 0, 0x12, 0x3e, 130, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 115],
    ]);
    const writes = buildWriteFlashCommands(0x0102, Uint8Array.from({ length: 12 }, (_, index) => index + 1));
    expect([...writes[0]!]).toEqual([7, 0, 1, 2, 138, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 130]);
    expect([...writes[1]!]).toEqual([7, 0, 1, 12, 130, 11, 12, 0, 0, 0, 0, 0, 0, 0, 0, 160]);
    expect(parseFlashReadResponse([8, 0, 0x12, 0x34, 0x83, 9, 8, 7, 0, 0, 0, 0, 0, 0, 0, 0])).toEqual({ address: 0x1234, data: Uint8Array.of(9, 8, 7) });
  });
});

describe("configuration write guard", () => {
  test("allows only ordinary configuration areas", () => {
    expect(isSafeConfigurationRange(FlashAddress.Keymaps, 4)).toBe(true);
    expect(isSafeConfigurationRange(FlashAddress.Macros, 384)).toBe(true);
    expect(isSafeConfigurationRange(FlashAddress.CustomLightMaps, 10)).toBe(false);
    expect(isSafeConfigurationRange(FlashAddress.BootAnimation, 2)).toBe(false);
    expect(isSafeConfigurationRange(0, 1025)).toBe(false);
  });
});

describe("read-only response parsing", () => {
  test("parses identity, online, battery, and version responses", () => {
    expect(parseIdentityResponse([1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 0, 0, 0, 0])).toEqual({ cid: 1, mid: 2, transportType: 2, wired: true, maxPollingRate: 1000 });
    expect(parseOnlineResponse([3, 0, 0, 0, 0, 1, 0xaa, 0xbb, 0xcc, 0, 0, 0, 0, 0, 0, 0])).toEqual({ online: true, address: [0xcc, 0xbb, 0xaa] });
    expect(parseBatteryResponse([4, 0, 0, 0, 0, 87, 1, 0x0f, 0xa0, 0, 0, 0, 0, 0, 0, 0])).toEqual({ level: 87, charging: true, voltageMillivolts: 4000 });
    expect(parseVersionResponse([18, 0, 0, 0, 0, 1, 0x66, 0, 0, 0, 0, 0, 0, 0, 0, 0])).toBe("v1.66");
    expect([...buildBatteryCommand()]).toHaveLength(16);
  });
});

describe("configuration codecs", () => {
  test("round-trips key assignments and computes addresses", () => {
    const encoded = encodeKeyAssignment({ type: 0x82, value: 0x003a });
    expect([...encoded]).toEqual([0x82, 0x3a, 0, 0x99]);
    expect(decodeKeyAssignment(encoded)).toEqual({ type: 0x82, value: 0x003a });
    expect(keymapEntryAddress("mac", "fn", 7)).toBe(1536 + 512 + 28);
  });

  test("round-trips macros using the official event layout", () => {
    const macro = { name: "Copy", events: [{ status: 0 as const, type: 2, value: 6, delay: 25 }, { status: 1 as const, type: 2, value: 6, delay: 0 }] };
    const encoded = encodeMacro(macro);
    expect([...encoded.slice(31)]).toEqual([2, 130, 6, 0, 0, 25, 66, 6, 0, 0, 0, 106]);
    expect(isValidMacroChecksum(encoded)).toBe(true);
    expect(decodeMacro(encoded)).toEqual(macro);
    expect(macroAddress(14)).toBe(10064 + 14 * 384);
  });

  test("round-trips lighting records", () => {
    const state = { mode: 10, enabled: true, offTime: 5 };
    expect([...encodeLightingState(state)]).toEqual([10, 75, 1, 84, 5, 80]);
    expect([...encodeLightingSelection(6, true)]).toEqual([6, 79, 1, 84]);
    expect(decodeLightingState(encodeLightingState(state))).toEqual(state);
    const effect = { colorIndex: 2, speed: 4, brightness: 5, colors: Array.from({ length: 7 }, () => ({ red: 10, green: 20, blue: 30 })) };
    expect(decodeLightEffect(encodeLightEffect(effect))).toEqual(effect);
    expect(decodeLightEffect(encodeLightEffect({ ...effect, colors: [] })).colors).toEqual(Array.from({ length: 7 }, () => ({ red: 0, green: 0, blue: 0 })));
    const custom = { type: 1, streamIndex: 2, streamListIndex: 3, runningIndex: 4, runningListIndex: 5, speed: 6, brightness: 7, color: { red: 8, green: 9, blue: 10 } };
    expect(decodeCustomLight(encodeCustomLight(custom))).toEqual(custom);
  });

  test("round-trips keyboard settings and rate encoding", () => {
    const settings = { pollingRate: 1000, bootAnimation: 2, bootAnimationEnabled: true, forbidKeyFunction: 0, currentSystem: "mac" as const, fnLock: 1, fullKeyLock: 0, musicMode: 0, scanKeyTime: 3, multikeyType: 1, wasdSwap: 0 };
    const encoded = encodeKeyboardSettings(settings);
    expect([...encoded.slice(0, 10)]).toEqual([1, 84, 2, 83, 1, 84, 0, 85, 1, 84]);
    expect(decodeKeyboardSettings(encoded)).toEqual(settings);
  });
});
