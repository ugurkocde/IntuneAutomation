// Helper functions to set custom headers for Supabase RLS policies

export function getSubscriberHeaders(
  email?: string,
  unsubscribeToken?: string,
) {
  const headers: Record<string, string> = {};

  if (email) {
    headers["check_email"] = email;
    headers["email"] = email;
  }

  if (unsubscribeToken) {
    headers["unsubscribe_token"] = unsubscribeToken;
  }

  return headers;
}

export function getRateLimitHeaders(ip?: string) {
  const headers: Record<string, string> = {};

  if (ip) {
    headers["x-forwarded-for"] = ip;
  }

  return headers;
}
