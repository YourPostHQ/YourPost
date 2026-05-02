/**
 * Cloudflare Email Worker for yourpost
 * 
 * Setup:
 * 1. Create a new Cloudflare Worker
 * 2. Copy this code into the worker
 * 3. Set the YOURPOST_URL secret: wrangler secret put YOURPOST_URL https://yourpost.privatedata.center
 * 4. Set the YOURPOST_API_KEY secret: wrangler secret put YOURPOST_API_KEY your-generated-api-key
 * 5. Set up Email Routing in Cloudflare Dashboard:
 *    - Go to Email Routing > Catch-all address
 *    - Select "Send to a Worker" and choose this worker
 *    - Or route specific addresses like: marketing@yourdomain.com, notifications@yourdomain.com
 */

// Export fetch handler (required for Workers)
export default {
  async fetch(request, env) {
    return new Response('yourpost email worker is running', { status: 200 });
  },
  
  async email(message, env, ctx) {
    // Log incoming email
    console.log(`Received email from: ${message.from}, to: ${message.to}, subject: ${message.headers.get('subject')}`);

    try {
      // Forward to yourpost API
      const yourpostUrl = env.YOURPOST_URL || 'https://yourpost.privatedata.center';
      const incomingUrl = `${yourpostUrl}/incoming`;

      // Construct raw email from message parts
      const rawEmail = await reconstructEmail(message);

      // Prepare headers
      const headers = {
        'Content-Type': 'message/rfc822',
      };

      // Add API key if configured
      if (env.YOURPOST_API_KEY) {
        headers['Authorization'] = `Bearer ${env.YOURPOST_API_KEY}`;
      }

      const response = await fetch(incomingUrl, {
        method: 'POST',
        headers: headers,
        body: rawEmail
      });

      if (response.ok) {
        console.log(`Email delivered to yourpost: ${await response.text()}`);
        // Optionally forward to another address
        // await message.forward("inbox@example.com");
      } else {
        console.error(`Failed to deliver to yourpost: ${response.status}`);
        message.setReject(`Delivery failed: ${response.statusText}`);
      }

    } catch (error) {
      console.error(`Error processing email: ${error}`);
      message.setReject('Temporary error processing email');
    }
  }
};

/**
 * Reconstruct raw email from Cloudflare message object
 */
async function reconstructEmail(message) {
  const parts = [];

  // Add headers
  parts.push(`From: ${message.from}`);
  parts.push(`To: ${message.to}`);
  
  for (const [key, value] of message.headers.entries()) {
    if (!['from', 'to'].includes(key.toLowerCase())) {
      parts.push(`${key}: ${value}`);
    }
  }
  parts.push('');

  // Add body - use message.text() for plain text
  if (message.text) {
    const text = await message.text();
    parts.push(text);
  }

  return parts.join('\r\n');
}

/**
 * Example routing logic (optional):
 * 
 * You can route different addresses to different handlers:
 * 
 *   switch (message.to) {
 *     case "marketing@example.com":
 *       await handleMarketingEmail(message, env);
 *       break;
 *     case "notifications@example.com":
 *       await handleNotificationEmail(message, env);
 *       break;
 *     default:
 *       message.setReject("Unknown address");
 *   }
 */
