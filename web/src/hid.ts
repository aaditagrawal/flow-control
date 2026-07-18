import {
  Command,
  FlashAddress,
  REPORT_ID,
  buildBatteryCommand,
  buildDeviceVersionCommand,
  buildIdentityCommand,
  buildReadFlashCommands,
  buildWriteFlashCommands,
  dataChecksum,
  decodeKeyboardSettings,
  decodeKeyAssignment,
  decodeLightEffect,
  decodeLightingState,
  decodeMacro,
  encodeKeyAssignment,
  encodeLightingSelection,
  encodeMacro,
  keymapEntryAddress,
  lightEffectAddress,
  macroAddress,
  parseBatteryResponse,
  parseCommandResponse,
  parseFlashReadResponse,
  parseIdentityResponse,
  parseVersionResponse,
  pollingRateToFlash,
  isSafeConfigurationRange,
} from '../../packages/protocol/src'
import { flashIndexByKeyId } from '../../packages/device-flow-lite84/src'
import {
  KEY_ROWS,
  describeAssignment,
  type KeyboardProfile,
  type KeyAssignment,
  type Layer,
  type MacroDefinition,
  type SystemMode,
} from './config'

export const FLOW_LITE_IDENTITY = { vendorId: 0x05ac, productId: 0x024f } as const
export const CONFIGURATION_USAGE_PAGE = 0xff02
export const CONFIGURATION_USAGE = 0x0002
const TRANSACTION_TIMEOUT_MS = 900
const TRANSACTION_ATTEMPTS = 4

export interface CollectionSummary {
  usagePage: number
  usage: number
  label: string
  inputReports: number[]
  outputReports: number[]
  featureReports: number[]
  isConfigurationChannel: boolean
}

export interface DeviceSummary {
  productName: string
  vendorId: number
  productId: number
  opened: boolean
  configurationChannel: boolean
  collections: CollectionSummary[]
}

function labelCollection(usagePage: number, usage: number) {
  if (usagePage === 0x01 && usage === 0x06) return 'Keyboard'
  if (usagePage === 0x01 && usage === 0x02) return 'Pointer'
  if (usagePage === 0x0c && usage === 0x01) return 'Consumer controls'
  if (usagePage >= 0xff00) return 'Vendor-defined'
  return 'HID collection'
}

function flattenCollections(collections: HIDCollectionInfo[]): CollectionSummary[] {
  return collections.flatMap((collection) => {
    const summary: CollectionSummary = {
      usagePage: collection.usagePage,
      usage: collection.usage,
      label: labelCollection(collection.usagePage, collection.usage),
      inputReports: collection.inputReports.map((report) => report.reportId),
      outputReports: collection.outputReports.map((report) => report.reportId),
      featureReports: collection.featureReports.map((report) => report.reportId),
      isConfigurationChannel:
        collection.usagePage === CONFIGURATION_USAGE_PAGE &&
        collection.usage === CONFIGURATION_USAGE &&
        collection.inputReports.some((report) => report.reportId === REPORT_ID) &&
        collection.outputReports.some((report) => report.reportId === REPORT_ID),
    }
    return [summary, ...flattenCollections(collection.children)]
  })
}

export function summarizeDevice(device: HIDDevice): DeviceSummary {
  const collections = flattenCollections(device.collections)
  return {
    productName: device.productName,
    vendorId: device.vendorId,
    productId: device.productId,
    opened: device.opened,
    configurationChannel: collections.some((collection) => collection.isConfigurationChannel),
    collections,
  }
}

function isFlowLite(device: HIDDevice) {
  return device.vendorId === FLOW_LITE_IDENTITY.vendorId && device.productId === FLOW_LITE_IDENTITY.productId
}

function equalBytes(left: ArrayLike<number>, right: ArrayLike<number>) {
  return left.length === right.length && Array.from(left).every((value, index) => value === right[index])
}

