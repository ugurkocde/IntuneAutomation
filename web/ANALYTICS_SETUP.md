# Analytics Setup Guide

This guide will help you set up analytics tracking for your Intune Automation Website using Supabase.

## 🚀 Quick Setup

### 1. Create a Supabase Project

1. Go to [Supabase](https://supabase.com) and create a new project
2. Note down your project URL and anon key from the API settings

### 2. Set Up Environment Variables

Add these to your `.env.local` file:

```env
# Existing GitHub token
PAT="your_github_token_here"

# New Supabase variables
NEXT_PUBLIC_SUPABASE_URL="your_supabase_project_url"
NEXT_PUBLIC_SUPABASE_ANON_KEY="your_supabase_anon_key"
```

### 3. Create Database Schema

Run the SQL commands from `supabase-schema.sql` in your Supabase SQL Editor:

1. Open your Supabase project dashboard
2. Go to SQL Editor
3. Copy and paste the contents of `supabase-schema.sql`
4. Click "Run" to create all tables and functions

### 4. Install Dependencies

```bash
npm install @supabase/supabase-js
```

## 📊 What Gets Tracked

### Script Views
- When users open script details
- Includes user agent and session tracking
- Automatically aggregated for performance

### Script Downloads
- **Copy**: When users copy script to clipboard
- **Raw**: When users download .ps1 file
- **GitHub**: When users click GitHub links

### Analytics Data
- **Total Views**: All-time script views
- **Total Downloads**: All-time downloads (all types)
- **Weekly Views**: Views in the last 7 days
- **Weekly Downloads**: Downloads in the last 7 days
- **Trending Indicator**: Shows when scripts have recent activity

## 🔧 Database Schema

### Tables Created

1. **`script_views`** - Individual view events
   - `script_id`, `script_title`, `user_agent`, `session_id`, `created_at`

2. **`script_downloads`** - Individual download events
   - `script_id`, `script_title`, `download_type`, `user_agent`, `session_id`, `created_at`

3. **`script_analytics`** - Aggregated statistics (for performance)
   - `script_id`, `total_views`, `total_downloads`, `weekly_views`, `weekly_downloads`

### Automatic Features

- **Triggers**: Automatically update analytics when new events are tracked
- **Indexes**: Optimized for fast queries
- **RLS Policies**: Secure read/write permissions
- **Weekly Refresh**: Function to update weekly statistics

## 🎯 Usage in Code

### Track Script View
```typescript
import { AnalyticsService } from '~/lib/supabase-analytics';

await AnalyticsService.trackScriptView(scriptId, scriptTitle, {
  userAgent: navigator.userAgent,
  sessionId: sessionStorage.getItem('session_id')
});
```

### Track Script Download
```typescript
await AnalyticsService.trackScriptDownload(
  scriptId, 
  scriptTitle, 
  'copy', // or 'raw', 'github'
  { userAgent, sessionId }
);
```

### Get Analytics Data
```typescript
const analytics = await AnalyticsService.getAllScriptAnalytics();
const topScripts = await AnalyticsService.getTopScripts('views', 10);
```

## 🔒 Privacy & Security

- **No Personal Data**: Only tracks user agent and anonymous session IDs
- **Row Level Security**: Supabase RLS protects data access
- **Data Retention**: Includes cleanup function for old analytics data
- **Anonymous Tracking**: No user identification or persistent tracking

## 📈 Monitoring & Maintenance

### Daily Maintenance (Optional)
Set up a daily cron job or Supabase Edge Function to:
```sql
SELECT refresh_weekly_analytics();
```

### Data Cleanup (Optional)
Clean up old raw analytics data (keeps aggregated data):
```typescript
await AnalyticsService.cleanupOldData(90); // Keep 90 days
```

## 🎨 Display Features

- **Compact Number Formatting**: 1.2k, 1.5M format
- **Trending Indicators**: Shows scripts with recent activity
- **Weekly Growth**: +X indicators for recent activity
- **Fallback Data**: Uses mock data when Supabase is unavailable

## 🔧 Troubleshooting

### Common Issues

1. **Environment Variables**: Make sure both Supabase env vars are set
2. **Database Schema**: Ensure all tables were created successfully  
3. **RLS Policies**: Check that policies allow anonymous access
4. **Network Issues**: Analytics failures are gracefully handled

### Testing Analytics

1. Open script details (should track a view)
2. Copy or download a script (should track download)
3. Check Supabase dashboard for new entries in analytics tables

## 🚀 Going to Production

1. **Scale Considerations**: Current setup handles thousands of events per day
2. **Monitoring**: Set up Supabase alerts for database usage
3. **Backup**: Supabase handles automatic backups
4. **Performance**: Analytics queries are optimized with indexes

---

**That's it!** Your analytics system is now set up and will start tracking usage automatically. The script cards will show real usage statistics once data starts coming in. 