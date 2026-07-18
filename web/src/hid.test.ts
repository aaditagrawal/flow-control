import { describe, expect, test } from 'bun:test'
import { REPORT_ID } from '../../packages/protocol/src'
import { CONFIGURATION_USAGE, CONFIGURATION_USAGE_PAGE, summarizeDevice } from './hid'

function mockDevice(collections: HIDCollectionInfo[]): HIDDevice {
  return {
    opened: false,
    vendorId: 0x05ac,
    productId: 0x024f,
    productName: 'Air84@Lofree',
    collections,
    addEventListener() {}, removeEventListener() {}, dispatchEvent() { return true },
    open: async () => undefined, close: async () => undefined, sendReport: async () => undefined,
  } as unknown as HIDDevice
}

describe('WebHID device boundary', () => {
  test('only marks the exact vendor collection with report 08 as configurable', () => {
    const vendor = { usagePage: CONFIGURATION_USAGE_PAGE, usage: CONFIGURATION_USAGE, type: 1, children: [], inputReports: [{ reportId: REPORT_ID, items: [] }], outputReports: [{ reportId: REPORT_ID, items: [] }], featureReports: [] }
    expect(summarizeDevice(mockDevice([vendor])).configurationChannel).toBe(true)
    expect(summarizeDevice(mockDevice([{ ...vendor, outputReports: [] }])).configurationChannel).toBe(false)
    expect(summarizeDevice(mockDevice([{ ...vendor, usage: 3 }])).configurationChannel).toBe(false)
  })
})