function complementPair(value: number) {
  if (!Number.isInteger(value) || value < 0 || value > 0xff) throw new RangeError('invalid complement value')
  return Uint8Array.of(value, (0x55 - value) & 0xff)
}

function profileComparable(profile: KeyboardProfile) {
  return {
    version: profile.version,
    keymaps: profile.keymaps,
    lighting: profile.lighting,
    macros: profile.macros,
    device: profile.device,
  }
}

export class FlowLiteWebClient {
  readonly device: HIDDevice
  private pending: {
    command: number
    resolve: (data: Uint8Array) => void
    timer: ReturnType<typeof setTimeout>
  } | null = null

  constructor(device: HIDDevice) {
    this.device = device
    device.addEventListener('inputreport', this.handleInputReport)
  }

  private clearPending(command: number) {
    const pending = this.pending
    if (!pending || pending.command !== command) return
    clearTimeout(pending.timer)
    this.pending = null
  }

  private handleInputReport = (event: Event) => {
    const report = event as HIDInputReportEvent
    if (report.reportId !== REPORT_ID || !this.pending) return
    const bytes = new Uint8Array(report.data.buffer, report.data.byteOffset, report.data.byteLength)
    if (bytes[0] !== this.pending.command) return
    const pending = this.pending
    this.pending = null
    clearTimeout(pending.timer)
    pending.resolve(Uint8Array.from(bytes))
  }

