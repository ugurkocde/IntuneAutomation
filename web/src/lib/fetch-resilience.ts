// Small, dependency-free helpers that make upstream fetches (GitHub API, raw
// content) tolerant of transient failures. Kept separate from github.ts so they
// can be unit tested without pulling in env validation.

export interface RetryOptions {
  /** Total attempts including the first one. */
  attempts?: number;
  /** Base delay in ms; attempt n waits baseDelayMs * 2^(n-1). */
  baseDelayMs?: number;
  /** Decide whether a non-ok response should be retried. */
  isRetryable?: (response: Response) => boolean;
  /** Injected for tests. */
  sleep?: (ms: number) => Promise<void>;
}

const defaultSleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * 429 and 5xx are transient. GitHub also reports primary and secondary rate
 * limits as 403, distinguishable from a real permission error by the
 * x-ratelimit-remaining or retry-after headers. Other 4xx are not retried.
 */
export function isRetryableResponse(response: Response): boolean {
  const { status, headers } = response;
  if (status === 429 || (status >= 500 && status <= 599)) return true;
  if (status === 403) {
    return (
      headers.get("x-ratelimit-remaining") === "0" || headers.has("retry-after")
    );
  }
  return false;
}

/**
 * Runs fetchFn until it returns an ok response or a non-retryable status.
 * Network errors (fetchFn throwing) are retried. The last response or error
 * is surfaced to the caller once attempts are exhausted.
 */
export async function fetchWithRetry(
  fetchFn: () => Promise<Response>,
  options: RetryOptions = {},
): Promise<Response> {
  const attempts = Math.max(1, options.attempts ?? 3);
  const baseDelayMs = options.baseDelayMs ?? 250;
  const retryable = options.isRetryable ?? isRetryableResponse;
  const sleep = options.sleep ?? defaultSleep;

  let lastError: unknown;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const response = await fetchFn();
      if (response.ok || !retryable(response) || attempt === attempts) {
        return response;
      }
    } catch (error) {
      lastError = error;
      if (attempt === attempts) {
        throw error;
      }
    }
    await sleep(baseDelayMs * 2 ** (attempt - 1));
  }

  // Unreachable: the loop either returns or throws on the final attempt.
  throw lastError instanceof Error
    ? lastError
    : new Error("fetchWithRetry exhausted attempts");
}

/**
 * Maps items with at most `limit` tasks in flight. Preserves input order and
 * fails fast: the first rejection rejects the whole call.
 */
export async function mapWithConcurrency<T, R>(
  items: readonly T[],
  limit: number,
  fn: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array<R>(items.length);
  const workers = Math.max(1, Math.min(limit, items.length));
  let next = 0;

  const run = async () => {
    while (true) {
      const index = next++;
      if (index >= items.length) return;
      results[index] = await fn(items[index] as T, index);
    }
  };

  await Promise.all(Array.from({ length: workers }, run));
  return results;
}
