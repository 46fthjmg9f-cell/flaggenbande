import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import Dashboard from './Dashboard'
import { operatorDashboardRedirect } from './operatorRouting'
import './styles.css'

const operatorDashboardUrl = operatorDashboardRedirect(
  window.location,
  import.meta.env.VITE_OPERATOR_API_URL,
)

if (operatorDashboardUrl) {
  window.location.replace(operatorDashboardUrl)
} else {
  createRoot(document.getElementById('root')!).render(
    <StrictMode><Dashboard /></StrictMode>,
  )
}