  private async transactOnce(report: Uint8Array) {
    if (this.pending) throw new Error('Another HID transaction is still active.')
    const command = report[0] ?? 0
    const response = new Promise<Uint8Array>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending?.command === command) this.pending = null
        reject(new Error(`Keyboard timed out during command ${command}.`))
      }, TRANSACTION_TIMEOUT_MS)
      this.pending = { command, resolve, timer }
    })
    try {
      if (!this.device.opened) throw new Error('Keyboard disconnected before the command could be sent.')
      await this.device.sendReport(REPORT_ID, report)
      return await response
    } catch (reason) {
      this.clearPending(command)
      throw reason
    }
  }

  private async transact(report: Uint8Array) {
    let failure: unknown
    for (let attempt = 0; attempt < TRANSACTION_ATTEMPTS; attempt += 1) {
      try {
        return await this.transactOnce(report)
      } catch (reason) {
        failure = reason
        if (!this.device.opened) break
      }
    }
    throw failure instanceof Error ? failure : new Error('HID transaction failed.')
  }

  async readFlash(address: number, length: number) {
    const result = new Uint8Array(length)
    let offset = 0
    for (const command of buildReadFlashCommands(address, length)) {
      const response = parseFlashReadResponse(await this.transact(command))
      if (response.address !== address + offset) throw new Error(`Unexpected flash address ${response.address}.`)
      result.set(response.data, offset)
      offset += response.data.length
    }
    return result
  }

  async writeFlash(address: number, data: Uint8Array) {
    if (!isSafeConfigurationRange(address, data.length)) throw new Error('Protected or unverified flash range blocked.')
    for (const command of buildWriteFlashCommands(address, data)) {
      const response = parseCommandResponse(await this.transact(command))
      if (!response.ok || response.command !== Command.WriteFlash) throw new Error('Keyboard rejected a flash write.')
    }
    const readback = await this.readFlash(address, data.length)
    if (!equalBytes(readback, data)) throw new Error(`Flash verification failed at ${address}.`)
  }

  async readLightingEffect(mode: number) {
    return decodeLightEffect(await this.readFlash(lightEffectAddress(mode), 32))
  }

  private async readLayer(system: SystemMode, layer: Layer) {
    const bytes = await this.readFlash(system === 'win' ? (layer === 'normal' ? 0 : 512) : (layer === 'normal' ? 1536 : 2048), 512)
    const result: Record<string, KeyAssignment> = {}
    for (const key of KEY_ROWS.flat()) {
      const offset = key.flashIndex * 4
      const assignment = decodeKeyAssignment(bytes.slice(offset, offset + 4))
      result[key.id] = describeAssignment(assignment.type, assignment.value)
    }
    return result
  }

  private async readMacro(slot: number): Promise<MacroDefinition> {
    const header = await this.readFlash(macroAddress(slot), 32)
    const nameLength = header[0] ?? 0
    const eventCount = header[31] ?? 0
    if (nameLength === 0 || nameLength > 30 || eventCount > 70) return { name: `Macro ${slot + 1}`, events: [] }
    const record = await this.readFlash(macroAddress(slot), 33 + eventCount * 5)
    const macro = decodeMacro(record)
    if (!macro) return { name: `Macro ${slot + 1}`, events: [] }
    return {
      name: macro.name,
      events: macro.events.map((event) => ({
        status: event.status === 0 ? 'down' : 'up',
        type: event.type,
        value: event.value,
        label: describeAssignment(event.type, event.value).label,
        delay: event.delay,
      })),
    }
  }

  async readConfiguration(): Promise<KeyboardProfile> {
    const nonce = crypto.getRandomValues(new Uint8Array(8))
    const identity = parseIdentityResponse(await this.transact(buildIdentityCommand(nonce)))
    if (identity.cid !== 1 || identity.mid !== 1 || !identity.wired) throw new Error('Connected device is not a wired Flow Lite 84.')
    const firmware = parseVersionResponse(await this.transact(buildDeviceVersionCommand()))
    let batteryLevel: number | null = null
    let charging = false
    try {
      const battery = parseBatteryResponse(await this.transact(buildBatteryCommand()))
      batteryLevel = battery.level
      charging = battery.charging
    } catch { /* Battery is optional on the wired interface. */ }

    // The keyboard only permits one report-08 transaction at a time.
    const winNormal = await this.readLayer('win', 'normal')
    const winFn = await this.readLayer('win', 'fn')
    const macNormal = await this.readLayer('mac', 'normal')
    const macFn = await this.readLayer('mac', 'fn')
    const lightingState = decodeLightingState(await this.readFlash(FlashAddress.CurrentLightMode, 6))
    const effect = await this.readLightingEffect(lightingState.mode)
    const settings = decodeKeyboardSettings(await this.readFlash(FlashAddress.ReportRate, 22))
    const macros: MacroDefinition[] = []
    for (let slot = 0; slot < 15; slot += 1) macros.push(await this.readMacro(slot))

    return {
      version: 1,
      keymaps: { win: { normal: winNormal, fn: winFn }, mac: { normal: macNormal, fn: macFn } },
      lighting: {
        mode: lightingState.mode,
        enabled: lightingState.enabled,
        brightness: effect.brightness,
        speed: effect.speed,
        offTime: lightingState.offTime,
      },
      macros,
      device: {
        pollingRate: settings.pollingRate as KeyboardProfile['device']['pollingRate'],
        currentSystem: settings.currentSystem === 'mac' ? 'mac' : 'win',
        fnLock: settings.fnLock === 1,
        fullKeyLock: settings.fullKeyLock === 1,
      },
      metadata: { firmware, batteryLevel, charging, cid: identity.cid, mid: identity.mid },
    }
  }

  async writeConfiguration(profile: KeyboardProfile, baseline: KeyboardProfile) {
    for (const system of ['win', 'mac'] as const) {
      for (const layer of ['normal', 'fn'] as const) {
        for (const key of KEY_ROWS.flat()) {
          const requested = profile.keymaps[system][layer][key.id]
          const existing = baseline.keymaps[system][layer][key.id]
          if (!requested || !existing || (requested.type === existing.type && requested.value === existing.value)) continue
          await this.writeFlash(
            keymapEntryAddress(system, layer, flashIndexByKeyId[key.id] ?? key.flashIndex),
            encodeKeyAssignment({ type: requested.type, value: requested.value }),
          )
        }
      }
    }

    const lighting = profile.lighting
    const previousLighting = baseline.lighting
    const modeChanged = lighting.mode !== previousLighting.mode
    const levelChanged = lighting.brightness !== previousLighting.brightness || lighting.speed !== previousLighting.speed
    if (modeChanged || levelChanged) {
      const address = lightEffectAddress(lighting.mode)
      const header = (await this.readFlash(address, 4)).slice()
      header[1] = lighting.speed
      header[2] = lighting.brightness
      header[3] = dataChecksum(header.slice(0, 3))
      await this.writeFlash(address, header)
    }
    if (modeChanged) {
      await this.writeFlash(FlashAddress.CurrentLightMode, encodeLightingSelection(lighting.mode, lighting.enabled))
    } else if (lighting.enabled !== previousLighting.enabled) {
      await this.writeFlash(FlashAddress.LightState, complementPair(lighting.enabled ? 1 : 0))
    }
    if (lighting.offTime !== previousLighting.offTime) {
      await this.writeFlash(FlashAddress.OffLightTime, complementPair(lighting.offTime))
    }

    const settingsWrites: Array<[number, Uint8Array]> = []
    if (profile.device.pollingRate !== baseline.device.pollingRate) settingsWrites.push([FlashAddress.ReportRate, complementPair(pollingRateToFlash(profile.device.pollingRate))])
    if (profile.device.currentSystem !== baseline.device.currentSystem) settingsWrites.push([FlashAddress.CurrentSystem, complementPair(profile.device.currentSystem === 'mac' ? 1 : 0)])
    if (profile.device.fnLock !== baseline.device.fnLock) settingsWrites.push([FlashAddress.FnLockState, complementPair(profile.device.fnLock ? 1 : 0)])
    if (profile.device.fullKeyLock !== baseline.device.fullKeyLock) settingsWrites.push([FlashAddress.FullKeyLockState, complementPair(profile.device.fullKeyLock ? 1 : 0)])
    for (const [address, data] of settingsWrites) await this.writeFlash(address, data)

    for (let slot = 0; slot < profile.macros.length; slot += 1) {
      const requested = profile.macros[slot]
      const existing = baseline.macros[slot]
      if (!requested || !existing || JSON.stringify(requested) === JSON.stringify(existing)) continue
      await this.writeFlash(macroAddress(slot), encodeMacro({
        name: requested.name,
        events: requested.events.map((event) => ({
          status: event.status === 'down' ? 0 : 1,
          type: event.type,
          value: event.value,
          delay: event.delay,
        })),
      }))
    }

    const verified = await this.readConfiguration()
    if (JSON.stringify(profileComparable(verified)) !== JSON.stringify(profileComparable(profile))) {
      throw new Error('Keyboard readback differs from the requested configuration.')
    }
    return verified
  }

  async close() {
    this.device.removeEventListener('inputreport', this.handleInputReport)
    if (this.device.opened) await this.device.close()
  }
}

export async function getAuthorizedFlowLite() {
  if (!('hid' in navigator)) return null
  return (await navigator.hid.getDevices()).find(isFlowLite) ?? null
}

export function webHidCompatibility(): { supported: boolean; secure: boolean; message: string } {
  const supported = typeof navigator !== 'undefined' && 'hid' in navigator
  const secure = typeof window !== 'undefined' && window.isSecureContext
  return { supported, secure, message: !secure ? 'WebHID requires HTTPS (or localhost).' : !supported ? 'Use a current Chrome or Edge browser with WebHID enabled.' : 'WebHID is available.' }
}

export async function connectFlowLite() {
  if (!('hid' in navigator)) throw new Error('WebHID requires Chrome or Edge on localhost or HTTPS.')
  const authorized = await getAuthorizedFlowLite()
  const device = authorized ?? (await navigator.hid.requestDevice({ filters: [FLOW_LITE_IDENTITY] }))[0]
  if (!device) throw new DOMException('No device selected', 'NotFoundError')
  if (!device.opened) await device.open()
  const summary = summarizeDevice(device)
  if (!summary.configurationChannel) throw new Error('The Flow Lite configuration channel is unavailable.')
  return new FlowLiteWebClient(device)
}
