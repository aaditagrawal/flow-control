import {
  CUSTOM_LIGHT_COUNT,
  CUSTOM_LIGHT_SIZE,
  LIGHT_EFFECT_COUNT,
  LIGHT_EFFECT_SIZE,
  FlashAddress,
} from "./constants";
import { assertByte, assertLength, assertRange, dataChecksum } from "./bytes";

export interface RgbColor { red: number; green: number; blue: number }

function encodeRgb(color: RgbColor): Uint8Array {
  assertByte(color.red, "red");
  assertByte(color.green, "green");
  assertByte(color.blue, "blue");
  return Uint8Array.of(color.red, color.green, color.blue);
}

export interface LightingState {
  mode: number;
  enabled: boolean;
  offTime: number;
}

export function encodeLightingState(state: LightingState): Uint8Array {
  assertRange(state.mode, 0, 0x55, "lighting mode");
  assertRange(state.offTime, 0, 0x55, "lighting off time");
  const enabled = state.enabled ? 1 : 0;
  return Uint8Array.of(state.mode, 0x55 - state.mode, enabled, 0x55 - enabled, state.offTime, 0x55 - state.offTime);
}

/** Official effect selection frame: mode and enabled state are one write. */
export function encodeLightingSelection(mode: number, enabled: boolean): Uint8Array {
  assertRange(mode, 0, 0x55, "lighting mode");
  const state = enabled ? 1 : 0;
  return Uint8Array.of(mode, 0x55 - mode, state, 0x55 - state);
}

export function decodeLightingState(bytes: ArrayLike<number>): LightingState {
  assertLength(bytes, 6, "lighting state");
  if (((bytes[0] ?? 0) + (bytes[1] ?? 0)) !== 0x55 || ((bytes[2] ?? 0) + (bytes[3] ?? 0)) !== 0x55 || ((bytes[4] ?? 0) + (bytes[5] ?? 0)) !== 0x55) {
    throw new Error("invalid lighting state complement");
  }
  return { mode: bytes[0] ?? 0, enabled: bytes[2] === 1, offTime: bytes[4] ?? 0 };
}

export interface LightEffect {
  colorIndex: number;
  speed: number;
  brightness: number;
  colors: readonly RgbColor[];
}

export function lightEffectAddress(effectIndex: number): number {
  assertRange(effectIndex, 0, LIGHT_EFFECT_COUNT - 1, "light effect index");
  return FlashAddress.EffectParameters + effectIndex * LIGHT_EFFECT_SIZE;
}

export function encodeLightEffect(effect: LightEffect): Uint8Array {
  if (effect.colors.length > 7) throw new RangeError("light effect cannot exceed 7 colors");
  assertByte(effect.colorIndex, "color index");
  assertByte(effect.speed, "speed");
  assertByte(effect.brightness, "brightness");
  const encoded = new Uint8Array(LIGHT_EFFECT_SIZE);
  encoded[0] = effect.colorIndex;
  encoded[1] = effect.speed;
  encoded[2] = effect.brightness;
  encoded[3] = dataChecksum(encoded.subarray(0, 3));
  for (let index = 0; index < 7; index += 1) encoded[7 + index * 4] = 0x55;
  effect.colors.forEach((color, index) => {
    const offset = 4 + index * 4;
    const rgb = encodeRgb(color);
    encoded.set(rgb, offset);
    encoded[offset + 3] = dataChecksum(rgb);
  });
  return encoded;
}

export function decodeLightEffect(bytes: ArrayLike<number>): LightEffect {
  assertLength(bytes, LIGHT_EFFECT_SIZE, "light effect");
  const encoded = Uint8Array.from(bytes);
  if (encoded[3] !== dataChecksum(encoded.subarray(0, 3))) throw new Error("invalid light effect checksum");
  const colors: RgbColor[] = [];
  for (let index = 0; index < 7; index += 1) {
    const offset = 4 + index * 4;
    const rgb = encoded.subarray(offset, offset + 3);
    if (encoded[offset + 3] !== dataChecksum(rgb)) throw new Error(`invalid light color ${index} checksum`);
    colors.push({ red: rgb[0] ?? 0, green: rgb[1] ?? 0, blue: rgb[2] ?? 0 });
  }
  return { colorIndex: encoded[0] ?? 0, speed: encoded[1] ?? 0, brightness: encoded[2] ?? 0, colors };
}

export interface CustomLight {
  type: number;
  streamIndex: number;
  streamListIndex: number;
  runningIndex: number;
  runningListIndex: number;
  speed: number;
  brightness: number;
  color: RgbColor;
}

export function customLightAddress(keyIndex: number): number {
  assertRange(keyIndex, 0, CUSTOM_LIGHT_COUNT - 1, "custom light key index");
  return FlashAddress.CustomLightMaps + keyIndex * CUSTOM_LIGHT_SIZE;
}

export function encodeCustomLight(light: CustomLight): Uint8Array {
  [light.type, light.streamIndex, light.streamListIndex, light.runningIndex, light.runningListIndex].forEach((value, index) => assertByte(value, `custom light field ${index}`));
  assertRange(light.speed, 0, 15, "custom light speed");
  assertRange(light.brightness, 0, 15, "custom light brightness");
  const encoded = new Uint8Array(CUSTOM_LIGHT_SIZE);
  encoded.set([light.type, light.streamIndex, light.streamListIndex, light.runningIndex, light.runningListIndex]);
  encoded[5] = (light.speed << 4) | light.brightness;
  encoded.set(encodeRgb(light.color), 6);
  encoded[9] = dataChecksum(encoded.subarray(0, 9));
  return encoded;
}

export function decodeCustomLight(bytes: ArrayLike<number>): CustomLight {
  assertLength(bytes, CUSTOM_LIGHT_SIZE, "custom light");
  const encoded = Uint8Array.from(bytes);
  if (encoded[9] !== dataChecksum(encoded.subarray(0, 9))) throw new Error("invalid custom light checksum");
  return {
    type: encoded[0] ?? 0,
    streamIndex: encoded[1] ?? 0,
    streamListIndex: encoded[2] ?? 0,
    runningIndex: encoded[3] ?? 0,
    runningListIndex: encoded[4] ?? 0,
    speed: (encoded[5] ?? 0) >> 4,
    brightness: (encoded[5] ?? 0) & 0x0f,
    color: { red: encoded[6] ?? 0, green: encoded[7] ?? 0, blue: encoded[8] ?? 0 },
  };
}
