import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0"

const SUPABASE_URL = "http://127.0.0.1:54321"
const SUPABASE_SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

async function main() {
  console.log("Creating bucket...")
  const { data, error } = await supabaseAdmin.storage.createBucket('fieldops-media', {
    public: false,
    fileSizeLimit: 20971520,
    allowedMimeTypes: ['image/jpeg', 'image/png']
  })
  
  if (error) {
    console.error("Failed:", error)
  } else {
    console.log("Bucket created successfully:", data)
  }
}

main()
