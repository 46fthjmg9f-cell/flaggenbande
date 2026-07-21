export const DASHBOARD_SECTIONS = [
  { id: 'app-development', label: 'App & Entwicklung' },
  { id: 'videos', label: 'Videos' },
  { id: 'social-stats', label: 'Social Stats' },
  { id: 'finance', label: 'Finanzen' },
] as const

export type DashboardSectionId = typeof DASHBOARD_SECTIONS[number]['id']

export function dashboardSectionFromHash(hash: string): DashboardSectionId {
  const requested = hash.replace(/^#\/?/, '')
  return DASHBOARD_SECTIONS.some(section => section.id === requested)
    ? requested as DashboardSectionId
    : 'app-development'
}
