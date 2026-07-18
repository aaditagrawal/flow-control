import { describe, expect, test } from 'bun:test'
import { KEY_ROWS, LIGHTING_MODES, LIGHTING_SLEEP_TIMES, createDefaultProfile } from './config'
import { cloneProfile, diffProfiles, validateProfile } from './profile'

describe('Flow Lite web model', () => {
  test('uses the complete 84-key hardware map', () => {
    const keys = KEY_ROWS.flat()
    expect(keys).toHaveLength(84)
    expect(new Set(keys.map((key) => key.flashIndex)).size).toBe(84)
  })

  test('uses raw firmware lighting values', () => {
    expect(LIGHTING_MODES.find((mode) => mode.label === 'Sine Wave')?.rawValue).toBe(0x06)
    expect(LIGHTING_MODES.find((mode) => mode.label === 'Always On')?.rawValue).toBe(0x00)
    expect(LIGHTING_SLEEP_TIMES.map((option) => option.value)).toEqual([0, 1, 3, 6, 12, 30, 60, 90])
  })

  test('creates four editable keymap layers and fifteen macros', () => {
    const profile = createDefaultProfile()
    expect(Object.keys(profile.keymaps.win.normal)).toHaveLength(84)
    expect(Object.keys(profile.keymaps.win.fn)).toHaveLength(84)
    expect(Object.keys(profile.keymaps.mac.normal)).toHaveLength(84)
    expect(Object.keys(profile.keymaps.mac.fn)).toHaveLength(84)
    expect(profile.macros).toHaveLength(15)
  })

  test('validates imports and reports scoped staged changes', () => {
    const baseline = createDefaultProfile()
    const staged = cloneProfile(baseline)
    staged.keymaps.mac.normal.escape = { type: 0x00, value: 0, label: 'Disabled', category: 'Basic' }
    staged.macros[0].events.push({ status: 'down', type: 2, value: 4, label: 'A', delay: 0 })
    staged.device.fnLock = true
    expect(diffProfiles(baseline, staged)).toEqual({ keys: 1, macros: 1, lighting: false, device: true })
    expect(validateProfile(staged)).toEqual(staged)
    expect(() => validateProfile({ version: 1 })).toThrow('missing required sections')
    const unsafe = cloneProfile(baseline)
    unsafe.keymaps.mac.normal.escape = { type: 0x99, value: 1, label: 'unsafe', category: 'Basic' }
    expect(() => validateProfile(unsafe)).toThrow('unsupported assignment')
  })
})
