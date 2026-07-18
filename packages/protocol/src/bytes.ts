import { CHECKSUM_TARGET, REPORT_ID, REPORT_LENGTH } from "./constants";

export function assertByte(value: number, name: string): void {
  if (!Number.isInteger(value) || value < 0 || value > 0xff) {
    throw new RangeError(`${name} must be an integer from 0 to 255`);
  }
}

export function assertRange(
  value: number,
  minimum: number,
  maximum: number,
  name: string,
): void {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${name} must be an integer from ${minimum} to ${maximum}`);
  }
}

export function sumBytes(bytes: ArrayLike<number>, end = bytes.length): number {
  let sum = 0;
  for (let index = 0; index < end; index += 1) sum += bytes[index] ?? 0;
  return sum;
}

/** Checksum used by four-byte flash records and variable-length macro data. */
export function dataChecksum(bytesWithoutChecksum: ArrayLike<number>): number {
  return (CHECKSUM_TARGET - (sumBytes(bytesWithoutChecksum) & 0xff)) & 0xff;
}

/** Byte 15 for a 16-byte report-8 payload. */
export function reportChecksum(payloadWithoutChecksum: ArrayLike<number>): number {
  return (dataChecksum(payloadWithoutChecksum) - REPORT_ID) & 0xff;
}

export function finalizeReport(payload: Uint8Array): Uint8Array {
  if (payload.length !== REPORT_LENGTH) {
    throw new RangeError(`report payload must be ${REPORT_LENGTH} bytes`);
  }
  const finalized = payload.slice();
  finalized[REPORT_LENGTH - 1] = reportChecksum(finalized.subarray(0, REPORT_LENGTH - 1));
  return finalized;
}

export function isValidReport(payload: ArrayLike<number>): boolean {
  return (
    payload.length === REPORT_LENGTH &&
    ((sumBytes(payload) + REPORT_ID) & 0xff) === CHECKSUM_TARGET
  );
}

export function assertLength(bytes: ArrayLike<number>, expected: number, name: string): void {
  if (bytes.length !== expected) {
    throw new RangeError(`${name} must contain ${expected} bytes`);
  }
}

export function assertMinimumLength(
  bytes: ArrayLike<number>,
  minimum: number,
  name: string,
): void {
  if (bytes.length < minimum) {
    throw new RangeError(`${name} must contain at least ${minimum} bytes`);
  }
}
