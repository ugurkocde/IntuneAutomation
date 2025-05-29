const { createClient } = require('@supabase/supabase-js');
const { Resend } = require('resend');
const fs = require('fs').promises;
const path = require('path');
const { glob } = require('glob');

// Initialize clients
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
const resend = new Resend(process.env.RESEND_API_KEY);

// Parse PowerShell script metadata
async function parseScriptMetadata(filePath) {
  const content = await fs.readFile(filePath, 'utf8');
  const metadata = {};
  
  // Extract metadata using regex
  const patterns = {
    title: /\.TITLE\s+(.+)/i,
    version: /\.VERSION\s+(.+)/i,
    description: /\.SYNOPSIS\s+(.+)/i,
    changelog: /\.CHANGELOG\s+([\s\S]*?)(?=\n\.\w+|\n#|$)/i
  };
  
  for (const [key, pattern] of Object.entries(patterns)) {
    const match = content.match(pattern);
    metadata[key] = match ? match[1].trim() : '';
  }
  
  // Extract category from path
  const pathParts = filePath.split(path.sep);
  const scriptsIndex = pathParts.indexOf('scripts');
  metadata.category = scriptsIndex >= 0 && scriptsIndex < pathParts.length - 2 
    ? pathParts[scriptsIndex + 1] 
    : 'uncategorized';
  
  return metadata;
}

// Get all PowerShell scripts
async function getAllScripts() {
  try {
    const files = await glob('scripts/**/*.ps1');
    return files;
  } catch (error) {
    console.error('Error finding scripts:', error);
    return [];
  }
}

// Main function
async function checkAndNotify() {
  try {
    console.log('Starting script update check...');
    
    // Get all scripts
    const scriptFiles = await getAllScripts();
    const updates = [];
    const newScripts = [];
    
    // Check each script
    for (const scriptPath of scriptFiles) {
      const metadata = await parseScriptMetadata(scriptPath);
      const scriptName = path.basename(scriptPath, '.ps1');
      
      // Check if script exists in database
      const { data: existingScript, error } = await supabase
        .from('script_versions')
        .select('*')
        .eq('script_path', scriptPath)
        .single();
      
      if (error && error.code !== 'PGRST116') {
        console.error(`Error checking script ${scriptPath}:`, error);
        continue;
      }
      
      if (!existingScript) {
        // New script
        newScripts.push({
          path: scriptPath,
          name: metadata.title || scriptName,
          category: metadata.category,
          version: metadata.version,
          description: metadata.description,
          changelog: metadata.changelog
        });
        
        // Insert into database
        await supabase.from('script_versions').insert({
          script_path: scriptPath,
          script_name: metadata.title || scriptName,
          category: metadata.category,
          current_version: metadata.version,
          changelog: metadata.changelog
        });
      } else if (existingScript.current_version !== metadata.version) {
        // Updated script
        updates.push({
          path: scriptPath,
          name: metadata.title || scriptName,
          category: metadata.category,
          oldVersion: existingScript.current_version,
          newVersion: metadata.version,
          changelog: metadata.changelog
        });
        
        // Update database
        await supabase
          .from('script_versions')
          .update({
            previous_version: existingScript.current_version,
            current_version: metadata.version,
            changelog: metadata.changelog,
            last_updated: new Date().toISOString()
          })
          .eq('id', existingScript.id);
      }
    }
    
    // Send notifications if there are updates or new scripts
    if (updates.length > 0 || newScripts.length > 0) {
      await sendNotifications(updates, newScripts);
    } else {
      console.log('No updates or new scripts found.');
    }
    
  } catch (error) {
    console.error('Error in checkAndNotify:', error);
    process.exit(1);
  }
}

// Send email notifications
async function sendNotifications(updates, newScripts) {
  // Get active subscribers
  const { data: subscribers, error } = await supabase
    .from('script_subscribers')
    .select('email')
    .eq('is_active', true);
  
  if (error || !subscribers || subscribers.length === 0) {
    console.log('No active subscribers found.');
    return;
  }
  
  const emails = subscribers.map(s => s.email);
  
  // Build email content
  let emailHtml = '<h2>Intune Automation Script Updates</h2>';
  
  if (newScripts.length > 0) {
    emailHtml += '<h3>🆕 New Scripts</h3><ul>';
    for (const script of newScripts) {
      const url = `https://github.com/ugurkocde/intuneautomation/blob/main/${script.path}`;
      emailHtml += `
        <li>
          <strong>${script.name}</strong> (${script.category})
          <br>Version: ${script.version}
          <br>Description: ${script.description}
          <br><a href="${url}">View Script</a>
        </li>
      `;
    }
    emailHtml += '</ul>';
  }
  
  if (updates.length > 0) {
    emailHtml += '<h3>🔄 Updated Scripts</h3><ul>';
    for (const script of updates) {
      const url = `https://github.com/ugurkocde/intuneautomation/blob/main/${script.path}`;
      emailHtml += `
        <li>
          <strong>${script.name}</strong> (${script.category})
          <br>Version: ${script.oldVersion} → ${script.newVersion}
          <br>Changes: ${script.changelog || 'No changelog provided'}
          <br><a href="${url}">View Script</a>
        </li>
      `;
    }
    emailHtml += '</ul>';
  }
  
  emailHtml += '<hr><p><small>To unsubscribe, please contact the administrator.</small></p>';
  
  // Send email via Resend
  try {
    const { error } = await resend.emails.send({
      from: process.env.FROM_EMAIL,
      to: emails,
      subject: `Intune Automation: ${newScripts.length} new, ${updates.length} updated scripts`,
      html: emailHtml
    });
    
    if (error) {
      console.error('Error sending email:', error);
    } else {
      console.log('Notifications sent successfully!');
      
      // Log notification
      await supabase.from('notification_log').insert({
        notification_type: 'daily_update',
        recipient_count: emails.length
      });
    }
  } catch (error) {
    console.error('Error with Resend:', error);
  }
}

// Run the checker
checkAndNotify();