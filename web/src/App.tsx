import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import './App.css'
import {
  ASSIGNMENTS,
  KEY_ROWS,
  LIGHTING_MODES,
  LIGHTING_SLEEP_TIMES,
  createDefaultProfile,
  type AssignmentCategory,
  type KeyboardProfile,
  type KeyAssignment,
  type Layer,
  type SystemMode,
  type WorkspaceTab,
} from './config'
import { connectFlowLite, getAuthorizedFlowLite, summarizeDevice, webHidCompatibility, FlowLiteWebClient, type DeviceSummary } from './hid'
import { cloneProfile, diffProfiles, validateProfile } from './profile'

const TABS: { id: WorkspaceTab; label: string; shortcut: string }[] = [
  { id: 'keymap', label: 'Key assignment', shortcut: '⌘1' },
  { id: 'lighting', label: 'Lighting', shortcut: '⌘2' },
  { id: 'macros', label: 'Macros', shortcut: '⌘3' },
  { id: 'device', label: 'Device', shortcut: '⌘4' },
]

const CATEGORIES: AssignmentCategory[] = [
  'Basic', 'Modifier', 'Media', 'Navigation', 'Macro', 'Device', 'Mouse',
]

const RECORDING_ASSIGNMENTS = createDefaultProfile().keymaps.win.normal

function keyIdForCode(code: string) {
  if (/^Key[A-Z]$/.test(code)) return `key-${code.slice(3).toLowerCase()}`
  if (/^Digit[0-9]$/.test(code)) return `digit-${code.slice(5)}`
  if (/^F(?:[1-9]|1[0-2])$/.test(code)) return code.toLowerCase()
  if (code === 'Minus' || code === 'Equal') return `digit-${code.toLowerCase()}`
  return code.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()
}

function hex(value: number) {
  return value.toString(16).toUpperCase().padStart(4, '0')
}

