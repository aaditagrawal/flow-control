import { MACRO_SLOT_COUNT, MACRO_SLOT_SIZE, FlashAddress } from "./constants";
import { assertByte, assertRange, dataChecksum, sumBytes } from "./bytes";

export interface MacroEvent {
  /** Official client values: 0 = press, 1 = release. */
  status: 0 | 1;
  type: number;
  value: number;
  delay: number;
}

export interface KeyboardMacro {
  name: string;
  events: readonly MacroEvent[];
}

export function macroAddress(slot: number): number {
  assertRange(slot, 0, MACRO_SLOT_COUNT - 1, "macro slot");
  return FlashAddress.Macros + slot * MACRO_SLOT_SIZE;
}

export function encodeMacro(macro: KeyboardMacro): Uint8Array {
  const name = new TextEncoder().encode(macro.name);
  if (name.length > 30) throw new RangeError("macro name cannot exceed 30 UTF-8 bytes");
  if (macro.events.length > 70) throw new RangeError("macro cannot exceed 70 events");
  const encoded = new Uint8Array(33 + macro.events.length * 5);
  encoded.fill(0xff);
  encoded[0] = name.length;
  encoded.set(name, 1);
  encoded[31] = macro.events.length;
  macro.events.forEach((event, index) => {
    assertByte(event.type, `events[${index}].type`);
    assertRange(event.type, 0, 0x0f, `events[${index}].type`);
    assertRange(event.value, 0, 0xffff, `events[${index}].value`);
    assertRange(event.delay, 0, 0xffff, `events[${index}].delay`);
    const offset = 32 + index * 5;
    encoded[offset] = ((event.status === 0 ? 2 : 1) << 6) + event.type;
    encoded[offset + 1] = event.value & 0xff;
    encoded[offset + 2] = event.value >> 8;
    encoded[offset + 3] = event.delay >> 8;
    encoded[offset + 4] = event.delay & 0xff;
  });
  const eventsStart = encoded.subarray(32, 32 + macro.events.length * 5);
  // This reproduces the official client's `nt(events + placeholder) - eventCount` rule.
  encoded[encoded.length - 1] = (dataChecksum(eventsStart) - macro.events.length) & 0xff;
  return encoded;
}

export function decodeMacro(slotBytes: ArrayLike<number>): KeyboardMacro | null {
  if (slotBytes.length > MACRO_SLOT_SIZE) throw new RangeError(`macro slot cannot exceed ${MACRO_SLOT_SIZE} bytes`);
  if (slotBytes.length < 32) throw new RangeError("macro slot must contain at least 32 bytes");
  const encoded = Uint8Array.from(slotBytes);
  const nameLength = encoded[0] ?? 0;
  const eventCount = encoded[31] ?? 0;
  if (nameLength === 0 || nameLength > 30 || eventCount > 70) return null;
  const requiredLength = 33 + eventCount * 5;
  if (encoded.length < requiredLength) throw new RangeError(`macro data must contain at least ${requiredLength} bytes`);
  const name = new TextDecoder().decode(encoded.slice(1, 1 + nameLength));
  const events: MacroEvent[] = [];
  for (let index = 0; index < eventCount; index += 1) {
    const offset = 32 + index * 5;
    const flags = encoded[offset] ?? 0;
    const status: 0 | 1 = flags >> 6 === 2 ? 0 : 1;
    events.push({
      status,
      type: flags & 0x0f,
      value: (encoded[offset + 1] ?? 0) | ((encoded[offset + 2] ?? 0) << 8),
      delay: ((encoded[offset + 3] ?? 0) << 8) | (encoded[offset + 4] ?? 0),
    });
  }
  return { name, events };
}

export function isValidMacroChecksum(bytes: ArrayLike<number>): boolean {
  if (bytes.length < 33) return false;
  const eventCount = bytes[31] ?? 0;
  const checksumOffset = 32 + eventCount * 5;
  if (checksumOffset >= bytes.length) return false;
  const events = Uint8Array.from(bytes).subarray(32, checksumOffset);
  const expected = (0x55 - (sumBytes(events) & 0xff) - eventCount) & 0xff;
  return bytes[checksumOffset] === expected;
}
