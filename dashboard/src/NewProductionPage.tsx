import VideoProductionControl from './VideoProductionControl'

export default function NewProductionPage() {
  return <section id="new-production-view" className="dashboard-view" role="tabpanel" aria-labelledby="new-production-tab" tabIndex={0}>
    <header className="compact-page-header">
      <h1>Neue Produktion</h1>
    </header>
    <VideoProductionControl />
  </section>
}
