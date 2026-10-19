"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

interface MentionUser {
  id: string;
  full_name: string;
  avatar_url: string | null;
}

interface ConfirmedMention {
  token: string; // e.g. "@John Doe"
  uuid: string;
}

interface Props {
  mediaAssetId: string;
  companyId: string;
  accessToken: string;
  parentId?: string | null;
  placeholder?: string;
  autoFocus?: boolean;
  onPosted: () => void;
  onCancel?: () => void;
}

// Names are written into @[name](uuid) markup, so they must not contain the
// markup delimiters or newlines — strip them so MENTION_RE can't be broken.
function sanitizeName(name: string): string {
  return name.replace(/[[\]()\r\n]/g, " ").replace(/\s+/g, " ").trim();
}

/**
 * Comment input with @mention autocomplete. The textarea holds friendly display
 * text ("Hi @John Doe"); confirmed mentions are tracked separately and converted
 * to @[name](uuid) markup on submit. The server re-validates every uuid.
 */
export function PhotoCommentComposer({
  mediaAssetId,
  companyId,
  accessToken,
  parentId = null,
  placeholder = "Add a comment… use @ to mention a teammate",
  autoFocus = false,
  onPosted,
  onCancel,
}: Props) {
  const [text, setText] = useState("");
  const [mentions, setMentions] = useState<ConfirmedMention[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Autocomplete state
  const [matches, setMatches] = useState<MentionUser[]>([]);
  const [activeIdx, setActiveIdx] = useState(0);
  const [mentionStart, setMentionStart] = useState<number | null>(null);
  const taRef = useRef<HTMLTextAreaElement>(null);

  const closeDropdown = useCallback(() => {
    setMentionStart(null);
    setMatches([]);
    setActiveIdx(0);
  }, []);

  // Detect an @token immediately before the caret (no whitespace between).
  const detectMention = useCallback((value: string, caret: number) => {
    const upTo = value.slice(0, caret);
    const at = upTo.lastIndexOf("@");
    if (at === -1) return null;
    // Must be at start or preceded by whitespace, and contain no whitespace after @.
    const before = at === 0 ? " " : upTo[at - 1];
    if (!/\s/.test(before)) return null;
    const token = upTo.slice(at + 1);
    if (/\s/.test(token)) return null;
    return { start: at, query: token };
  }, []);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const value = e.target.value;
      setText(value);
      const caret = e.target.selectionStart ?? value.length;
      const detected = detectMention(value, caret);
      if (!detected) {
        closeDropdown();
        return;
      }
      setMentionStart(detected.start);
    },
    [detectMention, closeDropdown],
  );

  // Query same-company active users when the @token changes.
  useEffect(() => {
    if (mentionStart === null) return;
    const caret = taRef.current?.selectionStart ?? text.length;
    const query = text.slice(mentionStart + 1, caret);
    let cancelled = false;
    const handle = setTimeout(async () => {
      const supabase = getSupabase();
      let q = supabase
        .from("users")
        .select("id, full_name, avatar_url")
        .eq("company_id", companyId)
        .eq("is_active", true)
        .order("full_name", { ascending: true })
        .limit(8);
      if (query) q = q.ilike("full_name", `${query}%`);
      const { data } = await q;
      if (cancelled) return;
      setMatches((data as MentionUser[] | null) ?? []);
      setActiveIdx(0);
    }, 120);
    return () => {
      cancelled = true;
      clearTimeout(handle);
    };
  }, [mentionStart, text, companyId]);

  const selectMention = useCallback(
    (user: MentionUser) => {
      if (mentionStart === null) return;
      const caret = taRef.current?.selectionStart ?? text.length;
      const name = sanitizeName(user.full_name) || "user";
      const token = `@${name}`;
      const next = `${text.slice(0, mentionStart)}${token} ${text.slice(caret)}`;
      setText(next);
      setMentions((prev) =>
        prev.some((m) => m.uuid === user.id) ? prev : [...prev, { token, uuid: user.id }],
      );
      closeDropdown();
      // Restore focus after React re-render.
      requestAnimationFrame(() => {
        const pos = mentionStart + token.length + 1;
        taRef.current?.focus();
        taRef.current?.setSelectionRange(pos, pos);
      });
    },
    [mentionStart, text, closeDropdown],
  );

  // Convert display text → @[name](uuid) markup for the confirmed mentions
  // whose token still appears verbatim in the text. Longest tokens first so
  // overlapping names don't partially match.
  const buildBody = useCallback((): string => {
    let body = text.trim();
    const sorted = [...mentions].sort((a, b) => b.token.length - a.token.length);
    for (const m of sorted) {
      if (!body.includes(m.token)) continue;
      body = body.split(m.token).join(`@[${m.token.slice(1)}](${m.uuid})`);
    }
    return body;
  }, [text, mentions]);

  const handleSubmit = useCallback(async () => {
    const body = buildBody();
    if (!body || saving) return;
    setSaving(true);
    setError(null);
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/photo-comments`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          action: "create",
          media_asset_id: mediaAssetId,
          body,
          parent_id: parentId,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.message || "Failed to post comment");
        return;
      }
      setText("");
      setMentions([]);
      closeDropdown();
      onPosted();
    } catch {
      setError("Failed to post comment");
    } finally {
      setSaving(false);
    }
  }, [buildBody, saving, accessToken, mediaAssetId, parentId, closeDropdown, onPosted]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (mentionStart !== null && matches.length > 0) {
        if (e.key === "ArrowDown") {
          e.preventDefault();
          setActiveIdx((i) => (i + 1) % matches.length);
          return;
        }
        if (e.key === "ArrowUp") {
          e.preventDefault();
          setActiveIdx((i) => (i - 1 + matches.length) % matches.length);
          return;
        }
        if (e.key === "Enter" || e.key === "Tab") {
          e.preventDefault();
          selectMention(matches[activeIdx]);
          return;
        }
        if (e.key === "Escape") {
          e.preventDefault();
          closeDropdown();
          return;
        }
      }
      // Submit on plain Enter (Shift+Enter inserts a newline).
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        void handleSubmit();
      }
    },
    [mentionStart, matches, activeIdx, selectMention, closeDropdown, handleSubmit],
  );

  return (
    <div className="relative">
      <textarea
        ref={taRef}
        value={text}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        autoFocus={autoFocus}
        rows={parentId ? 2 : 3}
        maxLength={4000}
        className="w-full resize-none rounded-lg border border-stone-200 bg-card px-3 py-2 text-sm text-slate-800 focus:border-amber-500 focus:outline-none dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100"
      />

      {mentionStart !== null && matches.length > 0 && (
        <ul className="absolute z-10 mt-1 max-h-56 w-full overflow-y-auto rounded-lg border border-stone-200 bg-card py-1 shadow-lg dark:border-slate-700 dark:bg-slate-900">
          {matches.map((u, i) => (
            <li key={u.id}>
              <button
                type="button"
                onMouseDown={(e) => {
                  e.preventDefault();
                  selectMention(u);
                }}
                className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm ${
                  i === activeIdx
                    ? "bg-amber-50 text-slate-900 dark:bg-amber-950/40 dark:text-amber-100"
                    : "text-slate-700 hover:bg-stone-50 dark:text-slate-200 dark:hover:bg-slate-800"
                }`}
              >
                <span className="flex h-6 w-6 items-center justify-center rounded-full bg-stone-200 text-xs font-semibold text-slate-600 dark:bg-slate-700 dark:text-slate-200">
                  {u.full_name.charAt(0).toUpperCase()}
                </span>
                {u.full_name}
              </button>
            </li>
          ))}
        </ul>
      )}

      {error && <p className="mt-1 text-xs text-rose-600 dark:text-rose-400">{error}</p>}

      <div className="mt-2 flex items-center justify-end gap-2">
        {onCancel && (
          <button
            type="button"
            onClick={onCancel}
            className="rounded-lg px-3 py-1.5 text-sm font-medium text-slate-500 hover:bg-stone-100 dark:text-slate-400 dark:hover:bg-slate-800"
          >
            Cancel
          </button>
        )}
        <button
          type="button"
          onClick={() => void handleSubmit()}
          disabled={saving || !text.trim()}
          className="inline-flex min-h-9 items-center rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:bg-stone-100 disabled:text-slate-400 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
        >
          {saving ? "Posting…" : parentId ? "Reply" : "Comment"}
        </button>
      </div>
    </div>
  );
}
