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
  appUnits?: Numeric
  inAppPurchaseUnits?: Numeric
  restoredInAppPurchaseUnits?: Numeric
  unclassifiedSalesUnits?: Numeric
  refunds?: Numeric
  retention?: Numeric
}

export interface Breakdown { key: string; value: number; label?: string }
export interface CloudDay { date: string; players: number; attempts: number; completed: number; averageScore: Numeric; averageDuration: Numeric; abortRate: Numeric }
export type SocialPlatform = 'youtube' | 'instagram' | 'facebook' | 'tiktok'
export type SocialSyncStatus = 'available' | 'partial' | 'not_configured' | 'error'

export interface SocialMetrics {
  views: Numeric
  reach: Numeric
  likes: Numeric
  comments: Numeric
  shares: Numeric
  saves: Numeric
  watchTimeMinutes: Numeric
  averageViewDurationSeconds: Numeric
  averageViewPercentage: Numeric
  followersGained: Numeric
}

export interface RetentionPoint {
  elapsedVideoTimeRatio: number
  audienceWatchRatio: number
  relativeRetentionPerformance: number | null
}

export interface SocialVideo {
  platform: SocialPlatform
  platformVideoId: string
  contentId: string | null
  title: string
  description: string
  publishedAt: string | null
  url: string | null
  thumbnailUrl: string | null
  status: string
  durationSeconds: Numeric
  metrics: SocialMetrics
  retention?: RetentionPoint[]
  retentionCheckedAt?: string | null
  retentionCheckStatus?: 'available' | 'error'
  retentionCheckReason?: string
}

export interface AppleSalesSummary {
  reportDate: string | null
  classificationStatus: 'complete' | 'partial' | 'unavailable'
  appUnits: Numeric
  inAppPurchaseUnits: Numeric
  restoredInAppPurchaseUnits: Numeric
  unclassifiedUnits: Numeric
  refunds: Numeric
  unknownProductTypeIdentifiers: string[]
}

export interface SocialUpload {
  platform: SocialPlatform
  platformVideoId: string
  contentId: string | null
  title: string
  description: string
  uploadedAt: string | null
  publishedAt: string | null
  scheduledAt: string | null
  url: string | null
  thumbnailUrl: string | null
  status: string
  privacyStatus: string
  uploadStatus: string
  durationSeconds: Numeric
}

export interface SocialPlatformState {
  status: SocialSyncStatus
  reason?: string
  accountName: string | null
  videoCount: number
  uploadCount?: number
  startedAt: string | null
  completedAt: string | null
}

export interface SocialData {
  schemaVersion: number
  syncedAt: string | null
  platforms: Record<SocialPlatform, SocialPlatformState>
  totals: SocialMetrics
  videos: SocialVideo[]
  uploads?: SocialUpload[]
  snapshots: Array<{
    platform: SocialPlatform
    platformVideoId: string
    capturedAt: string
    metrics: SocialMetrics
  }>
}
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
  sales?: AppleSalesSummary
  finance?: { period: string; proceeds: number; currency: string } | null
  cloudKit: {
    daily: Array<CloudDay & { mode?: string }>
    scoreDistribution: Breakdown[]
    modes: Breakdown[]
    trophies: Breakdown[]
    players?: number
    profilesUpdatedToday?: number
    totalAttempts?: number
    completedAttempts?: number
    averageScore?: Numeric
    averageDuration?: Numeric
    uniqueUsers?: number | null
    uniqueUsersLatestDay?: number | null
    identifiedUserCoverage?: Numeric
  }
  social: SocialData
}

const emptyMetrics: SocialMetrics = {
  views: null,
  reach: null,
  likes: null,
  comments: null,
  shares: null,
  saves: null,
  watchTimeMinutes: null,
  averageViewDurationSeconds: null,
  averageViewPercentage: null,
  followersGained: null,
}

const emptyPlatform = (): SocialPlatformState => ({
  status: 'not_configured',
  accountName: null,
  videoCount: 0,
  startedAt: null,
  completedAt: null,
})

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
  social: {
    schemaVersion: 1,
    syncedAt: null,
    platforms: {
      youtube: emptyPlatform(),
      instagram: emptyPlatform(),
      facebook: emptyPlatform(),
      tiktok: emptyPlatform(),
    },
    totals: emptyMetrics,
    videos: [],
    uploads: [],
    snapshots: [],
  },
}
