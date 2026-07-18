interface HIDReportItem {
  isAbsolute: boolean
  isArray: boolean
  isBufferedBytes: boolean
  isConstant: boolean
  isLinear: boolean
  isRange: boolean
  isVolatile: boolean
  hasNull: boolean
  hasPreferredState: boolean
  reportCount: number
  reportSize: number
  unitExponent: number
  unitSystem: string
  usages: number[]
  usageMinimum?: number
  usageMaximum?: number
}

interface HIDReportInfo {
  reportId: number
  items: HIDReportItem[]
}

interface HIDCollectionInfo {
  usagePage: number
  usage: number
  type: number
  children: HIDCollectionInfo[]
  inputReports: HIDReportInfo[]
  outputReports: HIDReportInfo[]
  featureReports: HIDReportInfo[]
}

interface HIDDevice extends EventTarget {
  opened: boolean
  vendorId: number
  productId: number
  productName: string
  collections: HIDCollectionInfo[]
  open(): Promise<void>
  close(): Promise<void>
  sendReport(reportId: number, data: Uint8Array): Promise<void>
}

interface HIDInputReportEvent extends Event {
  readonly device: HIDDevice
  readonly reportId: number
  readonly data: DataView
}

interface HIDConnectionEvent extends Event {
  readonly device: HIDDevice
}

interface HIDDeviceFilter {
  vendorId?: number
  productId?: number
  usagePage?: number
  usage?: number
}

interface HID extends EventTarget {
  getDevices(): Promise<HIDDevice[]>
  requestDevice(options: { filters: HIDDeviceFilter[] }): Promise<HIDDevice[]>
}

interface Navigator {
  readonly hid: HID
}
