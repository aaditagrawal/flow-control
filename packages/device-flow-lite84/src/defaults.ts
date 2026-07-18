import type { DefaultBinding, HostSystem } from "./types";
import { physicalLayout } from "./layout";

const normalKeyboardBindings: readonly DefaultBinding[] = physicalLayout
  .filter((key) => key.hidUsage !== undefined)
  .map((key): DefaultBinding => ({
    keyId: key.id,
    actionId: key.id.startsWith("control-") || key.id.startsWith("shift-") || key.id.startsWith("alt-") || key.id.startsWith("meta-")
      ? `modifier-${key.id}`
      : `keyboard-${key.hidUsage?.toString(16).padStart(2, "0")}`,
    evidence: "confirmed-flow-lite84",
  }));

const normalBindings: readonly DefaultBinding[] = [
  ...normalKeyboardBindings,
  { keyId: "fn", actionId: "fn", evidence: "confirmed-flow-lite84" },
];

const commonFn: readonly DefaultBinding[] = [
  { keyId: "f1", actionId: "screen-brightness-down", evidence: "confirmed-flow-lite84" },
  { keyId: "f2", actionId: "screen-brightness-up", evidence: "confirmed-flow-lite84" },
  { keyId: "f3", actionId: "multi-screen", evidence: "confirmed-flow-lite84" },
  { keyId: "f4", actionId: "search", evidence: "confirmed-flow-lite84" },
  { keyId: "f5", actionId: "light-brightness-down", evidence: "confirmed-flow-lite84" },
  { keyId: "f6", actionId: "light-brightness-up", evidence: "confirmed-flow-lite84" },
  { keyId: "f7", actionId: "previous-track", evidence: "confirmed-flow-lite84" },
  { keyId: "f8", actionId: "play-pause", evidence: "confirmed-flow-lite84" },
  { keyId: "f9", actionId: "next-track", evidence: "confirmed-flow-lite84" },
  { keyId: "f10", actionId: "mute", evidence: "confirmed-flow-lite84" },
  { keyId: "f11", actionId: "volume-down", evidence: "confirmed-flow-lite84" },
  { keyId: "f12", actionId: "volume-up", evidence: "confirmed-flow-lite84" },
];

export const defaults: Readonly<Record<HostSystem, { readonly normal: readonly DefaultBinding[]; readonly fn: readonly DefaultBinding[] }>> = {
  win: {
    normal: normalBindings,
    fn: [
      ...commonFn,
      { keyId: "alt-right", actionId: "menu", evidence: "confirmed-flow-lite84" },
      { keyId: "print-screen", actionId: "calculator", evidence: "confirmed-flow-lite84" },
      { keyId: "insert", actionId: "voice-assistant", evidence: "confirmed-flow-lite84" },
      { keyId: "delete", actionId: "lock", evidence: "confirmed-flow-lite84" },
    ],
  },
  mac: { normal: normalBindings, fn: commonFn },
};
