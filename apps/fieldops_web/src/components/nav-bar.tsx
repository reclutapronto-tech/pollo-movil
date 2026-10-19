"use client";

/**
 * NavBar is now an alias for Sidebar.
 * The layout uses <Sidebar /> directly — this export exists for backward
 * compatibility with any page that still imports NavBar.
 */
export { Sidebar as NavBar } from "./sidebar";
