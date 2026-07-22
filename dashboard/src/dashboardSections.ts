export const DASHBOARD_SECTIONS = [
  { id: 'new-production', label: 'Neue Produktion' },
  { id: 'production', label: 'Videos' },
  { id: 'calendar', label: 'Kalender' },
  { id: 'social-stats', label: 'Stats' },
  { id: 'app-development', label: 'App' },
  { id: 'finance', label: 'Finanzen' },
] as const

export type DashboardSectionId = typeof DASHBOARD_SECTIONS[number]['id']

export function dashboardSectionFromHash(hash: string): DashboardSectionId {
  const requested = hash.replace(/^#\/?/, '')
  if (requested === 'videos') return 'production'
  return DASHBOARD_SECTIONS.some(section => section.id === requested)
    ? requested as DashboardSectionId
    : 'new-production'
}
