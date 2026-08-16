const demoMode = import.meta.env.VITE_DEMO_MODE !== 'false'

export const runtimeConfig = Object.freeze({
  demoMode,
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL?.trim() || '',
  supabasePublishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() || '',
})

export function assertRuntimeConfig() {
  if (runtimeConfig.demoMode) return

  if (!runtimeConfig.supabaseUrl || !runtimeConfig.supabasePublishableKey) {
    throw new Error('Supabase mode requires VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY.')
  }
}
