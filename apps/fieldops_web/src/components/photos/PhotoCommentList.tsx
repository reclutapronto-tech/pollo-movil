"use client";

import { Fragment, useMemo, useState } from "react";
import { Trash2, CornerDownRight } from "lucide-react";
import { isSupervisorOrAbove } from "@/lib/roles";
import { PhotoCommentComposer } from "@/components/photos/PhotoCommentComposer";
import type { PhotoComment } from "@/components/photos/PhotoCommentsPanel";

const MENTION_RE = /@\[([^\]]{1,120})\]\(([0-9a-fA-F-]{36})\)/g;

function formatRelative(iso: string): string {
  const then = new Date(iso).getTime();
  const diff = Date.now() - then;
  const min = Math.round(diff / 60000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const day = Math.round(hr / 24);
  if (day < 7) return `${day}d ago`;
  return new Date(iso).toLocaleDateString();
}

/**
 * Render a comment body, turning @[name](uuid) markup into mention chips — but
 * ONLY when the uuid is in the server-validated mention set (anti-spoof: a user
 * typing literal markup can't fake a mention chip for someone not validated).
 */
function renderBody(body: string, validIds: string[]) {
  const valid = new Set(validIds.map((id) => id.toLowerCase()));
  const out: React.ReactNode[] = [];
  let last = 0;
  let key = 0;
  for (const m of body.matchAll(MENTION_RE)) {
    const idx = m.index ?? 0;
    if (idx > last) out.push(<Fragment key={key++}>{body.slice(last, idx)}</Fragment>);
    const name = m[1];
    const uuid = m[2].toLowerCase();
    if (valid.has(uuid)) {
      out.push(
        <span
          key={key++}
          className="rounded bg-amber-100 px-1 font-medium text-amber-800 dark:bg-amber-950/50 dark:text-amber-200"
        >
          @{name}
        </span>,
      );
    } else {
      out.push(<Fragment key={key++}>@{name}</Fragment>);
    }
    last = idx + m[0].length;
  }
  if (last < body.length) out.push(<Fragment key={key++}>{body.slice(last)}</Fragment>);
  return out;
}

interface Props {
  comments: PhotoComment[];
  currentUserId: string | null;
  role: string | null;
  mediaAssetId: string;
  companyId: string;
  accessToken: string;
  onChanged: () => void;
  onDelete: (commentId: string) => void;
}

export function PhotoCommentList({
  comments,
  currentUserId,
  role,
  mediaAssetId,
  companyId,
  accessToken,
  onChanged,
  onDelete,
}: Props) {
  const { roots, childrenOf } = useMemo(() => {
    const childrenOf = new Map<string, PhotoComment[]>();
    const roots: PhotoComment[] = [];
    for (const c of comments) {
      if (c.parent_id) {
        const list = childrenOf.get(c.parent_id) ?? [];
        list.push(c);
        childrenOf.set(c.parent_id, list);
      } else {
        roots.push(c);
      }
    }
    return { roots, childrenOf };
  }, [comments]);

  if (roots.length === 0) {
    return (
      <p className="py-6 text-center text-sm text-slate-400 dark:text-slate-500">
        No comments yet. Start the conversation.
      </p>
    );
  }

  return (
    <ul className="space-y-4">
      {roots.map((c) => (
        <CommentNode
          key={c.id}
          comment={c}
          depth={0}
          childrenOf={childrenOf}
          currentUserId={currentUserId}
          role={role}
          mediaAssetId={mediaAssetId}
          companyId={companyId}
          accessToken={accessToken}
          onChanged={onChanged}
          onDelete={onDelete}
        />
      ))}
    </ul>
  );
}

function CommentNode({
  comment,
  depth,
  childrenOf,
  currentUserId,
  role,
  mediaAssetId,
  companyId,
  accessToken,
  onChanged,
  onDelete,
}: {
  comment: PhotoComment;
  depth: number;
  childrenOf: Map<string, PhotoComment[]>;
  currentUserId: string | null;
  role: string | null;
  mediaAssetId: string;
  companyId: string;
  accessToken: string;
  onChanged: () => void;
  onDelete: (commentId: string) => void;
}) {
  const [replying, setReplying] = useState(false);
  const children = childrenOf.get(comment.id) ?? [];
  const canDelete =
    !comment.deleted &&
    (comment.author_id === currentUserId || isSupervisorOrAbove(role));
  const indent = depth > 0 ? "ml-6 border-l border-stone-200 pl-3 dark:border-slate-700" : "";

  return (
    <li className={indent}>
      {comment.deleted ? (
        <p className="text-sm italic text-slate-400 dark:text-slate-500">Comment deleted</p>
      ) : (
        <div>
          <div className="flex items-start gap-2">
            <span className="mt-0.5 flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-stone-200 text-xs font-semibold text-slate-600 dark:bg-slate-700 dark:text-slate-200">
              {(comment.author?.full_name ?? "?").charAt(0).toUpperCase()}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-baseline gap-2">
                <span className="text-sm font-semibold text-slate-800 dark:text-slate-100">
                  {comment.author?.full_name ?? "Unknown"}
                </span>
                <span className="text-xs text-slate-400 dark:text-slate-500">
                  {formatRelative(comment.created_at)}
                </span>
              </div>
              <p className="whitespace-pre-wrap break-words text-sm text-slate-700 dark:text-slate-200">
                {renderBody(comment.body, comment.mention_user_ids)}
              </p>
              <div className="mt-1 flex items-center gap-3">
                {depth === 0 && (
                  <button
                    onClick={() => setReplying((v) => !v)}
                    className="inline-flex items-center gap-1 text-xs font-medium text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200"
                  >
                    <CornerDownRight size={12} /> Reply
                  </button>
                )}
                {canDelete && (
                  <button
                    onClick={() => onDelete(comment.id)}
                    className="inline-flex items-center gap-1 text-xs font-medium text-slate-400 hover:text-rose-600 dark:hover:text-rose-400"
                    aria-label="Delete comment"
                  >
                    <Trash2 size={12} /> Delete
                  </button>
                )}
              </div>
            </div>
          </div>

          {replying && (
            <div className="ml-9 mt-2">
              <PhotoCommentComposer
                mediaAssetId={mediaAssetId}
                companyId={companyId}
                accessToken={accessToken}
                parentId={comment.id}
                placeholder="Write a reply…"
                autoFocus
                onPosted={() => {
                  setReplying(false);
                  onChanged();
                }}
                onCancel={() => setReplying(false)}
              />
            </div>
          )}
        </div>
      )}

      {children.length > 0 && (
        <ul className="mt-3 space-y-3">
          {children.map((child) => (
            <CommentNode
              key={child.id}
              comment={child}
              depth={depth + 1}
              childrenOf={childrenOf}
              currentUserId={currentUserId}
              role={role}
              mediaAssetId={mediaAssetId}
              companyId={companyId}
              accessToken={accessToken}
              onChanged={onChanged}
              onDelete={onDelete}
            />
          ))}
        </ul>
      )}
    </li>
  );
}
