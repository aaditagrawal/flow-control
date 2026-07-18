import {
  KEYMAP_ENTRY_SIZE,
  KEYMAP_KEYS_PER_LAYER,
  KEYMAP_LAYER_SIZE,
  KEYMAP_SYSTEM_SIZE,
} from "./constants";
import { assertByte, assertLength, assertRange, dataChecksum } from "./bytes";

export type KeyboardSystem = "win" | "mac" | "iOS" | "android";
export type KeyboardLayer = "normal" | "fn" | "fn2";

const systemOrder: readonly KeyboardSystem[] = ["win", "mac", "iOS", "android"];
const layerOrder: readonly KeyboardLayer[] = ["normal", "fn", "fn2"];

export interface KeyAssignment {
  type: number;
  value: number;
}

export function keymapLayerAddress(system: KeyboardSystem, layer: KeyboardLayer): number {
  return systemOrder.indexOf(system) * KEYMAP_SYSTEM_SIZE + layerOrder.indexOf(layer) * KEYMAP_LAYER_SIZE;
}

export function keymapEntryAddress(
  system: KeyboardSystem,
  layer: KeyboardLayer,
  keyIndex: number,
): number {
  assertRange(keyIndex, 0, KEYMAP_KEYS_PER_LAYER - 1, "key index");
  return keymapLayerAddress(system, layer) + keyIndex * KEYMAP_ENTRY_SIZE;
}

export function encodeKeyAssignment(assignment: KeyAssignment): Uint8Array {
  assertByte(assignment.type, "key type");
  assertRange(assignment.value, 0, 0xffff, "key value");
  const encoded = new Uint8Array(KEYMAP_ENTRY_SIZE);
  encoded[0] = assignment.type;
  encoded[1] = assignment.value & 0xff;
  encoded[2] = assignment.value >> 8;
  encoded[3] = dataChecksum(encoded.subarray(0, 3));
  return encoded;
}

export function decodeKeyAssignment(bytes: ArrayLike<number>): KeyAssignment {
  assertLength(bytes, KEYMAP_ENTRY_SIZE, "key assignment");
  const encoded = Uint8Array.from(bytes);
  if (dataChecksum(encoded.subarray(0, 3)) !== encoded[3]) throw new Error("invalid key assignment checksum");
  return { type: encoded[0] ?? 0, value: (encoded[1] ?? 0) | ((encoded[2] ?? 0) << 8) };
}

export function encodeKeymap(assignments: readonly KeyAssignment[]): Uint8Array {
  if (assignments.length !== KEYMAP_KEYS_PER_LAYER) {
    throw new RangeError(`keymap layer must contain ${KEYMAP_KEYS_PER_LAYER} assignments`);
  }
  const encoded = new Uint8Array(KEYMAP_LAYER_SIZE);
  assignments.forEach((assignment, index) => encoded.set(encodeKeyAssignment(assignment), index * KEYMAP_ENTRY_SIZE));
  return encoded;
}

export function decodeKeymap(bytes: ArrayLike<number>): KeyAssignment[] {
  assertLength(bytes, KEYMAP_LAYER_SIZE, "keymap layer");
  const encoded = Uint8Array.from(bytes);
  const assignments: KeyAssignment[] = [];
  for (let offset = 0; offset < encoded.length; offset += KEYMAP_ENTRY_SIZE) {
    assignments.push(decodeKeyAssignment(encoded.slice(offset, offset + KEYMAP_ENTRY_SIZE)));
  }
  return assignments;
}
