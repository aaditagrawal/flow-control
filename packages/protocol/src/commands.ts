import {
  Command,
  FLASH_CHUNK_SIZE,
  FLASH_SIZE,
  KEYBOARD_FLAG,
  REPORT_LENGTH,
} from "./constants";
import {
  assertByte,
  assertLength,
  assertMinimumLength,
  assertRange,
  finalizeReport,
} from "./bytes";

function emptyReport(command: number): Uint8Array {
  const report = new Uint8Array(REPORT_LENGTH);
  report[0] = command;
  return report;
}

export function buildReadCommand(command: number): Uint8Array {
  assertByte(command, "command");
  const report = emptyReport(command);
  report[4] = KEYBOARD_FLAG;
  return finalizeReport(report);
}

export function buildWriteCommand(command: number, data: ArrayLike<number>): Uint8Array {
  assertByte(command, "command");
  if (data.length > FLASH_CHUNK_SIZE) {
    throw new RangeError(`command data cannot exceed ${FLASH_CHUNK_SIZE} bytes`);
  }
  const report = emptyReport(command);
  report[4] = KEYBOARD_FLAG + data.length;
  for (let index = 0; index < data.length; index += 1) {
    const value = data[index] ?? 0;
    assertByte(value, `data[${index}]`);
    report[5 + index] = value;
  }
  return finalizeReport(report);
}

export function buildIdentityCommand(nonce: ArrayLike<number>): Uint8Array {
  if (nonce.length !== 8) throw new RangeError("identity nonce must contain 8 bytes");
  return buildWriteCommand(Command.Identity, nonce);
}

export function buildOnlineCommand(): Uint8Array {
  return buildReadCommand(Command.Online);
}

export function buildBatteryCommand(): Uint8Array {
  return buildReadCommand(Command.Battery);
}

export function buildDeviceVersionCommand(): Uint8Array {
  return buildReadCommand(Command.DeviceVersion);
}

export function buildCurrentProfileCommand(): Uint8Array {
  return buildReadCommand(Command.CurrentProfile);
}

export function buildReadFlashCommand(address: number, length: number): Uint8Array {
  assertRange(address, 0, FLASH_SIZE - 1, "flash address");
  assertRange(length, 1, FLASH_CHUNK_SIZE, "flash read length");
  if (address + length > FLASH_SIZE) throw new RangeError("flash read exceeds flash size");
  const report = emptyReport(Command.ReadFlash);
  report[2] = address >> 8;
  report[3] = address & 0xff;
  report[4] = KEYBOARD_FLAG + length;
  return finalizeReport(report);
}

export function buildReadFlashCommands(address: number, length: number): Uint8Array[] {
  assertRange(address, 0, FLASH_SIZE - 1, "flash address");
  assertRange(length, 1, FLASH_SIZE, "flash read length");
  if (address + length > FLASH_SIZE) throw new RangeError("flash read exceeds flash size");
  const reports: Uint8Array[] = [];
  for (let offset = 0; offset < length; offset += FLASH_CHUNK_SIZE) {
    reports.push(buildReadFlashCommand(address + offset, Math.min(FLASH_CHUNK_SIZE, length - offset)));
  }
  return reports;
}

export function buildWriteFlashCommands(address: number, data: ArrayLike<number>): Uint8Array[] {
  assertRange(address, 0, FLASH_SIZE - 1, "flash address");
  assertRange(data.length, 1, FLASH_SIZE, "flash write length");
  if (address + data.length > FLASH_SIZE) throw new RangeError("flash write exceeds flash size");
  const reports: Uint8Array[] = [];
  for (let offset = 0; offset < data.length; offset += FLASH_CHUNK_SIZE) {
    const length = Math.min(FLASH_CHUNK_SIZE, data.length - offset);
    const report = emptyReport(Command.WriteFlash);
    const chunkAddress = address + offset;
    report[2] = chunkAddress >> 8;
    report[3] = chunkAddress & 0xff;
    report[4] = KEYBOARD_FLAG + length;
    for (let index = 0; index < length; index += 1) {
      const value = data[offset + index] ?? 0;
      assertByte(value, `data[${offset + index}]`);
      report[5 + index] = value;
    }
    reports.push(finalizeReport(report));
  }
  return reports;
}

export interface CommandResponse {
  command: number;
  status: number;
  ok: boolean;
  payload: Uint8Array;
}

export function parseCommandResponse(bytes: ArrayLike<number>): CommandResponse {
  assertLength(bytes, REPORT_LENGTH, "command response");
  const payload = Uint8Array.from(bytes);
  return { command: payload[0] ?? 0, status: payload[1] ?? 0, ok: payload[1] === 0, payload };
}

function expectResponse(bytes: ArrayLike<number>, command: number): Uint8Array {
  const response = parseCommandResponse(bytes);
  if (response.command !== command) throw new Error(`expected command ${command}, received ${response.command}`);
  if (!response.ok) throw new Error(`command ${command} failed with status ${response.status}`);
  return response.payload;
}

export interface DeviceIdentity {
  cid: number;
  mid: number;
  transportType: number;
  wired: boolean;
  maxPollingRate: number;
}

export function parseIdentityResponse(bytes: ArrayLike<number>): DeviceIdentity {
  const response = expectResponse(bytes, Command.Identity);
  const transportType = response[11] ?? 0;
  const maxPollingRate =
    transportType === 1 ? 4000 : transportType === 3 || transportType === 5 ? 8000 : transportType === 4 ? 2000 : 1000;
  return {
    cid: response[9] ?? 0,
    mid: response[10] ?? 0,
    transportType,
    wired: transportType === 2 || transportType === 3,
    maxPollingRate,
  };
}

export interface OnlineState {
  online: boolean;
  address: readonly [number, number, number];
}

export function parseOnlineResponse(bytes: ArrayLike<number>): OnlineState {
  const response = expectResponse(bytes, Command.Online);
  return { online: response[5] === 1, address: [response[8] ?? 0, response[7] ?? 0, response[6] ?? 0] };
}

export interface BatteryState {
  level: number;
  charging: boolean;
  voltageMillivolts: number;
}

export function parseBatteryResponse(bytes: ArrayLike<number>): BatteryState {
  const response = expectResponse(bytes, Command.Battery);
  return {
    level: response[5] ?? 0,
    charging: response[6] === 1,
    voltageMillivolts: ((response[7] ?? 0) << 8) | (response[8] ?? 0),
  };
}

export function parseVersionResponse(bytes: ArrayLike<number>): string {
  const response = expectResponse(bytes, Command.DeviceVersion);
  return `v${response[5] ?? 0}.${(response[6] ?? 0).toString(16).padStart(2, "0")}`;
}

export function parseCurrentProfileResponse(bytes: ArrayLike<number>): number {
  return expectResponse(bytes, Command.CurrentProfile)[5] ?? 0;
}

export interface FlashReadResponse {
  address: number;
  data: Uint8Array;
}

export function parseFlashReadResponse(bytes: ArrayLike<number>): FlashReadResponse {
  assertMinimumLength(bytes, REPORT_LENGTH, "flash read response");
  const response = expectResponse(bytes, Command.ReadFlash);
  const length = (response[4] ?? 0) & 0x7f;
  if (length > FLASH_CHUNK_SIZE) throw new Error(`invalid flash response length ${length}`);
  return {
    address: ((response[2] ?? 0) << 8) | (response[3] ?? 0),
    data: response.slice(5, 5 + length),
  };
}
