"""Freeple Cleaner for Windows — clean, remap data, move third-party apps."""

from __future__ import annotations

import threading
import tkinter as tk
from tkinter import ttk, messagebox
from pathlib import Path

from . import __version__
from . import engine as eng


# Teal / slate palette matching macOS Freeple Cleaner
C = {
    "canvas": "#E9F3F5",
    "sidebar": "#F1F7F8",
    "card": "#FFFFFF",
    "ink": "#14242E",
    "muted": "#516672",
    "accent": "#0D8C85",
    "accent_dark": "#0A6E69",
    "warm": "#EB732E",
    "blue": "#1F6BB8",
    "danger": "#C73847",
    "chip": "#E5F5F3",
    "stroke": "#B8CCD3",
}


class FreepleApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"Freeple Cleaner for Windows  ·  v{__version__}")
        self.geometry("1100x720")
        self.minsize(980, 640)
        self.configure(bg=C["canvas"])

        self.categories: list[eng.CleanCategory] = []
        self.apps: list[eng.AppInfo] = []
        self.drives: list[dict] = []
        self.selected_drive = tk.StringVar()
        self.status = tk.StringVar(value="Ready")
        self.section = tk.StringVar(value="overview")

        self._build_style()
        self._build_layout()
        self.after(100, self.refresh_all)

    def _build_style(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TFrame", background=C["canvas"])
        style.configure("Card.TFrame", background=C["card"])
        style.configure("Side.TFrame", background=C["sidebar"])
        style.configure("TLabel", background=C["canvas"], foreground=C["ink"])
        style.configure("Card.TLabel", background=C["card"], foreground=C["ink"])
        style.configure("Muted.TLabel", background=C["canvas"], foreground=C["muted"])
        style.configure("Side.TLabel", background=C["sidebar"], foreground=C["ink"])
        style.configure("Title.TLabel", font=("Segoe UI Semibold", 22), background=C["canvas"], foreground=C["ink"])
        style.configure("H2.TLabel", font=("Segoe UI Semibold", 12), background=C["card"], foreground=C["ink"])
        style.configure("Accent.TButton", font=("Segoe UI Semibold", 10))
        style.map("Accent.TButton", background=[("active", C["accent_dark"])])

    def _build_layout(self) -> None:
        root = ttk.Frame(self, style="TFrame")
        root.pack(fill=tk.BOTH, expand=True)

        side = ttk.Frame(root, style="Side.TFrame", width=220)
        side.pack(side=tk.LEFT, fill=tk.Y)
        side.pack_propagate(False)

        brand = ttk.Label(side, text="🌿  Freeple Cleaner", style="Side.TLabel", font=("Segoe UI Semibold", 13))
        brand.pack(anchor="w", padx=16, pady=(18, 2))
        ttk.Label(side, text="Clean · Remap · Move apps", style="Side.TLabel", foreground=C["muted"]).pack(
            anchor="w", padx=18, pady=(0, 16)
        )

        self.nav_buttons: dict[str, tk.Button] = {}
        for key, label in [
            ("overview", "Overview"),
            ("clean", "Clean"),
            ("remap", "Remap Data"),
            ("apps", "Move Apps"),
            ("settings", "Settings"),
        ]:
            b = tk.Button(
                side,
                text=label,
                anchor="w",
                bd=0,
                padx=16,
                pady=10,
                font=("Segoe UI", 11),
                command=lambda k=key: self.show_section(k),
            )
            b.pack(fill=tk.X, padx=10, pady=3)
            self.nav_buttons[key] = b

        ttk.Label(side, textvariable=self.status, style="Side.TLabel", wraplength=190, font=("Segoe UI", 8)).pack(
            side=tk.BOTTOM, anchor="w", padx=14, pady=14
        )

        self.body = ttk.Frame(root, style="TFrame")
        self.body.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=18, pady=16)

        self.pages: dict[str, ttk.Frame] = {}
        self.pages["overview"] = self._page_overview()
        self.pages["clean"] = self._page_clean()
        self.pages["remap"] = self._page_remap()
        self.pages["apps"] = self._page_apps()
        self.pages["settings"] = self._page_settings()
        self.show_section("overview")

    def show_section(self, key: str) -> None:
        self.section.set(key)
        for k, frame in self.pages.items():
            frame.pack_forget()
        self.pages[key].pack(fill=tk.BOTH, expand=True)
        for k, btn in self.nav_buttons.items():
            if k == key:
                btn.configure(bg=C["accent"], fg="white", activebackground=C["accent_dark"], activeforeground="white")
            else:
                btn.configure(bg=C["sidebar"], fg=C["ink"], activebackground=C["chip"], activeforeground=C["ink"])

    def _card(self, parent) -> ttk.Frame:
        f = ttk.Frame(parent, style="Card.TFrame", padding=14)
        return f

    def _page_overview(self) -> ttk.Frame:
        page = ttk.Frame(self.body, style="TFrame")
        ttk.Label(page, text="Overview", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            page,
            text="Reclaim disk space, remap bulky folders, or park third-party apps on a portable drive. Microsoft/system apps stay on C:.",
            style="Muted.TLabel",
            wraplength=820,
        ).pack(anchor="w", pady=(4, 16))

        metrics = ttk.Frame(page, style="TFrame")
        metrics.pack(fill=tk.X)
        self.m_free = tk.StringVar(value="—")
        self.m_reclaim = tk.StringVar(value="—")
        self.m_apps = tk.StringVar(value="—")
        for i, (title, var, color) in enumerate(
            [
                ("C: free", self.m_free, C["accent"]),
                ("Reclaimable", self.m_reclaim, C["blue"]),
                ("Apps on SSD", self.m_apps, C["warm"]),
            ]
        ):
            card = self._card(metrics)
            card.grid(row=0, column=i, padx=(0 if i == 0 else 10), sticky="nsew")
            metrics.columnconfigure(i, weight=1)
            ttk.Label(card, text=title.upper(), style="Card.TLabel", foreground=C["muted"], font=("Segoe UI", 8)).pack(
                anchor="w"
            )
            tk.Label(card, textvariable=var, bg=C["card"], fg=color, font=("Segoe UI Semibold", 20)).pack(anchor="w")

        actions = ttk.Frame(page, style="TFrame")
        actions.pack(fill=tk.X, pady=18)
        tk.Button(
            actions, text="Clean system data", bg=C["accent"], fg="white", bd=0, padx=16, pady=10,
            font=("Segoe UI Semibold", 10), command=lambda: self.show_section("clean"),
        ).pack(side=tk.LEFT, padx=(0, 8))
        tk.Button(
            actions, text="Move apps to SSD", bg=C["warm"], fg="white", bd=0, padx=16, pady=10,
            font=("Segoe UI Semibold", 10), command=lambda: self.show_section("apps"),
        ).pack(side=tk.LEFT, padx=8)
        tk.Button(
            actions, text="Remap data", bg=C["card"], fg=C["ink"], bd=1, relief=tk.SOLID, padx=16, pady=10,
            font=("Segoe UI Semibold", 10), command=lambda: self.show_section("remap"),
        ).pack(side=tk.LEFT, padx=8)
        tk.Button(
            actions, text="↻ Scan", bg=C["chip"], fg=C["ink"], bd=0, padx=14, pady=10,
            command=self.refresh_all,
        ).pack(side=tk.RIGHT)
        return page

    def _page_clean(self) -> ttk.Frame:
        page = ttk.Frame(self.body, style="TFrame")
        ttk.Label(page, text="Clean", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            page,
            text="Select safe user-level caches and temp folders to delete.",
            style="Muted.TLabel",
        ).pack(anchor="w", pady=(0, 10))

        bar = ttk.Frame(page, style="TFrame")
        bar.pack(fill=tk.X, pady=6)
        tk.Button(bar, text="Select all", command=lambda: self._select_cats(True), bd=0, bg=C["chip"]).pack(side=tk.LEFT)
        tk.Button(bar, text="Select none", command=lambda: self._select_cats(False), bd=0, bg=C["chip"]).pack(
            side=tk.LEFT, padx=6
        )
        tk.Button(
            bar, text="Clean selected", bg=C["danger"], fg="white", bd=0, padx=12, pady=6,
            command=self.do_clean,
        ).pack(side=tk.RIGHT)

        self.clean_list = tk.Listbox(page, activestyle="dotbox", font=("Segoe UI", 10), selectmode=tk.MULTIPLE)
        self.clean_list.pack(fill=tk.BOTH, expand=True, pady=8)
        self.clean_list.configure(bg=C["card"], fg=C["ink"], highlightthickness=1, highlightbackground=C["stroke"])
        return page

    def _page_remap(self) -> ttk.Frame:
        page = ttk.Frame(self.body, style="TFrame")
        ttk.Label(page, text="Remap Data", style="Title.TLabel").pack(anchor="w")
        ttk.Label(
            page,
            text="Move bulky folders (npm, NuGet, pip caches) to a portable drive via directory junctions.",
            style="Muted.TLabel",
            wraplength=820,
        ).pack(anchor="w", pady=(0, 10))

        drive_row = ttk.Frame(page, style="TFrame")
        drive_row.pack(fill=tk.X, pady=6)
        ttk.Label(drive_row, text="Target drive").pack(side=tk.LEFT)
        self.drive_combo = ttk.Combobox(drive_row, textvariable=self.selected_drive, state="readonly", width=48)
        self.drive_combo.pack(side=tk.LEFT, padx=8)
        tk.Button(drive_row, text="Refresh drives", command=self.refresh_drives, bd=0, bg=C["chip"]).pack(side=tk.LEFT)

        self.remap_targets = [
            ("npm", "npm Cache", Path.home() / "AppData/Local/npm-cache"),
            ("nuget", "NuGet packages", Path.home() / ".nuget" / "packages"),
            ("pip", "pip Cache", Path(__import__("os").environ.get("LOCALAPPDATA", "")) / "pip" / "Cache"),
        ]
        self.remap_box = tk.Listbox(page, font=("Segoe UI", 10))
        self.remap_box.pack(fill=tk.BOTH, expand=True, pady=8)
        tk.Button(
            page, text="Remap selected folder", bg=C["blue"], fg="white", bd=0, padx=12, pady=8,
            command=self.do_remap,
        ).pack(anchor="e")
        return page

    def _page_apps(self) -> ttk.Frame:
        page = ttk.Frame(self.body, style="TFrame")
        head = ttk.Frame(page, style="TFrame")
        head.pack(fill=tk.X)
        ttk.Label(head, text="Move Apps", style="Title.TLabel").pack(side=tk.LEFT)
        tk.Label(head, text=" NEW ", bg=C["warm"], fg="white", font=("Segoe UI Semibold", 8)).pack(
            side=tk.LEFT, padx=8, pady=8
        )
        ttk.Label(
            page,
            text="Microsoft & Windows apps stay on this PC. Third-party apps can move to your portable SSD with a junction left behind.",
            style="Muted.TLabel",
            wraplength=820,
        ).pack(anchor="w", pady=(4, 10))

        bar = ttk.Frame(page, style="TFrame")
        bar.pack(fill=tk.X)
        ttk.Label(bar, text="SSD").pack(side=tk.LEFT)
        self.app_drive_combo = ttk.Combobox(bar, textvariable=self.selected_drive, state="readonly", width=40)
        self.app_drive_combo.pack(side=tk.LEFT, padx=8)
        tk.Button(bar, text="Select third-party", command=lambda: self._select_apps(True), bd=0, bg=C["chip"]).pack(
            side=tk.LEFT, padx=4
        )
        tk.Button(bar, text="Clear", command=lambda: self._select_apps(False), bd=0, bg=C["chip"]).pack(side=tk.LEFT)
        tk.Button(
            bar, text="Move to SSD", bg=C["accent"], fg="white", bd=0, padx=14, pady=7,
            command=self.do_move_apps,
        ).pack(side=tk.RIGHT)

        cols = ("sel", "name", "size", "type", "path")
        self.app_tree = ttk.Treeview(page, columns=cols, show="headings", selectmode="extended")
        self.app_tree.heading("sel", text="")
        self.app_tree.heading("name", text="Application")
        self.app_tree.heading("size", text="Size")
        self.app_tree.heading("type", text="Type")
        self.app_tree.heading("path", text="Path")
        self.app_tree.column("sel", width=40, anchor="center")
        self.app_tree.column("name", width=220)
        self.app_tree.column("size", width=90, anchor="e")
        self.app_tree.column("type", width=120)
        self.app_tree.column("path", width=420)
        self.app_tree.pack(fill=tk.BOTH, expand=True, pady=10)
        self.app_tree.bind("<Double-1>", self._toggle_app_row)
        return page

    def _page_settings(self) -> ttk.Frame:
        page = ttk.Frame(self.body, style="TFrame")
        ttk.Label(page, text="Settings", style="Title.TLabel").pack(anchor="w")
        card = self._card(page)
        card.pack(fill=tk.X, pady=12)
        ttk.Label(card, text="About", style="H2.TLabel").pack(anchor="w")
        ttk.Label(card, text=f"Freeple Cleaner for Windows  v{__version__}", style="Card.TLabel").pack(anchor="w", pady=4)
        ttk.Label(
            card,
            text="Cleans user caches, remaps folders with junctions, and moves third-party apps to a portable drive. System/Microsoft apps are never moved.",
            style="Card.TLabel",
            wraplength=780,
            foreground=C["muted"],
        ).pack(anchor="w")
        ttk.Label(card, text=f"Data folder: {eng.APP_SUPPORT}", style="Card.TLabel", foreground=C["muted"]).pack(
            anchor="w", pady=(8, 0)
        )
        return page

    # ----- actions -----

    def refresh_all(self) -> None:
        self.status.set("Scanning…")
        self.refresh_drives()

        def work():
            cats = eng.scan_categories(eng.default_categories())
            apps = eng.scan_installed_apps()
            total, free = eng.boot_disk_stats()
            remapped_apps = len(eng.load_json(eng.APP_REMAP_DB, {"records": []}).get("records", []))
            reclaim = sum(c.size for c in cats)

            def apply():
                self.categories = cats
                self.apps = apps
                self.m_free.set(eng.human_size(free))
                self.m_reclaim.set(eng.human_size(reclaim))
                self.m_apps.set(str(remapped_apps))
                self._fill_clean()
                self._fill_remap()
                self._fill_apps()
                self.status.set(
                    f"Scan complete — {eng.human_size(reclaim)} reclaimable · "
                    f"{sum(1 for a in apps if not a.is_system)} third-party apps"
                )

            self.after(0, apply)

        threading.Thread(target=work, daemon=True).start()

    def refresh_drives(self) -> None:
        self.drives = eng.list_removable_drives()
        labels = []
        for d in self.drives:
            mark = "★ " if (d["portable"] or not d["path"].upper().startswith("C:")) else ""
            labels.append(f"{mark}{d['name']}  ({d['path']})  — {eng.human_size(d['free'])} free")
        self.drive_combo["values"] = labels
        self.app_drive_combo["values"] = labels
        if labels and not self.selected_drive.get():
            # Prefer non-C
            for i, d in enumerate(self.drives):
                if not d["path"].upper().startswith("C:"):
                    self.selected_drive.set(labels[i])
                    break
            else:
                self.selected_drive.set(labels[0])

    def _current_volume(self) -> Path | None:
        label = self.selected_drive.get()
        for i, d in enumerate(self.drives):
            if label.startswith("★ "):
                cmp = f"★ {d['name']}  ({d['path']})"
            else:
                cmp = f"{d['name']}  ({d['path']})"
            if label.startswith(cmp) or d["path"] in label:
                return Path(d["path"])
        if self.drives:
            return Path(self.drives[0]["path"])
        return None

    def _fill_clean(self) -> None:
        self.clean_list.delete(0, tk.END)
        for c in self.categories:
            mark = "☑" if c.selected else "☐"
            self.clean_list.insert(tk.END, f"  {mark}  {c.title}    {eng.human_size(c.size)}")

    def _fill_remap(self) -> None:
        self.remap_box.delete(0, tk.END)
        for _id, title, path in self.remap_targets:
            exists = path.exists()
            size = eng.dir_size(path) if exists else 0
            self.remap_box.insert(
                tk.END,
                f"{title}  —  {eng.human_size(size) if exists else 'not found'}  —  {path}",
            )

    def _fill_apps(self) -> None:
        self.app_tree.delete(*self.app_tree.get_children())
        for i, a in enumerate(self.apps):
            kind = "Apple/System".replace("Apple/", "") if a.is_system else "Third-party"
            if a.is_system:
                kind = "Microsoft / System"
            if a.remapped:
                kind = "On SSD"
            mark = "☑" if a.selected else ("🔒" if a.is_system else "☐")
            self.app_tree.insert(
                "",
                tk.END,
                iid=str(i),
                values=(mark, a.name, eng.human_size(a.size), kind, a.path),
            )

    def _select_cats(self, on: bool) -> None:
        for c in self.categories:
            c.selected = on and c.size > 0
        self._fill_clean()

    def _select_apps(self, on: bool) -> None:
        for a in self.apps:
            if not a.is_system and not a.remapped:
                a.selected = on
        self._fill_apps()

    def _toggle_app_row(self, _event=None) -> None:
        sel = self.app_tree.selection()
        for iid in sel:
            i = int(iid)
            app = self.apps[i]
            if app.is_system or app.remapped:
                continue
            app.selected = not app.selected
        self._fill_apps()

    def do_clean(self) -> None:
        # Sync selection from listbox highlights optionally — use selected flags + clicked lines
        selected_indices = set(self.clean_list.curselection())
        for i, c in enumerate(self.categories):
            if selected_indices:
                c.selected = i in selected_indices
        chosen = [c for c in self.categories if c.selected]
        if not chosen:
            messagebox.showinfo("Freeple Cleaner", "Select at least one category.")
            return
        if not messagebox.askyesno("Confirm clean", f"Permanently delete data from {len(chosen)} categories?"):
            return

        def work():
            freed = 0
            warns = []
            for c in chosen:
                f, w = eng.clean_category(c)
                freed += f
                warns.extend(w)
            self.after(0, lambda: self._clean_done(freed, warns))

        self.status.set("Cleaning…")
        threading.Thread(target=work, daemon=True).start()

    def _clean_done(self, freed: int, warns: list[str]) -> None:
        self.status.set(f"Freed about {eng.human_size(freed)}")
        if warns:
            messagebox.showwarning("Finished with warnings", "\n".join(warns[:12]))
        self.refresh_all()

    def do_remap(self) -> None:
        vol = self._current_volume()
        if not vol:
            messagebox.showerror("No drive", "Select a target drive first.")
            return
        sel = self.remap_box.curselection()
        if not sel:
            messagebox.showinfo("Remap", "Select a folder to remap.")
            return
        idx = sel[0]
        cid, title, path = self.remap_targets[idx]
        if not path.exists():
            messagebox.showerror("Missing", f"{title} was not found.")
            return
        try:
            eng.remap_folder(title, cid, path, vol)
            messagebox.showinfo("Remapped", f"{title} → {vol / eng.DATA_DIR_NAME / cid}")
            self.refresh_all()
        except Exception as e:
            messagebox.showerror("Remap failed", str(e))

    def do_move_apps(self) -> None:
        vol = self._current_volume()
        if not vol:
            messagebox.showerror("No drive", "Select a portable/target drive first.")
            return
        if vol.resolve().as_posix().upper().startswith("C:"):
            if not messagebox.askyesno(
                "Confirm",
                "Selected drive looks like C:. Continue anyway? Prefer a portable SSD.",
            ):
                return
        chosen = [a for a in self.apps if a.selected and not a.is_system and not a.remapped]
        if not chosen:
            messagebox.showinfo("Move Apps", "Select one or more third-party apps (double-click rows to toggle).")
            return
        if not messagebox.askyesno(
            "Move apps",
            f"Move {len(chosen)} app(s) to {vol}?\nKeep the drive connected while using them.",
        ):
            return

        def work():
            try:
                moved, warns = eng.move_apps(chosen, vol)
                self.after(0, lambda: self._move_done(moved, warns))
            except Exception as e:
                self.after(0, lambda: messagebox.showerror("Move failed", str(e)))

        self.status.set("Moving apps…")
        threading.Thread(target=work, daemon=True).start()

    def _move_done(self, moved: int, warns: list[str]) -> None:
        self.status.set(f"Moved {moved} app(s)")
        if warns:
            messagebox.showwarning("Finished with notes", "\n".join(warns[:15]))
        else:
            messagebox.showinfo("Done", f"Moved {moved} app(s) to your drive.")
        self.refresh_all()


def main() -> None:
    eng.ensure_support()
    app = FreepleApp()
    app.mainloop()


if __name__ == "__main__":
    main()