function Segment<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T
  options: { value: T; label: string }[]
  onChange: (value: T) => void
}) {
  return (
    <div className="segment">
      {options.map((option) => (
        <button
          className={value === option.value ? 'active' : ''}
          key={option.value}
          type="button"
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  )
}

function KeymapPanel({
  profile,
  system,
  layer,
  selectedKey,
  onSelectKey,
  onAssign,
}: {
  profile: KeyboardProfile
  system: SystemMode
  layer: Layer
  selectedKey: string
  onSelectKey: (key: string) => void
  onAssign: (assignment: KeyAssignment) => void
}) {
  const [category, setCategory] = useState<AssignmentCategory>('Basic')
  const [search, setSearch] = useState('')
  const assignment = profile.keymaps[system][layer][selectedKey]
  const actions = ASSIGNMENTS.filter((action) =>
    action.category === category && action.label.toLowerCase().includes(search.toLowerCase()),
  )

  return (
    <div className="editor-layout">
      <section className="keyboard-workbench">
        <div className="workbench-meta">
          <span>Flow Lite 84 · ANSI</span>
          <span>{system === 'mac' ? 'macOS' : 'Windows'} / {layer === 'normal' ? 'Base' : 'Fn'}</span>
        </div>
        <div className="keyboard-shell">
          <div className="keyboard-brand">
            <span>LOFREE</span>
            <span className="roller-control">VOL</span>
          </div>
          <div className="keyboard-rows">
            {KEY_ROWS.map((row, rowIndex) => (
              <div className="keyboard-row" key={rowIndex}>
                {row.map((key) => {
                  const current = profile.keymaps[system][layer][key.id]
                  return (
                    <button
                      className={selectedKey === key.id ? 'key-button selected' : 'key-button'}
                      key={key.id}
                      style={{
                        flexGrow: key.width ?? 1,
                        flexBasis: `${(key.width ?? 1) * 42}px`,
                        marginLeft: key.spacerBefore ? `${key.spacerBefore * 12}px` : undefined,
                      }}
                      type="button"
                      onClick={() => onSelectKey(key.id)}
                      aria-label={`${key.label}, assigned to ${current?.label ?? key.label}`}
                    >
                      <span>{key.label}</span>
                      {current && current.label !== key.label && <small>{current.label}</small>}
                    </button>
                  )
                })}
              </div>
            ))}
          </div>
        </div>
        <div className="workbench-hint">
          <span className="hint-dot" />
          Select a key, then choose its new assignment. Changes stay local until Apply.
        </div>
      </section>

      <aside className="inspector">
        <div className="inspector-heading">
          <div>
            <p className="overline">Selected key</p>
            <h2>{KEY_ROWS.flat().find((key) => key.id === selectedKey)?.label ?? selectedKey}</h2>
          </div>
          <span className="assignment-code">
            {assignment ? `${assignment.type.toString(16).padStart(2, '0')}:${hex(assignment.value)}` : '--'}
          </span>
        </div>

        <div className="current-assignment">
          <span>Current assignment</span>
          <strong>{assignment?.label ?? 'Unknown'}</strong>
        </div>

        <label className="search-field">
          <span>Search actions</span>
          <input
            type="search"
            value={search}
            placeholder="Type a key or action…"
            onChange={(event) => setSearch(event.target.value)}
          />
        </label>

        <div className="category-tabs" aria-label="Assignment categories">
          {CATEGORIES.map((item) => (
            <button
              className={category === item ? 'active' : ''}
              key={item}
              type="button"
              onClick={() => setCategory(item)}
            >
              {item}
            </button>
          ))}
        </div>

        <div className="action-list">
          {actions.length > 0 ? actions.map((action) => (
            <button
              className={assignment?.type === action.type && assignment.value === action.value ? 'action-row active' : 'action-row'}
              key={`${action.type}-${action.value}`}
              type="button"
              onClick={() => onAssign(action)}
            >
              <span>{action.label}</span>
              <small>{action.category}</small>
            </button>
          )) : <p className="no-results">No matching actions.</p>}
        </div>
      </aside>
    </div>
  )
}

function LightingPanel({
  profile,
  onChange,
  onSelectMode,
}: {
  profile: KeyboardProfile
  onChange: (profile: KeyboardProfile) => void
  onSelectMode: (mode: number) => void
}) {
  const lighting = profile.lighting
  const update = (next: Partial<KeyboardProfile['lighting']>) =>
    onChange({ ...profile, lighting: { ...lighting, ...next } })

  return (
    <div className="settings-canvas">
      <section className="visual-card lighting-preview">
        <p className="overline">Effect reference</p>
        <div className={lighting.enabled ? `light-board mode-${lighting.mode}` : 'light-board off'}>
          {Array.from({ length: 48 }, (_, index) => <span key={index} />)}
        </div>
        <div className="preview-caption">
          <strong>{LIGHTING_MODES.find((mode) => mode.rawValue === lighting.mode)?.label ?? 'Custom'}</strong>
          <span>Illustration only · the keyboard is verified after Apply</span>
        </div>
      </section>

      <section className="control-card">
        <div className="control-heading">
          <div><p className="overline">Effect</p><h2>Backlight</h2></div>
          <label className="switch"><input type="checkbox" checked={lighting.enabled} onChange={(event) => update({ enabled: event.target.checked })} /><span /></label>
        </div>
        <div className="effect-grid">
          {LIGHTING_MODES.map((mode) => (
            <button className={lighting.mode === mode.rawValue ? 'effect-button active' : 'effect-button'} key={mode.rawValue} type="button" onClick={() => onSelectMode(mode.rawValue)}>
              <span className={`effect-glyph effect-${mode.rawValue}`} />
              {mode.label}
            </button>
          ))}
        </div>
        <div className="range-grid">
          <label><span>Brightness <b>{lighting.brightness}</b></span><input type="range" min="0" max="4" value={lighting.brightness} onChange={(event) => update({ brightness: Number(event.target.value) })} /></label>
          <label><span>Speed <b>{lighting.speed}</b></span><input type="range" min="0" max="4" value={lighting.speed} onChange={(event) => update({ speed: Number(event.target.value) })} /></label>
          <label><span>Light-off timer</span><select value={lighting.offTime} onChange={(event) => update({ offTime: Number(event.target.value) })}>{LIGHTING_SLEEP_TIMES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
        </div>
      </section>
    </div>
  )
}

function MacroPanel({
  profile,
  onChange,
}: {
  profile: KeyboardProfile
  onChange: (profile: KeyboardProfile) => void
}) {
  const [selected, setSelected] = useState(0)
  const [recording, setRecording] = useState(false)
  const recordedEvents = useRef<KeyboardProfile['macros'][number]['events']>([])
  const lastEventTime = useRef<number | null>(null)
  const profileRef = useRef(profile)
  profileRef.current = profile
  const macro = profile.macros[selected]

  const updateMacro = (name: string) => {
    const macros = profile.macros.map((item, index) => index === selected ? { ...item, name } : item)
    onChange({ ...profile, macros })
  }

  const replaceEvents = useCallback((events: KeyboardProfile['macros'][number]['events']) => {
    const current = profileRef.current
    const macros = current.macros.map((item, index) => index === selected ? { ...item, events } : item)
    const next = { ...current, macros }
    profileRef.current = next
    onChange(next)
  }, [onChange, selected])

  useEffect(() => {
    if (!recording) return
    const capture = (event: KeyboardEvent) => {
      if (event.repeat || recordedEvents.current.length >= 70) return
      const assignment = RECORDING_ASSIGNMENTS[keyIdForCode(event.code)]
      if (!assignment) return
      event.preventDefault()
      event.stopPropagation()
      const delay = lastEventTime.current === null ? 0 : Math.min(0xffff, Math.max(0, Math.round(event.timeStamp - lastEventTime.current)))
      lastEventTime.current = event.timeStamp
      recordedEvents.current = [...recordedEvents.current, {
        status: event.type === 'keydown' ? 'down' : 'up',
        type: assignment.type,
        value: assignment.value,
        label: assignment.label,
        delay,
      }]
      replaceEvents(recordedEvents.current)
    }
    window.addEventListener('keydown', capture, true)
    window.addEventListener('keyup', capture, true)
    return () => {
      window.removeEventListener('keydown', capture, true)
      window.removeEventListener('keyup', capture, true)
    }
  }, [recording, replaceEvents])

  const toggleRecording = () => {
    if (!recording) {
      recordedEvents.current = [...macro.events]
      lastEventTime.current = null
    }
    setRecording((current) => !current)
  }

  return (
    <div className="macro-layout">
      <aside className="macro-list">
        <div className="panel-title"><div><p className="overline">On-device storage</p><h2>15 macros</h2></div><span>{profile.macros.filter((item) => item.events.length > 0).length}/15 used</span></div>
        {profile.macros.map((item, index) => (
          <button className={selected === index ? 'macro-row active' : 'macro-row'} key={index} type="button" onClick={() => { setRecording(false); setSelected(index) }}>
            <span>{String(index + 1).padStart(2, '0')}</span><strong>{item.name}</strong><small>{item.events.length} events</small>
          </button>
        ))}
      </aside>
      <section className="macro-editor">
        <div className="macro-form-row">
          <label><span>Name</span><input maxLength={30} value={macro.name} onChange={(event) => updateMacro(event.target.value)} /></label>
          <button className="record-button" type="button" onClick={toggleRecording}><span />{recording ? 'Stop recording' : 'Record keys'}</button>
          <button className="plain-button" type="button" onClick={() => replaceEvents([])} disabled={macro.events.length === 0}>Clear</button>
        </div>
        <div className="timeline-heading"><span>Event</span><span>State</span><span>Delay</span></div>
        {macro.events.length === 0 ? (
          <div className="macro-empty"><span>◎</span><h3>No events stored</h3><p>Import a profile containing events, then assign this macro to a key.</p></div>
        ) : macro.events.map((event, index) => (
          <div className="timeline-row" key={index}><strong>{event.label}</strong><span>{event.status}</span><span>{event.delay} ms</span><button className="plain-button" type="button" onClick={() => replaceEvents(macro.events.filter((_, eventIndex) => eventIndex !== index))}>Remove</button></div>
        ))}
      </section>
    </div>
  )
}

function DevicePanel({
  profile,
  summary,
  onChange,
}: {
  profile: KeyboardProfile
  summary: DeviceSummary | null
  onChange: (profile: KeyboardProfile) => void
}) {
  const device = profile.device
  const update = (next: Partial<KeyboardProfile['device']>) => onChange({ ...profile, device: { ...device, ...next } })
  return (
    <div className="device-grid">
      <section className="control-card device-identity">
        <p className="overline">Hardware</p><h2>{summary?.productName ?? 'Flow Lite 84'}</h2>
        <dl><div><dt>USB identity</dt><dd>05AC:024F</dd></div><div><dt>Firmware</dt><dd>{profile.metadata.firmware}</dd></div><div><dt>Battery</dt><dd>{profile.metadata.batteryLevel === null ? '—' : `${profile.metadata.batteryLevel}%${profile.metadata.charging ? ' · charging' : ''}`}</dd></div><div><dt>Configuration channel</dt><dd>{summary?.configurationChannel ? 'Report 08 ready' : 'Not connected'}</dd></div><div><dt>Transport</dt><dd>Wired USB</dd></div></dl>
      </section>
      <section className="control-card">
        <p className="overline">Performance</p><h2>Keyboard behavior</h2>
        <div className="form-stack">
          <label><span>Polling rate</span><select value={device.pollingRate} onChange={(event) => update({ pollingRate: Number(event.target.value) as KeyboardProfile['device']['pollingRate'] })}><option value="125">125 Hz</option><option value="250">250 Hz</option><option value="500">500 Hz</option><option value="1000">1000 Hz</option></select></label>
          <label><span>Active layout</span><select value={device.currentSystem} onChange={(event) => update({ currentSystem: event.target.value === 'mac' ? 'mac' : 'win' })}><option value="mac">macOS</option><option value="win">Windows</option></select></label>
          <div className="toggle-row"><span><strong>Fn lock</strong><small>Keep the Fn layer active</small></span><label className="switch"><input type="checkbox" checked={device.fnLock} onChange={(event) => update({ fnLock: event.target.checked })} /><span /></label></div>
          <div className="toggle-row"><span><strong>Full keyboard lock</strong><small>Disable all key output temporarily</small></span><label className="switch"><input type="checkbox" checked={device.fullKeyLock} onChange={(event) => update({ fullKeyLock: event.target.checked })} /><span /></label></div>
        </div>
      </section>
      <section className="control-card danger-card">
        <p className="overline">Protected operations</p><h2>Recovery & firmware</h2><p>Firmware flashing, receiver pairing, and factory reset are intentionally unavailable until configuration writes pass backup and restore verification.</p><button type="button" disabled>Firmware update</button><button type="button" disabled>Factory reset</button>
      </section>
    </div>
  )
}

function App() {
  const [activeTab, setActiveTab] = useState<WorkspaceTab>('keymap')
  const [system, setSystem] = useState<SystemMode>('mac')
  const [layer, setLayer] = useState<Layer>('normal')
  const [selectedKey, setSelectedKey] = useState('escape')
  const [summary, setSummary] = useState<DeviceSummary | null>(null)
  const [connecting, setConnecting] = useState(false)
  const [applying, setApplying] = useState(false)
  const [client, setClient] = useState<FlowLiteWebClient | null>(null)
  const [connectionError, setConnectionError] = useState<string | null>(null)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [progress, setProgress] = useState<string | null>(null)
  const [savedProfile, setSavedProfile] = useState(createDefaultProfile)
  const [profile, setProfile] = useState(createDefaultProfile)
  const importRef = useRef<HTMLInputElement>(null)
  const compatibility = useMemo(webHidCompatibility, [])
  const diff = useMemo(() => diffProfiles(savedProfile, profile), [profile, savedProfile])
  const dirty = diff.keys + diff.macros + Number(diff.lighting) + Number(diff.device) > 0
  const operationRef = useRef(0)

  const releaseClient = useCallback(async (message?: string) => {
    operationRef.current += 1
    setClient((current) => { void current?.close(); return null })
    setSummary(null)
    setProgress(null)
    if (message) setStatusMessage(message)
  }, [])

  const connect = useCallback(async () => {
    if (!compatibility.supported || !compatibility.secure) { setConnectionError(compatibility.message); return }
    const operation = ++operationRef.current
    setConnecting(true); setConnectionError(null)
    try {
      const nextClient = await connectFlowLite()
      setProgress('Reading keyboard configuration…')
      const liveProfile = await nextClient.readConfiguration()
      if (operation !== operationRef.current || !nextClient.device.opened) { await nextClient.close(); return }
      setClient(nextClient)
      setSummary(summarizeDevice(nextClient.device))
      setSavedProfile(cloneProfile(liveProfile))
      setProfile(cloneProfile(liveProfile))
      setStatusMessage('Configuration read. A baseline backup is ready for export or restore.')
    } catch (reason) {
      if (operation === operationRef.current) setConnectionError(reason instanceof Error ? reason.message : 'Unable to connect')
    } finally { if (operation === operationRef.current) { setConnecting(false); setProgress(null) } }
  }, [compatibility])

  useEffect(() => {
    if (!compatibility.supported) return
    const hid = navigator.hid
    const disconnect = (rawEvent: Event) => {
      const event = rawEvent as HIDConnectionEvent
      if (client && event.device === client.device) void releaseClient('Keyboard disconnected. Staged changes were not applied.')
    }
    hid.addEventListener('disconnect', disconnect)
    return () => hid.removeEventListener('disconnect', disconnect)
  }, [client, compatibility.supported, releaseClient])

  useEffect(() => {
    if (!compatibility.supported || client || connecting) return
    let cancelled = false
    void getAuthorizedFlowLite().then((device) => {
      if (!cancelled && device) setStatusMessage('A previously permitted Flow Lite is available. Select Connect keyboard to read it.')
    }).catch(() => undefined)
    return () => { cancelled = true }
  }, [client, compatibility.supported, connecting])

  const assign = useCallback((assignment: KeyAssignment) => {
    setProfile((current) => ({
      ...current,
      keymaps: {
        ...current.keymaps,
        [system]: {
          ...current.keymaps[system],
          [layer]: { ...current.keymaps[system][layer], [selectedKey]: assignment },
        },
      },
    }))
  }, [layer, selectedKey, system])

  const exportProfile = useCallback(() => {
    const blob = new Blob([JSON.stringify(profile, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url; link.download = `flow-lite84-profile-${new Date().toISOString().slice(0, 10)}.json`; link.click()
    URL.revokeObjectURL(url)
  }, [profile])

  const importProfile = useCallback((file: File) => {
    file.text().then((text) => {
      setProfile(cloneProfile(validateProfile(JSON.parse(text))))
      setStatusMessage('Validated profile imported as staged changes. Review before applying.')
    }).catch((reason: unknown) => setConnectionError(reason instanceof Error ? reason.message : 'That profile file could not be read.'))
  }, [])

  const selectLightingMode = useCallback(async (mode: number) => {
    setConnectionError(null)
    if (!client) {
      setProfile((current) => ({ ...current, lighting: { ...current.lighting, mode } }))
      return
    }
    try {
      const effect = await client.readLightingEffect(mode)
      setProfile((current) => ({
        ...current,
        lighting: { ...current.lighting, mode, speed: effect.speed, brightness: effect.brightness },
      }))
    } catch (reason) {
      setConnectionError(reason instanceof Error ? reason.message : 'Unable to read that lighting effect.')
    }
  }, [client])

  const apply = useCallback(async () => {
    if (!client || !summary?.configurationChannel) {
      setConnectionError('Connect the wired keyboard before applying changes.')
      return
    }
    const operation = ++operationRef.current
    setApplying(true); setConnectionError(null); setStatusMessage(null); setProgress('Saving automatic backup…')
    try {
      localStorage.setItem('flow-lite84-last-backup', JSON.stringify(savedProfile))
      if (!client.device.opened) throw new Error('Keyboard disconnected before writing began.')
      setProgress(`Writing ${diff.keys} key assignment${diff.keys === 1 ? '' : 's'} and changed settings…`)
      const verified = await client.writeConfiguration(profile, savedProfile)
      if (operation !== operationRef.current || !client.device.opened) throw new Error('Keyboard disconnected before final verification completed.')
      setProfile(cloneProfile(verified))
      setSavedProfile(cloneProfile(verified))
      setStatusMessage('Applied, read back, and verified on the keyboard.')
    } catch (reason) {
      if (operation === operationRef.current) setConnectionError(reason instanceof Error ? reason.message : 'Apply failed.')
    } finally { if (operation === operationRef.current) { setApplying(false); setProgress(null) } }
  }, [client, diff.keys, profile, savedProfile, summary])

  return (
    <main className="app-shell">
      <header className="app-header">
        <div className="brand"><span className="brand-mark">84</span><div><strong>Flow Control</strong><small>for LoFree Flow Lite</small></div></div>
        <div className="header-actions">
          <button className="plain-button" type="button" onClick={() => importRef.current?.click()}>Import</button>
          <input ref={importRef} hidden type="file" accept="application/json" onChange={(event) => { const file = event.target.files?.[0]; if (file) importProfile(file) }} />
          <button className="plain-button" type="button" onClick={exportProfile}>Export</button>
          {summary && <button className="plain-button" type="button" onClick={() => void releaseClient('Keyboard disconnected safely.')}>Disconnect</button>}
          <button className={summary ? 'device-pill connected' : 'device-pill'} type="button" onClick={connect} disabled={connecting || applying}><span />{connecting ? 'Connecting…' : summary ? summary.productName : 'Connect keyboard'}</button>
        </div>
      </header>

      <aside className="app-sidebar">
        <nav>{TABS.map((tab) => <button className={activeTab === tab.id ? 'active' : ''} key={tab.id} type="button" onClick={() => setActiveTab(tab.id)}><span>{tab.label}</span><small>{tab.shortcut}</small></button>)}</nav>
        <div className="sidebar-status"><span className={summary ? 'status-dot connected' : 'status-dot'} /><div><strong>{summary ? 'Device ready' : compatibility.message}</strong><small>{summary ? `USB · Firmware ${profile.metadata.firmware}` : 'Offline editing is available; writes require a wired keyboard.'}</small></div></div>
      </aside>

      <section className="app-content">
        <div className="content-toolbar">
          <div><p className="overline">{activeTab === 'keymap' ? 'Remap every supported key' : 'On-device configuration'}</p><h1>{TABS.find((tab) => tab.id === activeTab)?.label}</h1></div>
          {activeTab === 'keymap' && <div className="toolbar-segments"><Segment value={system} options={[{ value: 'mac', label: 'macOS' }, { value: 'win', label: 'Windows' }]} onChange={setSystem} /><Segment value={layer} options={[{ value: 'normal', label: 'Base layer' }, { value: 'fn', label: 'Fn layer' }]} onChange={setLayer} /></div>}
          <div className="save-cluster"><button className="discard-button" type="button" onClick={() => { setProfile(cloneProfile(savedProfile)); setStatusMessage('Staged changes discarded; the on-keyboard baseline is unchanged.') }} disabled={!dirty || applying}>Discard</button><button className="apply-button" type="button" onClick={apply} disabled={!dirty || applying}>{applying ? 'Applying…' : 'Apply changes'} <span>{dirty ? diff.keys + diff.macros + Number(diff.lighting) + Number(diff.device) : '0'}</span></button></div>
        </div>

        {connectionError && <div className="notice"><span>!</span>{connectionError}<button type="button" onClick={() => setConnectionError(null)}>Dismiss</button></div>}
        {statusMessage && <div className="notice"><span>✓</span>{statusMessage}<button type="button" onClick={() => setStatusMessage(null)}>Dismiss</button></div>}
        {progress && <div className="notice progress" role="status"><span>…</span>{progress}</div>}

        <div className="content-body">
          {activeTab === 'keymap' && <KeymapPanel profile={profile} system={system} layer={layer} selectedKey={selectedKey} onSelectKey={setSelectedKey} onAssign={assign} />}
          {activeTab === 'lighting' && <LightingPanel profile={profile} onChange={setProfile} onSelectMode={selectLightingMode} />}
          {activeTab === 'macros' && <MacroPanel profile={profile} onChange={setProfile} />}
          {activeTab === 'device' && <DevicePanel profile={profile} summary={summary} onChange={setProfile} />}
        </div>
      </section>
    </main>
  )
}

export default App
