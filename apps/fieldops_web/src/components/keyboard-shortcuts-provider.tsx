"use client";

import { useShortcutsHelp } from "@/lib/use-keyboard-shortcuts";
import { ShortcutHelpModal } from "@/components/shortcut-help-modal";

/**
 * Client-side wrapper that registers the global keyboard shortcut layer
 * and renders the help modal it can open. Drop into the app root next to
 * <CommandPalette /> so shortcuts work on every page.
 */
export function KeyboardShortcutsProvider() {
  const { shortcutsOpen, closeShortcuts } = useShortcutsHelp();
  return <ShortcutHelpModal open={shortcutsOpen} onClose={closeShortcuts} />;
}
