import { assertByte } from "./bytes";

export type CurrentSystem = "win" | "mac" | "android" | "iOS";
const currentSystemOrder: readonly CurrentSystem[] = ["win", "mac", "android", "iOS"];

export interface KeyboardSettings {
  pollingRate: number;
  bootAnimation: number;
  bootAnimationEnabled: boolean;
  forbidKeyFunction: number;
  currentSystem: CurrentSystem;
  fnLock: number;
  fullKeyLock: number;
  musicMode: number;
  scanKeyTime: number;
  multikeyType: number;
  wasdSwap: number;
}

export function pollingRateToFlash(rate: number): number {
  const encoded = rate > 1000 ? (rate / 1000) * 16 : 1000 / rate;
  assertByte(encoded, "encoded polling rate");
  return encoded;
}

export function pollingRateFromFlash(encoded: number): number {
  assertByte(encoded, "encoded polling rate");
  if (encoded === 0) throw new RangeError("encoded polling rate cannot be zero");
  return encoded >= 16 ? (encoded / 16) * 2000 : 1000 / encoded;
}

function setComplementPair(bytes: Uint8Array, offset: number, value: number): void {
  if (!Number.isInteger(value) || value < 0 || value > 0x55) {
    throw new RangeError(`settings byte ${offset} must be an integer from 0 to 85`);
  }
  bytes[offset] = value;
  bytes[offset + 1] = 0x55 - value;
}

export function encodeKeyboardSettings(settings: KeyboardSettings): Uint8Array {
  const encoded = new Uint8Array(32);
  setComplementPair(encoded, 0, pollingRateToFlash(settings.pollingRate));
  setComplementPair(encoded, 2, settings.bootAnimation);
  setComplementPair(encoded, 4, settings.bootAnimationEnabled ? 1 : 0);
  setComplementPair(encoded, 6, settings.forbidKeyFunction);
  setComplementPair(encoded, 8, currentSystemOrder.indexOf(settings.currentSystem));
  setComplementPair(encoded, 10, settings.fnLock);
  setComplementPair(encoded, 12, settings.fullKeyLock);
  setComplementPair(encoded, 14, settings.musicMode);
  setComplementPair(encoded, 16, settings.scanKeyTime);
  setComplementPair(encoded, 18, settings.multikeyType);
  setComplementPair(encoded, 20, settings.wasdSwap);
  return encoded;
}

export function decodeKeyboardSettings(bytes: ArrayLike<number>): KeyboardSettings {
  if (bytes.length < 22) throw new RangeError("keyboard settings must contain at least 22 bytes");
  for (let offset = 0; offset <= 20; offset += 2) {
    if ((bytes[offset] ?? 0) + (bytes[offset + 1] ?? 0) !== 0x55) {
      throw new Error(`invalid settings complement at byte ${offset}`);
    }
  }
  const currentSystem = currentSystemOrder[bytes[8] ?? 0];
  if (!currentSystem) throw new Error(`invalid current system ${bytes[8]}`);
  return {
    pollingRate: pollingRateFromFlash(bytes[0] ?? 0),
    bootAnimation: bytes[2] ?? 0,
    bootAnimationEnabled: bytes[4] === 1,
    forbidKeyFunction: bytes[6] ?? 0,
    currentSystem,
    fnLock: bytes[10] ?? 0,
    fullKeyLock: bytes[12] ?? 0,
    musicMode: bytes[14] ?? 0,
    scanKeyTime: bytes[16] ?? 0,
    multikeyType: bytes[18] ?? 0,
    wasdSwap: bytes[20] ?? 0,
  };
}
