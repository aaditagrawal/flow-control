import SwiftUI

struct DeviceView: View {
    let store: AppStore

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "Device",
                subtitle: "Manage keyboard-wide behavior and inspect hardware information."
            )
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Keyboard Behavior") {
                        VStack(spacing: 14) {
                            LabeledContent("Default layout") {
                                Picker("Default layout", selection: $store.configuration.device.currentSystem) {
                                    ForEach(KeyboardSystem.allCases) { system in
                                        Text(system.title).tag(system)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 160)
                            }

                            LabeledContent("Polling rate") {
                                Picker("Polling rate", selection: $store.configuration.device.pollingRate) {
                                    ForEach([125, 250, 500, 1000], id: \.self) { rate in
                                        Text("\(rate) Hz").tag(rate)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 160)
                            }

                            Toggle("Fn lock", isOn: $store.configuration.device.fnLock)
                            Toggle("Lock the full keyboard", isOn: $store.configuration.device.fullKeyboardLock)
                        }
                        .padding(8)
                    }

                    GroupBox("Connected Hardware") {
                        if let identity = store.identity {
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                                IdentityRow(label: "Product", value: identity.productName)
                                IdentityRow(label: "Firmware", value: identity.deviceVersion)
                                IdentityRow(label: "USB", value: String(format: "%04X:%04X", identity.vendorID, identity.productID))
                                if let customerID = identity.customerID {
                                    IdentityRow(label: "Customer ID", value: String(customerID))
                                }
                                if let modelID = identity.modelID {
                                    IdentityRow(label: "Model ID", value: String(modelID))
                                }
                                if let battery = identity.batteryPercent {
                                    IdentityRow(label: "Battery", value: "\(battery)%")
                                }
                            }
                            .padding(8)
                        } else {
                            ContentUnavailableView(
                                "No Keyboard Connected",
                                systemImage: "cable.connector",
                                description: Text("Connect the Flow Lite 84 over USB to read its hardware information.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }

                    GroupBox("Firmware") {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.secondary)
                            Text("Firmware updates are intentionally protected. This app configures supported settings without entering the keyboard bootloader.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            ConfigurationActionBar(store: store, scope: .device, workspaceName: "Device Settings")
        }
        .navigationTitle("Device")
    }
}

private struct IdentityRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
