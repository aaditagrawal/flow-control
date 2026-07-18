import type { Action } from "./types";

const shared = "official-shared-driver" as const;

export const actions: readonly Action[] = [
  { id: "disabled", label: "Disabled", category: "disabled", type: 0x00, value: 0x00, evidence: shared },
  { id: "multi-screen", label: "Multi-Screen", category: "keyboard", type: null, value: null, evidence: "confirmed-flow-lite84", notes: "Printed Fn default; raw assignment encoding is unknown." },
  { id: "menu", label: "Menu", category: "keyboard", type: null, value: null, evidence: "confirmed-flow-lite84", notes: "Windows-only printed Fn default; raw assignment encoding is unknown." },
  { id: "voice-assistant", label: "Voice Assistant", category: "consumer", type: null, value: null, evidence: "confirmed-flow-lite84", notes: "Windows-only printed Fn default; raw assignment encoding is unknown." },
  { id: "lock", label: "Lock", category: "consumer", type: null, value: null, evidence: "confirmed-flow-lite84", notes: "Windows-only printed Fn default; raw assignment encoding is unknown." },
  ...[
    ["modifier-control-left", "Left Control", 0x01], ["modifier-shift-left", "Left Shift", 0x02],
    ["modifier-alt-left", "Left Alt / Option", 0x04], ["modifier-meta-left", "Left Windows / Command", 0x08],
    ["modifier-control-right", "Right Control", 0x10], ["modifier-shift-right", "Right Shift", 0x20],
    ["modifier-alt-right", "Right Alt / Option", 0x40], ["modifier-meta-right", "Right Windows / Command", 0x80],
  ].map(([id, label, value]): Action => ({ id: String(id), label: String(label), category: "keyboard", type: 0x01, value: Number(value), evidence: shared })),
  ...[
    ["player", "Player", 0x0183], ["play-pause", "Play / Pause", 0x00cd], ["next-track", "Next track", 0x00b5],
    ["previous-track", "Previous track", 0x00b6], ["stop", "Stop", 0x00b7], ["mute", "Mute", 0x00e2],
    ["volume-up", "Volume up", 0x00e9], ["volume-down", "Volume down", 0x00ea], ["mail", "Mail", 0x018a],
    ["calculator", "Calculator", 0x0192], ["computer", "My computer", 0x0194], ["home-page", "Home page", 0x0223],
    ["search", "Search", 0x0221], ["browser-forward", "Browser forward", 0x0225], ["browser-back", "Browser back", 0x0224],
    ["browser-stop", "Stop web page", 0x0226], ["refresh", "Refresh", 0x0227], ["favorites", "Favorites", 0x022a],
    ["screen-brightness-down", "Screen brightness down", 0x0070], ["screen-brightness-up", "Screen brightness up", 0x006f],
  ].map(([id, label, value]): Action => ({ id: String(id), label: String(label), category: "consumer", type: 0x03, value: Number(value), evidence: shared })),
  ...[
    ["bt-1", "Bluetooth 1", 0x0000], ["bt-2", "Bluetooth 2", 0x0001], ["bt-3", "Bluetooth 3", 0x0002], ["receiver-24g", "2.4 GHz", 0x0003],
    ["light-mode-cycle-forward", "Light mode cycle +", 0x0004], ["light-mode-next", "Light mode +", 0x0005], ["light-mode-previous", "Light mode -", 0x0006],
    ["light-color-cycle", "Light color cycle", 0x0007], ["light-color-next", "Light color +", 0x0008], ["light-color-previous", "Light color -", 0x0009],
    ["light-speed-cycle", "Light speed cycle", 0x000b], ["light-speed-up", "Light speed +", 0x000c], ["light-speed-down", "Light speed -", 0x000d],
    ["light-brightness-cycle", "Light brightness cycle", 0x000e], ["light-brightness-up", "Light brightness +", 0x000f], ["light-brightness-down", "Light brightness -", 0x0010],
    ["battery-check", "Check battery", 0x0011], ["light-toggle", "Light switch", 0x0012], ["fn-lock", "Fn Lock", 0x0013],
    ["ble", "BLE", 0x0014], ["wired", "Wired", 0x0015], ["clear-ble", "Clear BLE record", 0x0016], ["restore", "Restore", 0x0017],
    ["system-windows", "Windows mode", 0x0018], ["system-mac", "macOS mode", 0x0019], ["system-android", "Android mode", 0x001a], ["system-ios", "iOS mode", 0x001b],
    ["disable-alt-tab", "Disable Alt+Tab", 0x001c], ["disable-alt-fn", "Disable Alt+Fn", 0x001d], ["disable-shift-tab", "Disable Shift+Tab", 0x001e],
    ["disable-win", "Disable Windows key", 0x001f], ["other-static-led", "Other static LED", 0x0020], ["disable-win-app", "Disable Win+App", 0x0021],
    ["keyboard-lock", "Full keyboard lock", 0x0022], ["copilot", "Copilot (Windows only)", 0x0023],
    ["light-strip-toggle", "Light strip switch", 0x0024], ["light-strip-mode-cycle", "Light strip mode cycle", 0x0025],
    ["light-strip-mode-next", "Light strip mode +", 0x0026], ["light-strip-mode-previous", "Light strip mode -", 0x0027],
    ["light-strip-brightness-cycle", "Light strip brightness cycle", 0x0028], ["light-strip-brightness-up", "Light strip brightness +", 0x0029],
    ["light-strip-brightness-down", "Light strip brightness -", 0x002a], ["light-strip-speed-cycle", "Light strip speed cycle", 0x002b],
    ["light-strip-speed-up", "Light strip speed +", 0x002c], ["light-strip-speed-down", "Light strip speed -", 0x002d],
    ["light-strip-color-cycle", "Light strip color cycle", 0x002e], ["light-strip-color-next", "Light strip color +", 0x002f],
    ["light-strip-color-previous", "Light strip color -", 0x0030], ["light-mode-cycle-backward", "Light mode cycle -", 0x0031],
  ].map(([id, label, value]): Action => ({ id: String(id), label: String(label), category: "device", type: 0x05, value: Number(value), evidence: shared })),
  { id: "fn", label: "Fn", category: "layer", type: 0x06, value: 0x01, evidence: shared },
  { id: "mac-fn", label: "Mac Fn", category: "layer", type: 0x06, value: 0x02, evidence: shared },
  { id: "fn-2", label: "Fn 2", category: "layer", type: 0x06, value: 0x03, evidence: shared },
  ...Array.from({ length: 16 }, (_, index): Action => ({ id: `sequence-${index + 1}`, label: `Sequence ${index + 1}`, category: "sequence", type: 0x09, value: index + 1, evidence: shared })),
  ...[["mouse-left", "Mouse left", 0x01], ["mouse-right", "Mouse right", 0x02], ["mouse-middle", "Mouse middle", 0x04], ["mouse-forward", "Mouse forward", 0x10], ["mouse-back", "Mouse back", 0x08]].map(([id, label, value]): Action => ({ id: String(id), label: String(label), category: "mouse", type: 0x0a, value: Number(value), evidence: shared })),
];

// Keyboard usages are encoded as type 0x02 in the captured shared web config.
// The desktop UI can generate these rather than carrying a duplicated label table.
export function keyboardAction(hidUsage: number, label: string): Action {
  return { id: `keyboard-${hidUsage.toString(16).padStart(2, "0")}`, label, category: "keyboard", type: 0x02, value: hidUsage, evidence: shared };
}
