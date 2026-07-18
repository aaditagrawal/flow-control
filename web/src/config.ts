import {
  actions as sharedActions,
  flashIndexByKeyId,
  keyboardAction,
  lightingModes,
  physicalLayout,
} from '../../packages/device-flow-lite84/src'

export type SystemMode = 'win' | 'mac'
export type Layer = 'normal' | 'fn'
export type WorkspaceTab = 'keymap' | 'lighting' | 'macros' | 'device'

export interface KeyDefinition {
  id: string
  label: string
  width?: number
  spacerBefore?: number
  flashIndex: number
}

export interface KeyAssignment {
  type: number
  value: number
  label: string
  category: AssignmentCategory
}

export type AssignmentCategory =
  | 'Basic'
  | 'Modifier'
  | 'Media'
  | 'Navigation'
  | 'Macro'
  | 'Device'
  | 'Mouse'

export interface MacroEvent {
  status: 'down' | 'up'
  type: number
  value: number
  label: string
  delay: number
}

export interface MacroDefinition {
  name: string
  events: MacroEvent[]
}

export interface LightingSettings {
  /** Raw firmware mode, not the Windows display-row index. */
  mode: number
  enabled: boolean
  brightness: number
  speed: number
  offTime: number
}

export interface DeviceSettings {
  pollingRate: 125 | 250 | 500 | 1000
  currentSystem: SystemMode
  fnLock: boolean
  fullKeyLock: boolean
}

export interface DeviceMetadata {
  firmware: string
  batteryLevel: number | null
  charging: boolean
  cid: number
  mid: number
}

export interface KeyboardProfile {
  version: 1
  keymaps: Record<SystemMode, Record<Layer, Record<string, KeyAssignment>>>
  lighting: LightingSettings
  macros: MacroDefinition[]
  device: DeviceSettings
  metadata: DeviceMetadata
}

const rows = new Map<number, KeyDefinition[]>()
for (const key of physicalLayout) {
  const flashIndex = flashIndexByKeyId[key.id]
  if (flashIndex === undefined) continue
  const y = key.y
  const row = rows.get(y) ?? []
  const previous = row.at(-1)
  const previousEnd = previous ? (physicalLayout.find((item) => item.id === previous.id)?.x ?? 0) + (previous.width ?? 1) : 0
  row.push({
    id: key.id,
    label: key.label,
    width: key.width,
    spacerBefore: Math.max(0, key.x - previousEnd),
    flashIndex,
  })
  rows.set(y, row)
}

export const KEY_ROWS = [...rows.entries()]
  .sort(([left], [right]) => left - right)
  .map(([, row]) => row)

function categoryFor(type: number, value: number): AssignmentCategory {
  switch (type & 0x0f) {
    case 0x01: return 'Modifier'
    case 0x03: return value >= 0x006f && value <= 0x0070 ? 'Device' : 'Media'
    case 0x05: case 0x06: return 'Device'
    case 0x08: case 0x09: return 'Macro'
    case 0x0a: return 'Mouse'
    default: return value >= 0x4a && value <= 0x52 ? 'Navigation' : 'Basic'
  }
}

const keyboardActions = physicalLayout.flatMap((key) =>
  key.hidUsage === undefined ? [] : [keyboardAction(key.hidUsage, key.label)],
)

export const ASSIGNMENTS: KeyAssignment[] = [...sharedActions, ...keyboardActions]
  .filter((action) => action.type !== null && action.value !== null)
  .filter((action) => action.id !== 'restore' && action.id !== 'clear-ble')
  .map((action) => ({
    type: action.type ?? 0,
    value: action.value ?? 0,
    label: action.label,
    category: categoryFor(action.type ?? 0, action.value ?? 0),
  }))
  .concat(Array.from({ length: 15 }, (_, index) => ({
    type: 0x08,
    value: index,
    label: `Macro ${index + 1}`,
    category: 'Macro' as const,
  })))

export function describeAssignment(type: number, value: number): KeyAssignment {
  const normalizedType = type & 0x0f
  const known = ASSIGNMENTS.find((assignment) =>
    (assignment.type & 0x0f) === normalizedType && assignment.value === value,
  )
  return known
    ? { ...known, type }
    : { type, value, label: `Unknown ${type.toString(16)}:${value.toString(16)}`, category: categoryFor(type, value) }
}

function createLayer() {
  return Object.fromEntries(KEY_ROWS.flat().map((key) => {
    const physical = physicalLayout.find((item) => item.id === key.id)
    if (key.id === 'fn') return [key.id, describeAssignment(0x06, 0x02)]
    return [key.id, describeAssignment(0x02, physical?.hidUsage ?? 0)]
  }))
}

export const LIGHTING_MODES = lightingModes.filter((mode) => mode.rawValue !== 0xff)
export const LIGHTING_SLEEP_TIMES = [
  { value: 0, label: 'Never' },
  { value: 1, label: '10 seconds' },
  { value: 3, label: '30 seconds' },
  { value: 6, label: '1 minute' },
  { value: 12, label: '2 minutes' },
  { value: 30, label: '5 minutes' },
  { value: 60, label: '10 minutes' },
  { value: 90, label: '15 minutes' },
] as const

export function createDefaultProfile(): KeyboardProfile {
  return {
    version: 1,
    keymaps: {
      win: { normal: createLayer(), fn: createLayer() },
      mac: { normal: createLayer(), fn: createLayer() },
    },
    lighting: { mode: 0, enabled: true, brightness: 3, speed: 3, offTime: 6 },
    macros: Array.from({ length: 15 }, (_, index) => ({ name: `Macro ${index + 1}`, events: [] })),
    device: { pollingRate: 1000, currentSystem: 'mac', fnLock: false, fullKeyLock: false },
    metadata: { firmware: 'Unknown', batteryLevel: null, charging: false, cid: 0, mid: 0 },
  }
}
