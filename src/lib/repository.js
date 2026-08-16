import { createClient } from '@supabase/supabase-js'
import { createDemoRepository } from './demo-repository'
import { createSupabaseRepository } from './supabase-repository'
import { assertRuntimeConfig, runtimeConfig } from './runtime-config'

export function createRepository(seed) {
  assertRuntimeConfig()
  if (runtimeConfig.demoMode) return createDemoRepository(seed)

  const client = createClient(runtimeConfig.supabaseUrl, runtimeConfig.supabasePublishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  })
  return createSupabaseRepository(client)
}

export { runtimeConfig }
