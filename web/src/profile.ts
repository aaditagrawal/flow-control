import { MACRO_SLOT_COUNT } from '../../packages/protocol/src'
import { ASSIGNMENTS, KEY_ROWS, LIGHTING_MODES, LIGHTING_SLEEP_TIMES, type KeyboardProfile } from './config'

const keyIds = new Set(KEY_ROWS.flat().map((key) => key.id))
const assignmentPairs = new Set(ASSIGNMENTS.map((item) => `${item.type & 0x0f}:${item.value}`))
const sleepTimes = new Set<number>(LIGHTING_SLEEP_TIMES.map((item) => item.value))
const lightingValues = new Set(LIGHTING_MODES.map((item) => item.rawValue))
const rates = new Set([125, 250, 500, 1000])

export function cloneProfile(profile: KeyboardProfile): KeyboardProfile {
  return JSON.parse(JSON.stringify(profile)) as KeyboardProfile
}

function fail(message: string): never { throw new Error(`Invalid Flow Lite profile: ${message}`) }

export function validateProfile(value: unknown): KeyboardProfile {
  if (!value || typeof value !== 'object') fail('expected an object')
  const profile = value as KeyboardProfile
  if (profile.version !== 1) fail('unsupported version')
  if (!profile.keymaps || !profile.lighting || !profile.device || !profile.metadata || !Array.isArray(profile.macros)) fail('missing required sections')
  if (profile.macros.length !== MACRO_SLOT_COUNT) fail(`expected ${MACRO_SLOT_COUNT} macros`)
  for (const system of ['win', 'mac'] as const) for (const layer of ['normal', 'fn'] as const) {
    const map = profile.keymaps[system]?.[layer]
    if (!map || Object.keys(map).length !== keyIds.size) fail(`invalid ${system}/${layer} layer`)
    for (const key of keyIds) {
      const assignment = map[key]
      if (!assignment || !Number.isInteger(assignment.type) || assignment.type < 0 || assignment.type > 0x0f || !Number.isInteger(assignment.value) || assignment.value < 0 || assignment.value > 0xffff || !assignmentPairs.has(`${assignment.type}:${assignment.value}`)) fail(`unsupported assignment for ${key}`)
    }
  }
  if (!lightingValues.has(profile.lighting.mode) || !Number.isInteger(profile.lighting.brightness) || profile.lighting.brightness < 0 || profile.lighting.brightness > 4 || !Number.isInteger(profile.lighting.speed) || profile.lighting.speed < 0 || profile.lighting.speed > 4 || !sleepTimes.has(profile.lighting.offTime)) fail('invalid lighting settings')
  if (!rates.has(profile.device.pollingRate) || !['win', 'mac'].includes(profile.device.currentSystem) || typeof profile.device.fnLock !== 'boolean' || typeof profile.device.fullKeyLock !== 'boolean') fail('invalid device settings')
  for (const macro of profile.macros) {
    if (!macro || typeof macro.name !== 'string' || macro.name.length > 30 || !Array.isArray(macro.events) || macro.events.length > 70) fail('invalid macro')
    for (const event of macro.events) if (!event || !['down', 'up'].includes(event.status) || !Number.isInteger(event.type) || !Number.isInteger(event.value) || !Number.isInteger(event.delay) || event.delay < 0 || event.delay > 0xffff) fail('invalid macro event')
  }
  return profile
}

export interface ProfileDiff { keys: number; macros: number; lighting: boolean; device: boolean }
export function diffProfiles(baseline: KeyboardProfile, staged: KeyboardProfile): ProfileDiff {
  let keys = 0
  for (const system of ['win', 'mac'] as const) for (const layer of ['normal', 'fn'] as const) for (const key of keyIds) {
    const before = baseline.keymaps[system][layer][key]; const after = staged.keymaps[system][layer][key]
    if (before.type !== after.type || before.value !== after.value) keys += 1
  }
  return {
    keys,
    macros: staged.macros.reduce((count, macro, index) => count + (JSON.stringify(macro) === JSON.stringify(baseline.macros[index]) ? 0 : 1), 0),
    lighting: JSON.stringify(baseline.lighting) !== JSON.stringify(staged.lighting),
    device: JSON.stringify(baseline.device) !== JSON.stringify(staged.device),
  }
}
