export type HostSystem = "win" | "mac";
export type Layer = "normal" | "fn";

export type EvidenceLevel = "confirmed-flow-lite84" | "official-shared-driver" | "windows-static-analysis" | "inferred";

export interface KeyRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height?: number;
}

export interface PhysicalKey extends KeyRect {
  readonly id: string;
  readonly label: string;
  readonly hidUsage?: number;
}

export interface Action {
  readonly id: string;
  readonly label: string;
  readonly category: "disabled" | "keyboard" | "consumer" | "device" | "layer" | "sequence" | "mouse" | "macro";
  readonly type: number | null;
  readonly value: number | null;
  readonly evidence: EvidenceLevel;
  readonly notes?: string;
}

export interface DefaultBinding {
  readonly keyId: string;
  readonly actionId: string;
  readonly evidence: EvidenceLevel;
}

export interface LightingMode {
  readonly id: number;
  readonly rawValue: number;
  readonly label: string;
  readonly evidence: EvidenceLevel;
  readonly capabilities: readonly ("brightness" | "speed" | "color" | "direction")[];
}

export interface NumericOption {
  readonly value: number;
  readonly label: string;
}
