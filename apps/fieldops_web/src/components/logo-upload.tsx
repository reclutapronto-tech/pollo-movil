"use client";

import { useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";

const MAX_FILE_SIZE = 2 * 1024 * 1024; // 2MB
const ALLOWED_TYPES = ["image/png", "image/jpeg", "image/webp"];

interface LogoUploadProps {
  currentLogoUrl: string | null;
  onLogoChanged: (newUrl: string | null) => void;
}

export function LogoUpload({ currentLogoUrl, onLogoChanged }: LogoUploadProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleFileSelect(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;

    setError(null);

    // Client-side validation
    if (!ALLOWED_TYPES.includes(file.type)) {
      setError("Only PNG, JPEG, and WebP images are allowed.");
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      setError("File must be under 2MB.");
      return;
    }

    setUploading(true);

    try {
      const supabase = getSupabase();
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData.session?.access_token;

      if (!token) {
        setError("Not authenticated.");
        setUploading(false);
        return;
      }

      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;

      // Step 1: Get presigned URL
      const presignRes = await fetch(
        `${supabaseUrl}/functions/v1/company_logo`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            action: "presign",
            content_type: file.type,
          }),
        },
      );

      if (!presignRes.ok) {
        const body = await presignRes.text();
        throw new Error(body || "Failed to get upload URL.");
      }

      const { upload_url, file_key } = await presignRes.json();

      // Step 2: Upload to signed URL
      const uploadRes = await fetch(upload_url, {
        method: "PUT",
        headers: { "Content-Type": file.type },
        body: file,
      });

      if (!uploadRes.ok) {
        throw new Error("Upload failed.");
      }

      // Step 3: Finalize
      const finalizeRes = await fetch(
        `${supabaseUrl}/functions/v1/company_logo`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            action: "finalize",
            file_key,
          }),
        },
      );

      if (!finalizeRes.ok) {
        const body = await finalizeRes.text();
        throw new Error(body || "Failed to finalize upload.");
      }

      const { logo_url } = await finalizeRes.json();
      onLogoChanged(logo_url);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed.");
    } finally {
      setUploading(false);
      // Reset input so re-selecting the same file triggers onChange
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  }

  return (
    <div className="flex items-center gap-4">
      {/* Logo preview — large enough to actually read at the settings page */}
      {currentLogoUrl ? (
        <img
          src={currentLogoUrl}
          alt="Company logo"
          className="h-20 w-20 rounded-xl border border-stone-200 bg-card object-contain p-2 dark:border-slate-800 dark:bg-slate-900"
        />
      ) : (
        <div className="flex h-20 w-20 items-center justify-center rounded-xl border border-stone-200 bg-stone-50 dark:border-slate-800 dark:bg-slate-900">
          <svg
            className="h-8 w-8 text-stone-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"
            />
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"
            />
          </svg>
        </div>
      )}

      {/* Change button */}
      <button
        type="button"
        onClick={() => fileInputRef.current?.click()}
        disabled={uploading}
        className="rounded-lg border border-stone-200 px-3 py-1.5 text-xs font-medium text-slate-600 transition-colors hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
      >
        {uploading ? (
          <span className="flex items-center gap-1.5">
            <span className="h-3 w-3 animate-spin rounded-full border-2 border-stone-200 border-t-slate-600" />
            Uploading...
          </span>
        ) : (
          "Change"
        )}
      </button>

      <input
        ref={fileInputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        onChange={handleFileSelect}
        className="hidden"
      />

      {error && <p className="text-xs text-red-500">{error}</p>}
    </div>
  );
}
