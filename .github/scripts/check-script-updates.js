const { createClient } = require('@supabase/supabase-js');
const { Resend } = require('resend');
const fs = require('fs').promises;
const path = require('path');
const { glob } = require('glob');
const os = require('os');

// Initialize clients
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
const resend = new Resend(process.env.RESEND_API_KEY);

// Generate unsubscribe URL
function generateUnsubscribeUrl(email) {
  // For now, using the website URL with email parameter
  // You'll need to implement the unsubscribe page on your website
  const encodedEmail = encodeURIComponent(email);
  return `https://intuneautomation.com/unsubscribe?email=${encodedEmail}`;
}

// Write to GitHub Actions summary
async function writeToGitHubSummary(newScripts, updates) {
  const summaryFile = process.env.GITHUB_STEP_SUMMARY;
  if (!summaryFile) return; // Not running in GitHub Actions
  
  let summary = '# 📊 Script Update Check Summary\n\n';
  
  summary += `- **New Scripts:** ${newScripts.length}\n`;
  summary += `- **Updated Scripts:** ${updates.length}\n\n`;
  
  if (newScripts.length > 0) {
    summary += '## 🆕 New Scripts\n\n';
    summary += '| Script Name | Version | Category |\n';
    summary += '|-------------|---------|----------|\n';
    
    newScripts.forEach(script => {
      summary += `| ${script.name} | v${script.version} | ${script.category} |\n`;
    });
    summary += '\n';
  }
  
  if (updates.length > 0) {
    summary += '## 🔄 Updated Scripts\n\n';
    summary += '| Script Name | Old Version | New Version | Category |\n';
    summary += '|-------------|-------------|-------------|----------|\n';
    
    updates.forEach(script => {
      summary += `| ${script.name} | v${script.oldVersion} | v${script.newVersion} | ${script.category} |\n`;
    });
    summary += '\n';
  }
  
  if (newScripts.length > 0 || updates.length > 0) {
    summary += '✅ **Email notifications sent successfully**\n';
  } else {
    summary += '✨ **No new or updated scripts found**\n';
    summary += '📧 **No notifications sent**\n';
  }
  
  await fs.appendFile(summaryFile, summary);
}

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
        const { error: insertError } = await supabase.from('script_versions').insert({
          script_path: scriptPath,
          script_name: metadata.title || scriptName,
          category: metadata.category,
          current_version: metadata.version,
          changelog: metadata.changelog
        });
        
        if (insertError) {
          console.error(`Failed to insert script ${scriptPath}:`, insertError);
        } else {
          console.log(`Inserted new script: ${scriptPath}`);
        }
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
        const { error: updateError } = await supabase
          .from('script_versions')
          .update({
            previous_version: existingScript.current_version,
            current_version: metadata.version,
            changelog: metadata.changelog,
            last_updated: new Date().toISOString()
          })
          .eq('id', existingScript.id);
          
        if (updateError) {
          console.error(`Failed to update script ${scriptPath}:`, updateError);
        } else {
          console.log(`Updated script: ${scriptPath}`);
        }
      }
    }
    
    // Write to GitHub Actions summary
    await writeToGitHubSummary(newScripts, updates);
    
    // Send notifications if there are updates or new scripts
    if (updates.length > 0 || newScripts.length > 0) {
      await sendNotifications(updates, newScripts);
      console.log('Script check completed. Email notifications sent.');
    } else {
      console.log('Script check completed. No updates or new scripts found.');
    }
    
  } catch (error) {
    console.error('Error in checkAndNotify:', error);
    process.exit(1);
  }
}

