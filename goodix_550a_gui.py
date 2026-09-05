#!/usr/bin/env python3
"""GTK3 setup and support utility for the Goodix 27c6:550a reader."""

from __future__ import annotations

from pathlib import Path
import os
import subprocess
import sys
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "lib"))

from gui_backend import USB_ID, collect_state, current_user, state_summary  # noqa: E402

FINGERS = (
    ("Right index", "right-index-finger"),
    ("Left index", "left-index-finger"),
    ("Right thumb", "right-thumb"),
    ("Left thumb", "left-thumb"),
    ("Right middle", "right-middle-finger"),
    ("Left middle", "left-middle-finger"),
)


class GoodixWindow(Gtk.ApplicationWindow):
    def __init__(self, application: Gtk.Application) -> None:
        super().__init__(application=application, title="Goodix Fingerprint Setup")
        self.set_default_size(760, 610)
        self.set_border_width(0)
        self.user = current_user()
        self.busy = False
        self.cancellable = False
        self.process: subprocess.Popen[str] | None = None
        self.last_summary = ""
        self._build_ui()
        self.connect("delete-event", self.on_window_delete)
        self.refresh_state()
        GLib.timeout_add_seconds(3, self.refresh_state)

    def _build_ui(self) -> None:
        header = Gtk.HeaderBar(title="Fingerprint Setup", subtitle=f"Goodix {USB_ID}")
        header.set_show_close_button(True)
        refresh = Gtk.Button.new_from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON)
        refresh.set_tooltip_text("Refresh device status")
        refresh.connect("clicked", lambda *_: self.refresh_state())
        header.pack_end(refresh)
        self.set_titlebar(header)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        outer.set_border_width(24)
        self.add(outer)

        status_frame = Gtk.Frame(label=" Device status ")
        status_grid = Gtk.Grid(column_spacing=18, row_spacing=10, margin=16)
        status_frame.add(status_grid)
        outer.pack_start(status_frame, False, False, 0)

        self.status_icon = Gtk.Image.new_from_icon_name(
            "dialog-information-symbolic", Gtk.IconSize.DIALOG
        )
        status_grid.attach(self.status_icon, 0, 0, 1, 3)
        self.summary_label = Gtk.Label(xalign=0)
        self.summary_label.set_markup("<b>Checking reader…</b>")
        status_grid.attach(self.summary_label, 1, 0, 1, 1)
        self.hardware_label = Gtk.Label(xalign=0)
        self.driver_label = Gtk.Label(xalign=0)
        status_grid.attach(self.hardware_label, 1, 1, 1, 1)
        status_grid.attach(self.driver_label, 1, 2, 1, 1)

        action_frame = Gtk.Frame(label=" Setup and maintenance ")
        action_grid = Gtk.Grid(column_spacing=10, row_spacing=10, margin=16)
        action_frame.add(action_grid)
        outer.pack_start(action_frame, False, False, 0)

        self.install_button = self._button("Install / repair driver", "system-software-install")
        self.install_button.connect("clicked", self.on_install)
        self.rollback_button = self._button("Restore Kali packages", "edit-undo")
        self.rollback_button.connect("clicked", self.on_rollback)
        self.enroll_button = self._button("Enroll fingerprint", "list-add")
        self.enroll_button.connect("clicked", self.on_enroll)
        self.verify_button = self._button("Verify fingerprint", "emblem-ok")
        self.verify_button.connect("clicked", self.on_verify)
        self.reset_button = self._button("Reset enrolled prints", "edit-delete")
        self.reset_button.connect("clicked", self.on_reset)
        self.diagnostic_button = self._button("Save diagnostic report", "document-save")
        self.diagnostic_button.connect("clicked", self.on_diagnostic)

        action_grid.attach(self.install_button, 0, 0, 1, 1)
        action_grid.attach(self.rollback_button, 1, 0, 1, 1)
        action_grid.attach(self.enroll_button, 0, 1, 1, 1)
        action_grid.attach(self.verify_button, 1, 1, 1, 1)
        action_grid.attach(self.reset_button, 0, 2, 1, 1)
        action_grid.attach(self.diagnostic_button, 1, 2, 1, 1)

        finger_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        finger_box.pack_start(Gtk.Label(label="Finger:"), False, False, 0)
        self.finger_combo = Gtk.ComboBoxText()
        for label, value in FINGERS:
            self.finger_combo.append(value, label)
        self.finger_combo.set_active_id("right-index-finger")
        finger_box.pack_start(self.finger_combo, True, True, 0)
        action_grid.attach(finger_box, 0, 3, 2, 1)

        activity_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.spinner = Gtk.Spinner()
        self.activity_label = Gtk.Label(label="Ready", xalign=0)
        self.cancel_button = Gtk.Button(label="Cancel")
        self.cancel_button.connect("clicked", self.on_cancel)
        self.cancel_button.set_no_show_all(True)
        activity_box.pack_start(self.spinner, False, False, 0)
        activity_box.pack_start(self.activity_label, True, True, 0)
        activity_box.pack_end(self.cancel_button, False, False, 0)
        outer.pack_start(activity_box, False, False, 0)

        log_frame = Gtk.Frame(label=" Activity log ")
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.log = Gtk.TextView(editable=False, cursor_visible=False, monospace=True)
        self.log.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        scroll.add(self.log)
        log_frame.add(scroll)
        outer.pack_start(log_frame, True, True, 0)

        note = Gtk.Label(
            label="Password authentication remains enabled. PAM is never changed automatically.",
            xalign=0,
        )
        note.get_style_context().add_class("dim-label")
        outer.pack_start(note, False, False, 0)

    @staticmethod
    def _button(label: str, icon: str) -> Gtk.Button:
        button = Gtk.Button(label=label)
        button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
        button.set_always_show_image(True)
        button.set_hexpand(True)
        return button

    def append_log(self, message: str) -> bool:
        buffer = self.log.get_buffer()
        end = buffer.get_end_iter()
        buffer.insert(end, message.rstrip() + "\n")
        mark = buffer.create_mark(None, buffer.get_end_iter(), False)
        self.log.scroll_mark_onscreen(mark)
        return False

    def set_busy(self, busy: bool, message: str = "Ready") -> None:
        self.busy = busy
        self.activity_label.set_text(message)
        if busy:
            self.spinner.start()
        else:
            self.spinner.stop()
        self._update_buttons()

    def refresh_state(self) -> bool:
        if self.busy:
            return True

        def worker() -> None:
            state = collect_state()
            GLib.idle_add(self._render_state, state)

        threading.Thread(target=worker, daemon=True).start()
        return True

    def _render_state(self, state) -> bool:
        self.state = state
        summary = state_summary(state)
        self.summary_label.set_markup(f"<b>{GLib.markup_escape_text(summary)}</b>")
        self.hardware_label.set_text(
            f"Hardware: {'detected' if state.reader_present else 'not detected'} ({USB_ID})"
        )
        driver_version = state.package_versions.get("libfprint-2-tod1-goodix", "not installed")
        service = "active" if state.service_active else "idle (starts automatically)"
        self.driver_label.set_text(f"Driver: {driver_version} • fprintd: {service}")
        icon = "emblem-ok-symbolic" if state.ready else "dialog-warning-symbolic"
        self.status_icon.set_from_icon_name(icon, Gtk.IconSize.DIALOG)
        if summary != self.last_summary:
            self.append_log(summary)
            self.last_summary = summary
        self._update_buttons()
        return False

    def _update_buttons(self) -> None:
        state = getattr(self, "state", None)
        ready = bool(state and state.ready)
        present = bool(state and state.reader_present)
        installed = bool(state and (state.driver_installed or state.tod_installed))
        self.install_button.set_sensitive(not self.busy and present)
        self.rollback_button.set_sensitive(not self.busy and installed)
        self.enroll_button.set_sensitive(not self.busy and ready)
        self.verify_button.set_sensitive(not self.busy and ready)
        self.reset_button.set_sensitive(not self.busy and ready)
        self.diagnostic_button.set_sensitive(not self.busy)
        self.cancel_button.set_visible(self.busy and self.cancellable)
        self.cancel_button.set_sensitive(self.busy and self.cancellable)

    def confirm(self, title: str, detail: str, destructive: bool = False) -> bool:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.WARNING if destructive else Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.CANCEL,
            text=title,
        )
        dialog.format_secondary_text(detail)
        dialog.add_button("Continue", Gtk.ResponseType.OK)
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.OK

    def run_command(
        self,
        command: list[str],
        activity: str,
        done_message: str,
        cancellable: bool = False,
    ) -> None:
        self.cancellable = cancellable
        self.set_busy(True, activity)
        self.append_log(f"$ {' '.join(command)}")

        def worker() -> None:
            try:
                process = subprocess.Popen(
                    command,
                    cwd=ROOT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                )
                self.process = process
                assert process.stdout is not None
                for line in process.stdout:
                    GLib.idle_add(self.append_log, line)
                returncode = process.wait()
            except OSError as error:
                GLib.idle_add(self.append_log, f"Unable to start command: {error}")
                returncode = 127
            GLib.idle_add(self._command_finished, returncode, done_message)

        threading.Thread(target=worker, daemon=True).start()

    def _command_finished(self, returncode: int, done_message: str) -> bool:
        self.process = None
        self.cancellable = False
        if returncode == 0:
            self.append_log(done_message)
            self.set_busy(False, done_message)
        else:
            message = f"Command failed with exit status {returncode}"
            self.append_log(message)
            self.set_busy(False, message)
        self.refresh_state()
        return False

    def on_cancel(self, *_args) -> None:
        if self.process is not None and self.process.poll() is None and self.cancellable:
            self.append_log("Cancelling the current fingerprint operation…")
            self.process.terminate()
            self.cancel_button.set_sensitive(False)

    def on_window_delete(self, *_args) -> bool:
        if self.process is not None and self.process.poll() is None and self.cancellable:
            self.process.terminate()
        return False

    def on_install(self, *_args) -> None:
        if not self.confirm(
            "Install or repair the Goodix driver?",
            "Verified Lenovo and Canonical packages will be installed or reinstalled. "
            "The operation requires administrator authorization and will not enable PAM.",
        ):
            return
        self.run_command(
            ["pkexec", str(ROOT / "install.sh"), "--yes"],
            "Installing and checking the driver…",
            "Driver installation completed",
        )

    def on_rollback(self, *_args) -> None:
        if not self.confirm(
            "Restore Kali fingerprint packages?",
            "The proprietary driver, TOD stack, and all enrolled fingerprint "
            "templates will be removed. This cannot be undone.",
            destructive=True,
        ):
            return
        self.run_command(
            ["pkexec", str(ROOT / "uninstall.sh")],
            "Restoring Kali packages…",
            "Kali packages restored",
        )

    def on_enroll(self, *_args) -> None:
        finger = self.finger_combo.get_active_id() or "right-index-finger"
        self.run_command(
            ["fprintd-enroll", "-f", finger, self.user],
            "Touch and lift your finger when prompted…",
            "Fingerprint enrollment completed",
            cancellable=True,
        )

    def on_verify(self, *_args) -> None:
        self.run_command(
            ["fprintd-verify", self.user],
            "Touch the enrolled finger…",
            "Fingerprint verification completed",
            cancellable=True,
        )

    def on_reset(self, *_args) -> None:
        if not self.confirm(
            "Delete all enrolled fingerprints?",
            f"All fingerprint records for {self.user} will be removed. This cannot be undone.",
            destructive=True,
        ):
            return
        self.run_command(
            ["fprintd-delete", self.user],
            "Deleting enrolled fingerprints…",
            "Enrolled fingerprints deleted",
        )

    def on_diagnostic(self, *_args) -> None:
        chooser = Gtk.FileChooserDialog(
            title="Save diagnostic report",
            parent=self,
            action=Gtk.FileChooserAction.SAVE,
        )
        chooser.add_buttons(
            "Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.OK
        )
        chooser.set_current_name("goodix-550a-diagnostic.txt")
        chooser.set_do_overwrite_confirmation(True)
        response = chooser.run()
        filename = chooser.get_filename()
        chooser.destroy()
        if response != Gtk.ResponseType.OK or not filename:
            return

        self.set_busy(True, "Creating diagnostic report…")

        def worker() -> None:
            result = subprocess.run(
                [str(ROOT / "diagnose.sh")], text=True, capture_output=True, check=False
            )
            if result.returncode == 0:
                try:
                    Path(filename).write_text(result.stdout, encoding="utf-8")
                    GLib.idle_add(self._command_finished, 0, f"Report saved to {filename}")
                except OSError as error:
                    GLib.idle_add(self.append_log, f"Could not save report: {error}")
                    GLib.idle_add(self._command_finished, 1, "")
            else:
                GLib.idle_add(self.append_log, result.stderr or "Diagnostic command failed")
                GLib.idle_add(self._command_finished, result.returncode, "")

        threading.Thread(target=worker, daemon=True).start()


class GoodixApplication(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="io.github.ghostlykn1ght.Goodix550a")

    def do_activate(self) -> None:
        window = self.props.active_window or GoodixWindow(self)
        window.show_all()
        window.present()


def main() -> int:
    return GoodixApplication().run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
