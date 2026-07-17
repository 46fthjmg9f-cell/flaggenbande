export type Numeric = number | null

export interface DailyMetric {
  date: string
  country?: string
  device?: string
  osVersion?: string
  appVersion?: string
  downloads?: Numeric
  firstTimeDownloads?: Numeric
  redownloads?: Numeric
  impressions?: Numeric
  productPageViews?: Numeric
  sessions?: Numeric
  activeDevices?: Numeric
  activeUsers?: Numeric
  installations?: Numeric
  deletions?: Numeric
  crashes?: Numeric
  revenue?: Numeric
  proceeds?: Numeric
  purchases?: Numeric
  refunds?: Numeric
  retention?: Numeric
}

export interface Breakdown { key: string; value: number; label?: string }
export interface CloudDay { date: string; players: number; attempts: number; completed: number; averageScore: Numeric; averageDuration: Numeric; abortRate: Numeric }
export interface DashboardData {
  schemaVersion: number
  generatedAt: string | null
  status: 'ok' | 'partial' | 'waiting_for_first_sync' | 'error'
  messages: string[]
  availability: Record<string, { available: boolean; reason?: string; updatedAt?: string }>
  kpis: Record<string, Numeric>
  daily: DailyMetric[]
  countries: Breakdown[]
  devices: Breakdown[]
  versions: Breakdown[]
  release?: {
    appStoreVersion?: string
    appStoreState?: string
    build?: string
    buildProcessingState?: string
  }
  finance?: { period: string; proceeds: number; currency: string } | null
  cloudKit: {
    daily: Array<CloudDay & { mode?: string }>
    scoreDistribution: Breakdown[]
    modes: Breakdown[]
    trophies: Breakdown[]
    players?: number
    profilesUpdatedToday?: number
    totalAttempts?: number
    averageScore?: Numeric
  }
}

export const emptyDashboard: DashboardData = {
  schemaVersion: 1,
  generatedAt: null,
  status: 'waiting_for_first_sync',
  messages: ['Warte auf den ersten sicheren Cloud-Export aus GitHub Actions.'],
  availability: {},
  kpis: {},
  daily: [],
  countries: [],
  devices: [],
  versions: [],
  cloudKit: { daily: [], scoreDistribution: [], modes: [], trophies: [] },
}