// Send email notifications
async function sendNotifications(updates, newScripts) {
  // Get active subscribers - handle multiple possible boolean representations
  const { data: subscribers, error } = await supabase
    .from('script_subscribers')
    .select('email, is_active')
    .or('is_active.eq.true,is_active.eq."true",is_active.is.null');
  
  if (error) {
    console.error('Error fetching subscribers:', error);
    return;
  }
  
  if (!subscribers || subscribers.length === 0) {
    console.log('No subscribers found in database.');
    return;
  }
  
  // Filter for active subscribers (handle boolean and string representations)
  const activeSubscribers = subscribers.filter(sub => 
    sub.is_active === true || 
    sub.is_active === 'true' || 
    sub.is_active === null  // Default to active if not set
  );
  
  console.log('Found active subscribers in database.');
  
  if (activeSubscribers.length === 0) {
    console.log('No active subscribers found.');
    return;
  }
  
  const emails = activeSubscribers.map(s => s.email);
  
  // Build email content with improved design
  let emailHtml = `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="margin: 0; padding: 0; font-family: 'Segoe UI', Arial, sans-serif; background-color: #f4f4f4;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f4f4f4; padding: 20px 0;">
        <tr>
          <td align="center">
            <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
              <!-- Header -->
              <tr>
                <td style="background-color: #0078d4; padding: 40px; text-align: center; border-radius: 8px 8px 0 0;">
                  <h1 style="color: #ffffff; margin: 0; font-size: 28px;">Intune Automation Updates</h1>
                </td>
              </tr>
              
              <!-- Summary -->
              <tr>
                <td style="padding: 30px 40px;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td width="50%" style="text-align: center; padding: 20px;">
                        <div style="background-color: #e3f2fd; padding: 20px; border-radius: 8px;">
                          <div style="font-size: 36px; font-weight: bold; color: #0078d4;">${newScripts.length}</div>
                          <div style="color: #666; margin-top: 5px;">New Scripts</div>
                        </div>
                      </td>
                      <td width="50%" style="text-align: center; padding: 20px;">
                        <div style="background-color: #f3e5f5; padding: 20px; border-radius: 8px;">
                          <div style="font-size: 36px; font-weight: bold; color: #7b1fa2;">${updates.length}</div>
                          <div style="color: #666; margin-top: 5px;">Updated Scripts</div>
                        </div>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>`;
  
  // New Scripts Section
  if (newScripts.length > 0) {
    emailHtml += `
              <tr>
                <td style="padding: 0 40px 30px;">
                  <h2 style="color: #0078d4; margin: 0 0 20px 0; font-size: 24px;">
                    <span style="margin-right: 10px;">🆕</span>New Scripts
                  </h2>`;
    
    for (const script of newScripts) {
      const url = `https://github.com/ugurkocde/intuneautomation/blob/main/${script.path}`;
      emailHtml += `
                  <div style="background-color: #f8f9fa; padding: 20px; margin-bottom: 15px; border-radius: 8px; border-left: 4px solid #0078d4;">
                    <h3 style="margin: 0 0 10px 0; color: #333;">${script.name}</h3>
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td style="color: #666; padding: 5px 0;">
                          <strong>Category:</strong> <span style="background-color: #e3f2fd; padding: 2px 8px; border-radius: 4px; color: #0078d4;">${script.category}</span>
                        </td>
                      </tr>
                      <tr>
                        <td style="color: #666; padding: 5px 0;">
                          <strong>Version:</strong> ${script.version}
                        </td>
                      </tr>
                      ${script.description ? `
                      <tr>
                        <td style="color: #666; padding: 5px 0;">
                          <strong>Description:</strong> ${script.description}
                        </td>
                      </tr>` : ''}
                    </table>
                    <div style="margin-top: 15px;">
                      <a href="${url}" style="background-color: #0078d4; color: #ffffff; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block;">View Script →</a>
                    </div>
                  </div>`;
    }
    
    emailHtml += `
                </td>
              </tr>`;
  }
  
  // Updated Scripts Section
  if (updates.length > 0) {
    emailHtml += `
              <tr>
                <td style="padding: 0 40px 30px;">
                  <h2 style="color: #7b1fa2; margin: 0 0 20px 0; font-size: 24px;">
                    <span style="margin-right: 10px;">🔄</span>Updated Scripts
                  </h2>`;
    
    for (const script of updates) {
      const url = `https://github.com/ugurkocde/intuneautomation/blob/main/${script.path}`;
      const changelogHtml = script.changelog 
        ? script.changelog.split('\n').map(line => `<div style="margin: 2px 0;">• ${line}</div>`).join('')
        : '<div style="color: #999;">No changelog provided</div>';
        
      emailHtml += `
                  <div style="background-color: #f8f9fa; padding: 20px; margin-bottom: 15px; border-radius: 8px; border-left: 4px solid #7b1fa2;">
                    <h3 style="margin: 0 0 10px 0; color: #333;">${script.name}</h3>
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td style="color: #666; padding: 5px 0;">
                          <strong>Category:</strong> <span style="background-color: #f3e5f5; padding: 2px 8px; border-radius: 4px; color: #7b1fa2;">${script.category}</span>
                        </td>
                      </tr>
                      <tr>
                        <td style="color: #666; padding: 5px 0;">
                          <strong>Version:</strong> 
                          <span style="background-color: #ffebee; padding: 2px 6px; border-radius: 4px; text-decoration: line-through;">${script.oldVersion}</span>
                          <span style="margin: 0 5px;">→</span>
                          <span style="background-color: #e8f5e9; padding: 2px 6px; border-radius: 4px;">${script.newVersion}</span>
                        </td>
                      </tr>
                      <tr>
                        <td style="color: #666; padding: 10px 0 5px 0;">
                          <strong>Changes:</strong>
                          <div style="margin-top: 5px; padding-left: 10px; color: #555;">
                            ${changelogHtml}
                          </div>
                        </td>
                      </tr>
                    </table>
                    <div style="margin-top: 15px;">
                      <a href="${url}" style="background-color: #7b1fa2; color: #ffffff; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block;">View Changes →</a>
                    </div>
                  </div>`;
    }
    
    emailHtml += `
                </td>
              </tr>`;
  }
  
  // Footer with unsubscribe
  emailHtml += `
              <!-- Footer -->
              <tr>
                <td style="background-color: #f8f9fa; padding: 30px 40px; text-align: center; border-radius: 0 0 8px 8px;">
                  <p style="color: #666; margin: 0 0 15px 0; font-size: 14px;">
                    Stay updated with the latest Intune automation scripts!
                  </p>
                  <div style="margin: 20px 0;">
                    <a href="https://github.com/ugurkocde/intuneautomation" style="color: #0078d4; text-decoration: none; margin: 0 10px;">GitHub Repository</a>
                    <span style="color: #ccc;">|</span>
                    <a href="https://intuneautomation.com" style="color: #0078d4; text-decoration: none; margin: 0 10px;">Website</a>
                  </div>
                  <div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #e0e0e0;">
                    <p style="color: #999; font-size: 12px; margin: 0;">
                      You received this email because you subscribed to Intune Automation script updates.
                    </p>
                    <p style="margin: 10px 0 0 0;">
                      <a href="${generateUnsubscribeUrl(emails[0])}" style="color: #666; font-size: 12px;">Unsubscribe from these notifications</a>
                    </p>
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
  `;
  
  // Send email via Resend with rate limiting
  try {
    console.log('Sending notification emails with rate limiting...');
    
    const results = [];
    const errors = [];
    
    // Send emails with rate limiting (max 2 per second)
    for (let i = 0; i < emails.length; i++) {
      const email = emails[i];
      
      try {
        // Replace the unsubscribe URL for each recipient
        const personalizedHtml = emailHtml.replace(
          generateUnsubscribeUrl(emails[0]), 
          generateUnsubscribeUrl(email)
        );
        
        const result = await resend.emails.send({
          from: process.env.FROM_EMAIL,
          to: email,
          subject: `Intune Automation: ${newScripts.length} new, ${updates.length} updated scripts`,
          html: personalizedHtml
        });
        
        results.push(result);
        console.log(`Email sent successfully`);
        
        // Rate limiting: wait 600ms between emails (allows ~1.67 emails per second)
        if (i < emails.length - 1) {
          await new Promise(resolve => setTimeout(resolve, 600));
        }
        
      } catch (emailError) {
        console.error('Failed to send email:', emailError);
        errors.push(emailError);
      }
    }
    
    if (errors.length > 0) {
      console.error('Some emails failed to send:', errors);
    }
    
    const successCount = results.length;
    console.log('Email notifications sent successfully!');
    
    // Log notification
    if (successCount > 0) {
      await supabase.from('notification_log').insert({
        notification_type: 'daily_update',
        recipient_count: successCount,
        failed_count: errors.length
      });
    }
    
  } catch (error) {
    console.error('Error with Resend:', error);
  }
}

// Run the checker
checkAndNotify();