# Notification Scripts Implementation Guide

This guide provides implementation details for distinguishing notification scripts on the intuneautomation-website.

## Overview

Notification scripts are specialized PowerShell scripts designed exclusively for Azure Automation runbooks. They monitor Intune environments and send email alerts when specific conditions are met.

## Key Differences from Other Scripts

| Feature | Operational/Reporting Scripts | Notification Scripts |
|---------|------------------------------|---------------------|
| **Execution** | Local + Azure Automation | Azure Automation Only |
| **Output** | Files (CSV, JSON, HTML) | Email Only |
| **Authentication** | Interactive + Managed Identity | Managed Identity Only |
| **Scheduling** | Optional | Required (Daily/Weekly) |
| **Purpose** | On-demand tasks | Continuous monitoring |
| **Parameters** | Multiple options | Minimal (threshold + recipients) |

## Script Metadata Structure

All notification scripts now include PSScriptInfo metadata:

```powershell
<#PSScriptInfo
.VERSION 1.0.0
.TAGS Notification, RunbookOnly, Email, Monitoring
.EXECUTION RunbookOnly
.OUTPUT Email
.SCHEDULE Daily
.CATEGORY Notification
#>
```

## Website Implementation Components

### 1. Script Card Component Updates

Add visual indicators to distinguish notification scripts:

```jsx
// Components to add to script cards
const ScriptCard = ({ script }) => {
  const isNotification = script.tags?.includes('RunbookOnly');
  
  return (
    <div className={`script-card ${isNotification ? 'notification-script' : ''}`}>
      <div className="script-header">
        <h3>
          {isNotification && <span className="icon">🔔</span>}
          {script.title}
        </h3>
        {isNotification && (
          <div className="badges">
            <span className="badge runbook-only">Runbook Only</span>
            <span className="badge email">📧 Email</span>
          </div>
        )}
      </div>
      {isNotification && (
        <div className="schedule-info">
          📅 Runs: {script.schedule || 'Daily'}
        </div>
      )}
    </div>
  );
};
```

### 2. CSS Styling for Notification Scripts

```css
/* Notification script specific styles */
.script-card.notification-script {
  border: 2px solid #6366f1;
  background: linear-gradient(135deg, #f3f4f6 0%, #e0e7ff 100%);
}

.badge {
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 12px;
  font-weight: 600;
  margin-right: 8px;
}

.badge.runbook-only {
  background: #8b5cf6;
  color: white;
}

.badge.email {
  background: #3b82f6;
  color: white;
}

.schedule-info {
  color: #6b7280;
  font-size: 14px;
  margin-top: 8px;
}
```

### 3. Filter Component Updates

Add execution mode filtering:

```jsx
const FilterOptions = {
  executionMode: [
    { value: 'all', label: 'All Scripts' },
    { value: 'local', label: 'Local Execution' },
    { value: 'runbook', label: 'Azure Runbook' },
    { value: 'runbook-only', label: 'Runbook Only' }
  ],
  category: [
    { value: 'all', label: 'All Categories' },
    { value: 'operational', label: 'Operational' },
    { value: 'reporting', label: 'Reporting' },
    { value: 'notification', label: 'Notification' }
  ]
};
```

### 4. Script Detail Page Updates

Conditional rendering for notification scripts:

```jsx
const ScriptDetail = ({ script }) => {
  const isNotification = script.tags?.includes('RunbookOnly');
  
  return (
    <div>
      {isNotification && (
        <div className="alert alert-info">
          <h4>🚨 Azure Automation Required</h4>
          <p>This script is designed exclusively for Azure Automation runbooks and cannot be run locally.</p>
        </div>
      )}
      
      <Tabs>
        <Tab label="Overview" />
        {!isNotification && <Tab label="Local Usage" />}
        <Tab label="Azure Automation" default={isNotification} />
        {isNotification && <Tab label="Email Configuration" />}
      </Tabs>
    </div>
  );
};
```

### 5. Navigation Structure

Update site navigation to highlight notification scripts:

