export const REPORT_ID = 0x08;
export const REPORT_LENGTH = 16;
export const CHECKSUM_TARGET = 0x55;
export const KEYBOARD_FLAG = 0x80;
export const FLASH_SIZE = 16_384;
export const FLASH_CHUNK_SIZE = 10;

export const Command = {
  Identity: 0x01,
  DriverStatus: 0x02,
  Online: 0x03,
  Battery: 0x04,
  WriteFlash: 0x07,
  ReadFlash: 0x08,
  CurrentProfile: 0x0e,
  SetCurrentProfile: 0x0f,
  DeviceVersion: 0x12,
  DongleVersion: 0x1d,
} as const;

export const FlashAddress = {
  Keymaps: 0,
  CustomLightMaps: 6176,
  CurrentLightMode: 8496,
  LightState: 8498,
  OffLightTime: 8500,
  EffectParameters: 8544,
  ReportRate: 9408,
  BootAnimation: 9410,
  BootAnimationState: 9412,
  ForbidKeyFunction: 9414,
  CurrentSystem: 9416,
  FnLockState: 9418,
  FullKeyLockState: 9420,
  MusicState: 9422,
  ScanKeyTime: 9424,
  MultikeyType: 9426,
  WasdKey: 9428,
  Macros: 10064,
} as const;

export const KeyType = {
  Disabled: 0,
  Modifier: 1,
  Normal: 2,
  Media: 3,
  Power: 4,
  Special: 5,
  Function: 6,
  Combination: 7,
  Macro: 8,
  Queue: 9,
  Mouse: 10,
  PcKey: 11,
  AdcKey: 12,
  MouseFireKey: 13,
} as const;

export const KEYMAP_ENTRY_SIZE = 4;
export const KEYMAP_KEYS_PER_LAYER = 128;
export const KEYMAP_LAYER_SIZE = 512;
export const KEYMAP_SYSTEM_SIZE = 1536;
export const MACRO_SLOT_COUNT = 15;
export const MACRO_SLOT_SIZE = 384;
export const LIGHT_EFFECT_COUNT = 16;
export const LIGHT_EFFECT_SIZE = 32;
export const CUSTOM_LIGHT_COUNT = 128;
export const CUSTOM_LIGHT_SIZE = 10;

/**
 * The only persistent ranges the Flow Lite web companion is allowed to alter.
 * Firmware, boot animation, custom-light maps, pairing and reset areas are
 * deliberately absent. Keep this policy here so transports cannot drift.
 */
export const SAFE_CONFIGURATION_RANGES: readonly (readonly [number, number])[] = [
  [FlashAddress.Keymaps, FlashAddress.Keymaps + 1024],
  [1536, 2560],
  [FlashAddress.CurrentLightMode, FlashAddress.CurrentLightMode + 6],
  [FlashAddress.EffectParameters, FlashAddress.EffectParameters + 512],
  [FlashAddress.ReportRate, FlashAddress.ReportRate + 2],
  [FlashAddress.CurrentSystem, FlashAddress.CurrentSystem + 2],
  [FlashAddress.FnLockState, FlashAddress.FnLockState + 2],
  [FlashAddress.FullKeyLockState, FlashAddress.FullKeyLockState + 2],
  [FlashAddress.Macros, FlashAddress.Macros + MACRO_SLOT_COUNT * MACRO_SLOT_SIZE],
];

export function isSafeConfigurationRange(address: number, length: number): boolean {
  return Number.isSafeInteger(address) && Number.isSafeInteger(length) && length > 0 &&
    SAFE_CONFIGURATION_RANGES.some(([start, end]) => address >= start && address + length <= end);
}
