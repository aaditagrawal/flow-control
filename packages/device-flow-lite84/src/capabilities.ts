import type { LightingMode, NumericOption } from "./types";

// Names and per-mode flags are from the Flow Lite Windows package. Duplicate
// 0xFF values are preserved exactly; mode slot and raw value are separate fields.
export const lightingModes: readonly LightingMode[] = [
  { id: 0, rawValue: 0xff, label: "Off", evidence: "windows-static-analysis", capabilities: [] },
  { id: 1, rawValue: 0x08, label: "Ripple", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 2, rawValue: 0x07, label: "Touch Effect", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 3, rawValue: 0xff, label: "Flow", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 4, rawValue: 0x04, label: "Snow Trace", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 5, rawValue: 0x06, label: "Sine Wave", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 6, rawValue: 0x01, label: "Breathing", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 7, rawValue: 0x00, label: "Always On", evidence: "windows-static-analysis", capabilities: ["brightness"] },
  { id: 8, rawValue: 0x09, label: "Snake", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
  { id: 9, rawValue: 0xff, label: "Season Blossom", evidence: "windows-static-analysis", capabilities: [] },
  { id: 10, rawValue: 0x02, label: "Rainbow Cycle", evidence: "windows-static-analysis", capabilities: [] },
  { id: 11, rawValue: 0x03, label: "Seven-color Change", evidence: "windows-static-analysis", capabilities: ["brightness", "speed"] },
];

export const lightingBrightnessValues: readonly number[] = [0, 30, 60, 90, 120];
export const lightingSpeedValues: readonly number[] = [1000, 17, 12, 8, 0];

export const pollingRates: readonly NumericOption[] = [
  { value: 8, label: "125 Hz" }, { value: 4, label: "250 Hz" }, { value: 2, label: "500 Hz" }, { value: 1, label: "1000 Hz" },
];

export const sharedDriverPollingRates: readonly NumericOption[] = [
  ...pollingRates, { value: 16, label: "2000 Hz" }, { value: 32, label: "4000 Hz" }, { value: 64, label: "8000 Hz" },
];

export const webLightSleepTimes: readonly NumericOption[] = [
  { value: 1, label: "10 seconds" }, { value: 3, label: "30 seconds" }, { value: 6, label: "1 minute" }, { value: 12, label: "2 minutes" },
  { value: 30, label: "5 minutes" }, { value: 60, label: "10 minutes" }, { value: 90, label: "15 minutes" },
];

// Semantic seconds. The Windows UI exposes these labels; the on-wire encoding
// still needs a read/write capture before use.
export const windowsSleepTimes: readonly NumericOption[] = [
  { value: 10, label: "10 seconds" }, { value: 30, label: "30 seconds" }, { value: 60, label: "1 minute" }, { value: 180, label: "3 minutes" },
  { value: 300, label: "5 minutes" }, { value: 600, label: "10 minutes" }, { value: 900, label: "15 minutes" }, { value: 1200, label: "20 minutes" },
  { value: 1500, label: "25 minutes" }, { value: 1800, label: "30 minutes" }, { value: 2100, label: "35 minutes" }, { value: 2400, label: "40 minutes" },
];

export const capabilities = {
  systems: ["win", "mac"],
  layers: ["normal", "fn"],
  physicalKeyCount: 84,
  macro: { maximumSlots: 15, repeatMinimum: 1, repeatMaximum: 250, defaultDelayMinimumMs: 10, eventKinds: ["key-down", "key-up", "delay", "mouse-button"] },
  lighting: { brightnessValues: lightingBrightnessValues, speedValues: lightingSpeedValues, customModeCountEnabled: 3, singleColor: true },
  settings: { pollingRatesHzConfirmed: [125, 250, 500, 1000], rollover: ["6-key", "n-key"], profileOperations: ["create", "rename", "delete", "import", "export"] },
} as const;