```jsx
const Navigation = () => (
  <nav>
    <ul>
      <li>Scripts
        <ul>
          <li>Operational Scripts</li>
          <li>Reporting Scripts</li>
          <li className="highlight">
            🔔 Notification Scripts
            <span className="new-badge">NEW</span>
          </li>
        </ul>
      </li>
      <li>Automation & Scheduling
        <ul>
          <li>Azure Automation Setup</li>
          <li className="highlight">Proactive Monitoring</li>
        </ul>
      </li>
    </ul>
  </nav>
);
```

### 6. Landing Page Section

Add dedicated section for notification scripts:

```jsx
const NotificationSection = () => (
  <section className="notification-scripts-section">
    <div className="container">
      <h2>🔔 Proactive Monitoring & Alerts</h2>
      <p className="lead">
        Set up continuous monitoring with automated email notifications for critical Intune events.
      </p>
      
      <div className="features-grid">
        <div className="feature">
          <h3>🍎 Apple Token Monitoring</h3>
          <p>Get alerts before DEP tokens expire</p>
        </div>
        <div className="feature">
          <h3>📱 Stale Device Detection</h3>
          <p>Identify inactive devices for cleanup</p>
        </div>
        <div className="feature">
          <h3>🛡️ Compliance Drift Alerts</h3>
          <p>Monitor compliance degradation</p>
        </div>
        <div className="feature">
          <h3>📦 App Deployment Failures</h3>
          <p>Track application deployment issues</p>
        </div>
      </div>
      
      <div className="cta">
        <a href="/scripts/notification" className="btn btn-primary">
          Explore Notification Scripts
        </a>
      </div>
    </div>
  </section>
);
```

### 7. Comparison Table Component

```jsx
const ScriptComparison = () => (
  <table className="comparison-table">
    <thead>
      <tr>
        <th>Feature</th>
        <th>Operational/Reporting</th>
        <th>Notification Scripts</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>Local Execution</td>
        <td>✅ Yes</td>
        <td>❌ No (Runbook Only)</td>
      </tr>
      <tr>
        <td>File Output</td>
        <td>✅ Yes</td>
        <td>❌ No</td>
      </tr>
      <tr>
        <td>Email Alerts</td>
        <td>❌ No</td>
        <td>✅ Yes</td>
      </tr>
      <tr>
        <td>Scheduling</td>
        <td>Optional</td>
        <td>Required</td>
      </tr>
      <tr>
        <td>Use Case</td>
        <td>On-demand tasks</td>
        <td>Continuous monitoring</td>
      </tr>
    </tbody>
  </table>
);
```

## Implementation Checklist

- [ ] Update script parser to read PSScriptInfo metadata
- [ ] Add notification script badges to script cards
- [ ] Implement execution mode filtering
- [ ] Create notification scripts landing page section
- [ ] Update script detail pages with conditional rendering
- [ ] Add CSS styles for notification script differentiation
- [ ] Create comparison table component
- [ ] Update navigation with notification scripts section
- [ ] Add "NEW" badges to highlight new features
- [ ] Create email configuration documentation
- [ ] Update search to handle notification-specific queries

## Script Metadata Fields

| Field | Description | Values |
|-------|-------------|---------|
| `EXECUTION` | Where the script can run | `Local`, `Runbook`, `RunbookOnly` |
| `OUTPUT` | Output type | `File`, `Email`, `Console` |
| `SCHEDULE` | Recommended schedule | `Daily`, `Weekly`, `Monthly`, `OnDemand` |
| `CATEGORY` | Script category | `Operational`, `Reporting`, `Notification` |

## User Experience Guidelines

1. **Clear Visual Distinction**: Use color, icons, and badges to immediately identify notification scripts
2. **Upfront Requirements**: Show execution requirements before users click into details
3. **Guided Setup**: Provide step-by-step Azure Automation setup instructions
4. **Warning Messages**: Alert users when trying to run notification scripts locally
5. **Filter Persistence**: Remember user's filter preferences across sessions

## Next Steps

1. Implement script metadata parser in the website codebase
2. Update UI components with notification script support
3. Create dedicated documentation pages for each notification script
4. Add setup wizards for Azure Automation configuration
5. Implement email template preview functionality