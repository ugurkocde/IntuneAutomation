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

// Parse script metadata (PowerShell or Shell)
async function parseScriptMetadata(filePath) {
  const content = await fs.readFile(filePath, 'utf8');
  const metadata = {};
  const isShellScript = filePath.endsWith('.sh');
  
  // Extract metadata using regex
  const patterns = isShellScript ? {
    // Shell script patterns (# FIELD: value)
    title: /#\s*TITLE:\s*(.+)/i,
    version: /#\s*VERSION:\s*(.+)/i,
    description: /#\s*SYNOPSIS:\s*(.+)/i,
    changelog: /#\s*CHANGELOG:\s*([\s\S]*?)(?=\n#\s*[A-Z]+:|\n[^#]|$)/i
  } : {
    // PowerShell patterns (.FIELD value)
    title: /\.TITLE\s+(.+)/i,
    version: /\.VERSION\s+(.+)/i,
    description: /\.SYNOPSIS\s+(.+)/i,
    changelog: /\.CHANGELOG\s+([\s\S]*?)(?=\n\.\w+|\n#|$)/i
  };
  
  for (const [key, pattern] of Object.entries(patterns)) {
    const match = content.match(pattern);
    metadata[key] = match ? match[1].trim() : '';
  }
  
  // Clean up changelog for shell scripts (remove # prefixes)
  if (isShellScript && metadata.changelog) {
    metadata.changelog = metadata.changelog
      .split('\n')
      .map(line => line.replace(/^#\s*/, '').trim())
      .filter(line => line.length > 0)
      .join('\n');
  }
  
  // Extract category from path
  const pathParts = filePath.split(path.sep);
  const scriptsIndex = pathParts.indexOf('scripts');
  metadata.category = scriptsIndex >= 0 && scriptsIndex < pathParts.length - 2 
    ? pathParts[scriptsIndex + 1] 
    : 'uncategorized';
  
  return metadata;
}

// Get all PowerShell and shell scripts
async function getAllScripts() {
  try {
    const files = await glob('scripts/**/*.{ps1,sh}');
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
      const ext = path.extname(scriptPath);
      const scriptName = path.basename(scriptPath, ext);
      
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
  
  // Build email content with professional design
  const currentDate = new Date().toLocaleDateString('en-US', { 
    weekday: 'long', 
    year: 'numeric', 
    month: 'long', 
    day: 'numeric' 
  });
  
  let emailHtml = `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        @media only screen and (max-width: 600px) {
          .container { width: 100% !important; }
          .content-padding { padding: 20px !important; }
        }
      </style>
    </head>
    <body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f0f2f5; color: #323130;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f0f2f5; padding: 40px 20px;">
        <tr>
          <td align="center">
            <table class="container" width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 2px; box-shadow: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08);">
              <!-- Header -->
              <tr>
                <td style="background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%); padding: 48px 40px; border-radius: 2px 2px 0 0;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td>
                        <h1 style="color: #ffffff; margin: 0 0 8px 0; font-size: 32px; font-weight: 600; letter-spacing: -0.5px;">Intune Automation</h1>
                        <p style="color: #e3f2fd; margin: 0; font-size: 16px; font-weight: 300;">Script Repository Update Notification</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
              
              <!-- Date and Greeting -->
              <tr>
                <td class="content-padding" style="padding: 40px 40px 24px;">
                  <p style="color: #605e5c; margin: 0 0 24px 0; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">${currentDate}</p>
                  <h2 style="color: #323130; margin: 0 0 16px 0; font-size: 24px; font-weight: 600;">Weekly Script Update Summary</h2>
                  <p style="color: #605e5c; margin: 0 0 32px 0; font-size: 16px; line-height: 1.5;">
                    The following scripts have been added or updated in the Intune Automation repository. 
                    These updates include bug fixes, performance improvements, and new functionality to enhance your Intune management capabilities.
                  </p>
                  
                  <!-- Statistics -->
                  <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 32px;">
                    <tr>
                      <td width="50%" style="padding-right: 12px;">
                        <div style="background-color: #f3f2f1; padding: 24px; border-radius: 2px; border-left: 4px solid #0078d4; text-align: center;">
                          <div style="font-size: 48px; font-weight: 300; color: #0078d4; line-height: 1;">${newScripts.length}</div>
                          <div style="color: #605e5c; margin-top: 8px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">New Scripts</div>
                        </div>
                      </td>
                      <td width="50%" style="padding-left: 12px;">
                        <div style="background-color: #f3f2f1; padding: 24px; border-radius: 2px; border-left: 4px solid #5c2d91; text-align: center;">
                          <div style="font-size: 48px; font-weight: 300; color: #5c2d91; line-height: 1;">${updates.length}</div>
                          <div style="color: #605e5c; margin-top: 8px; font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Updated Scripts</div>
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
                <td class="content-padding" style="padding: 0 40px 40px;">
                  <h3 style="color: #323130; margin: 0 0 24px 0; font-size: 20px; font-weight: 600;">
                    New Scripts Available
                  </h3>`;
    
    for (const script of newScripts) {
      // Generate script ID from path (remove file extension)
      const scriptId = path.basename(script.path, path.extname(script.path));
      const url = `https://intuneautomation.com/script/${scriptId}`;
      emailHtml += `
                  <div style="background-color: #fafafa; padding: 24px; margin-bottom: 16px; border-radius: 2px; border: 1px solid #edebe9;">
                    <h4 style="margin: 0 0 12px 0; color: #323130; font-size: 18px; font-weight: 600;">${script.name}</h4>
                    ${script.description ? `
                    <p style="color: #605e5c; margin: 0 0 16px 0; font-size: 14px; line-height: 1.5;">
                      ${script.description}
                    </p>` : ''}
                    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 16px;">
                      <tr>
                        <td style="padding: 8px 0;">
                          <span style="color: #605e5c; font-size: 14px;">Category:</span>
                          <span style="background-color: #e1dfdd; padding: 4px 12px; border-radius: 12px; color: #323130; font-size: 12px; margin-left: 8px; font-weight: 600; text-transform: capitalize;">${script.category}</span>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding: 8px 0;">
                          <span style="color: #605e5c; font-size: 14px;">Version:</span>
                          <span style="color: #323130; font-size: 14px; margin-left: 8px; font-weight: 600;">${script.version}</span>
                        </td>
                      </tr>
                    </table>
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td>
                          <a href="${url}" style="background-color: #0078d4; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 2px; display: inline-block; font-size: 14px; font-weight: 600;">View Documentation</a>
                        </td>
                        <td style="text-align: right;">
                          <a href="https://github.com/ugurkocde/intuneautomation/blob/main/${script.path}" style="color: #0078d4; text-decoration: none; font-size: 14px;">View on GitHub →</a>
                        </td>
                      </tr>
                    </table>
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
                <td class="content-padding" style="padding: 0 40px 40px;">
                  <h3 style="color: #323130; margin: 0 0 24px 0; font-size: 20px; font-weight: 600;">
                    Updated Scripts
                  </h3>`;
    
    for (const script of updates) {
      // Generate script ID from path (remove file extension)
      const scriptId = path.basename(script.path, path.extname(script.path));
      const url = `https://intuneautomation.com/script/${scriptId}`;
      const changelogHtml = script.changelog 
        ? script.changelog.split('\n').map(line => `<li style="margin: 4px 0; color: #605e5c; font-size: 14px;">${line}</li>`).join('')
        : '<li style="color: #a19f9d; font-size: 14px;">No changelog provided</li>';
        
      emailHtml += `
                  <div style="background-color: #fafafa; padding: 24px; margin-bottom: 16px; border-radius: 2px; border: 1px solid #edebe9;">
                    <h4 style="margin: 0 0 12px 0; color: #323130; font-size: 18px; font-weight: 600;">${script.name}</h4>
                    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 16px;">
                      <tr>
                        <td style="padding: 8px 0;">
                          <span style="color: #605e5c; font-size: 14px;">Category:</span>
                          <span style="background-color: #e1dfdd; padding: 4px 12px; border-radius: 12px; color: #323130; font-size: 12px; margin-left: 8px; font-weight: 600; text-transform: capitalize;">${script.category}</span>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding: 8px 0;">
                          <span style="color: #605e5c; font-size: 14px;">Version Update:</span>
                          <span style="background-color: #fce4ec; padding: 4px 8px; border-radius: 2px; color: #c5221f; font-size: 13px; font-weight: 600; margin-left: 8px; text-decoration: line-through;">${script.oldVersion}</span>
                          <span style="color: #605e5c; margin: 0 8px;">→</span>
                          <span style="background-color: #e6f4ea; padding: 4px 8px; border-radius: 2px; color: #188038; font-size: 13px; font-weight: 600;">${script.newVersion}</span>
                        </td>
                      </tr>
                    </table>
                    <div style="background-color: #f3f2f1; padding: 16px; border-radius: 2px; margin-bottom: 16px;">
                      <p style="color: #323130; margin: 0 0 8px 0; font-size: 14px; font-weight: 600;">What's Changed:</p>
                      <ul style="margin: 0; padding-left: 20px;">
                        ${changelogHtml}
                      </ul>
                    </div>
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td>
                          <a href="${url}" style="background-color: #5c2d91; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 2px; display: inline-block; font-size: 14px; font-weight: 600;">Review Changes</a>
                        </td>
                        <td style="text-align: right;">
                          <a href="https://github.com/ugurkocde/intuneautomation/blob/main/${script.path}" style="color: #5c2d91; text-decoration: none; font-size: 14px;">View on GitHub →</a>
                        </td>
                      </tr>
                    </table>
                  </div>`;
    }
    
    emailHtml += `
                </td>
              </tr>`;
  }
  
  // Footer with professional signature
  emailHtml += `
              <!-- Call to Action -->
              <tr>
                <td class="content-padding" style="padding: 0 40px 40px;">
                  <div style="background-color: #f3f2f1; padding: 24px; border-radius: 2px; text-align: center;">
                    <h4 style="color: #323130; margin: 0 0 12px 0; font-size: 18px; font-weight: 600;">Ready to Deploy?</h4>
                    <p style="color: #605e5c; margin: 0 0 20px 0; font-size: 14px; line-height: 1.5;">
                      All scripts are production-ready and thoroughly tested. Deploy with confidence using Azure Automation or run locally.
                    </p>
                    <a href="https://www.intuneautomation.com/scripts" style="background-color: #323130; color: #ffffff; padding: 12px 32px; text-decoration: none; border-radius: 2px; display: inline-block; font-size: 14px; font-weight: 600;">Browse All Scripts</a>
                  </div>
                </td>
              </tr>
              
              <!-- Footer -->
              <tr>
                <td style="background-color: #f3f2f1; padding: 40px; border-radius: 0 0 2px 2px;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td style="text-align: center;">
                        <div style="border-top: 1px solid #e1dfdd; padding-top: 24px;">
                          <p style="color: #a19f9d; font-size: 12px; margin: 0 0 8px 0;">
                            You're receiving this because you subscribed to Intune Automation updates.
                          </p>
                          <p style="margin: 0;">
                            <a href="${generateUnsubscribeUrl(emails[0])}" style="color: #605e5c; font-size: 12px; text-decoration: underline;">Unsubscribe</a>
                          </p>
                        </div>
                      </td>
                    </tr>
                  </table>
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
          from: `IntuneAutomation <${process.env.FROM_EMAIL}>`,
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